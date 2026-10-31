-- AF Tweaker, "Total War Warhammer 3" modification
-- af_tweaker

local mod_version = '0.5.1'

local mct_mod_key = 'af_tweaker'

-- All values except the timings and the limits are defaults, used when MCT is not installed
local settings = {
    enable_logging = false,
    auto_upgrade_enabled = true,
    favorite_buildings_enabled = true,
    auto_skills_enabled = true,
    min_treasury = 5000,
    turn_start_delay = 0.5,
    round_delay = 0.5,
    skill_commit_rounds = 3,
    ui_poll_ms = 250,
    ui_poll_max_failures = 10
}

local settlement_context = 'CcoCampaignSettlement'
local slot_context = 'CcoCampaignBuildingSlot'

-- Lives in the game folder, not in a save: favorites are shared by all campaigns
local favorites_file_name = '!!af_tweaker-favorites.txt'
local popup_name = 'building_construction_popup'
local favorite_button_name = 'af_tweaker_favorite_button'
local favorite_button_template = 'ui/templates/round_small_button_toggle'
local favorite_button_icon = 'ui/skins/default/af_tweaker_favorite_star.png'

local character_context = 'CcoCampaignCharacter'

-- In the game folder too, for the same reason as the favorites
local skill_priorities_file_name = '!!af_tweaker-skill-priorities.txt'
local skill_panel_name = 'character_details_panel_skills'
local skill_button_name = 'af_tweaker_skill_priority_button'
local skill_button_template = 'ui/templates/round_extra_small_button'
local skill_button_transparent_image = 'ui/skins/default/1x1_transparent_white.png'
local skill_max_priority = 3

local favorites = {}
local favorite_button_key = nil
local favorite_button_slot_id = nil
local hovered_slot_id = nil
local skill_priorities = {}

local function get_setting(option_key)
    local default_value = settings[option_key]

    if not get_mct then
        return default_value
    end

    local mct_mod = get_mct():get_mod_by_key(mct_mod_key)

    if not mct_mod then
        return default_value
    end

    local option = mct_mod:get_option_by_key(option_key)

    if not option then
        return default_value
    end

    local value = option:get_finalized_setting()

    if value == nil then
        return default_value
    end

    return value
end

-- Call sites check it first when building the text takes context queries
local function is_logging_enabled()
    return get_setting('enable_logging')
end

local function append_line(file_name, text)
    local file = io.open(file_name, "a")

    if not file then return end

    file:write(tostring(text) .. "\n")
    file:close()
end

local function log(text)
    if is_logging_enabled() then
        append_line('!!af_tweaker.txt', text)
    end
end

local function log_errors(text)
    append_line('!!af_tweaker-errors.txt', text)
end

-- Repeats a round while it returns true. Commands are asynchronous, so the game needs the
-- delay to process the ones of a round before the next round reads its data.
local function run_rounds(name, round, on_done)
    local is_ok, has_more = pcall(round)

    if not is_ok then
        log_errors(name .. ': ' .. tostring(has_more))
        return
    end

    if has_more then
        cm:callback(function()
            run_rounds(name, round, on_done)
        end, settings.round_delay)
    else
        on_done()
    end
end

-- All expressions are evaluated on the settlement context, so `this` is the settlement.
-- The building cost comes from the game itself, not from a table in this script:
-- it already includes other mods (Radious rewrites most of building_levels) and discounts.
local function get_value(region_cqi, expression)
    return common.get_context_value(settlement_context, region_cqi, expression)
end

local function with_name(name, key)
    if not name or name == '' then
        return key
    end

    return name .. ' (' .. key .. ')'
end

local function building_title(level_key)
    return with_name(
        common.get_context_value('CcoBuildingLevelRecord', level_key, 'PlayerVariantRecordContext.Name'),
        level_key
    )
end

local function region_title(region)
    return with_name(get_value(region:cqi(), 'this.Name'), region:name())
end

local function slot_expression(slot_index)
    return 'this.BuildingSlotList.At(' .. slot_index .. ')'
end

local function level_expression(slot_index, level_key)
    return slot_expression(slot_index)
        .. '.BuildingContext.BuildingLevelRecordContext.BuildingChainRecordContext'
        .. '.LevelsList.FirstContext(Key == "' .. level_key .. '")'
end

local function is_slot_ready(region_cqi, slot_index)
    local slot = slot_expression(slot_index)

    return get_value(region_cqi, slot .. '.IsEmpty == false && ' .. slot .. '.CanUpgrade'
        .. ' && IsContextValid(' .. slot .. '.ConstructionItemContext) == false'
        .. ' && IsContextValid(' .. slot .. '.LifecycleStateContext) == false'
    )
end

-- Stays on the current chain. A choice inside the chain is left to the player.
local function find_upgrade_key(level_key)
    local upgrades = cm:get_building_level_upgrades(level_key)

    if not upgrades then
        return nil
    end

    local chain_key = cm:building_chain_key_for_building(level_key)
    local upgrade_key = nil

    for _, key in pairs(upgrades) do
        if cm:building_chain_key_for_building(key) == chain_key then
            if upgrade_key then
                if is_logging_enabled() then
                    log('skip branching building: ' .. building_title(level_key))
                end

                return nil
            end

            upgrade_key = key
        end
    end

    return upgrade_key
end

local function uses_development_points(region_cqi, level)
    local development_points = get_value(region_cqi, level .. '.DevelopmentPointCost(this)')

    return development_points ~= nil and development_points > 0
end

local function uses_pooled_resources(region_cqi, slot_index, level)
    local cost = level .. '.ResourceCostContext(' .. slot_expression(slot_index) .. ')'

    return get_value(region_cqi, 'IsContextValid(' .. cost .. ')'
        .. ' && ' .. cost .. '.PooledResourceTransactionList.IsEmpty == false'
    )
end

local function is_level_available(region_cqi, slot_index, level)
    local slot = slot_expression(slot_index)

    return get_value(region_cqi, level .. '.IsLockedByAnyTech == false'
        .. ' && ' .. level .. '.IsLockedByLevel(' .. slot .. ') == false'
        .. ' && ' .. level .. '.CanAfford(this)'
        .. ' && ' .. level .. '.CanAffordResourceCostForSlot(' .. slot .. ')'
    )
end

-- Building caps have the same blind spot as the costs below, and the script doesn't know which
-- building has one. So the first copy of a favorite goes alone, which is enough for a cap of
-- one per faction, and then a round takes one copy per province, enough for one per province.
local function waits_for_cap(cycle, level_key, province_name)
    local provinces = cycle.round_favorites[level_key]

    return provinces ~= nil and (provinces[province_name] or not cycle.known_favorites[level_key])
end

-- What waits keeps its gold until the next round, or something later in the order would take it
local function defer_level(region, cost, cycle)
    cycle.has_deferred = true
    cycle.recheck_regions[region:name()] = true
    cycle.budget = cycle.budget - cost
    cycle.reserved = cycle.reserved + cost
end

-- The game checks development points and pooled resources against what it has now, and
-- commands are asynchronous. Only gold is counted in the script, so the others get one
-- building per round: per province for development points, per faction for resources.
-- Returns the cost if the building was queued, or nil and true if it waits for the next round.
local function queue_level(region, region_cqi, slot_index, level, level_key, cycle, is_favorite)
    local slot_key = region_cqi .. ':' .. slot_index

    -- The game can be slower than a round, and a refused command must not repeat each round
    if cycle.queued_slots[slot_key] or not is_level_available(region_cqi, slot_index, level) then
        return nil
    end

    local cost = get_value(region_cqi, level .. '.CreateCost(this)')

    if not cost then
        log_errors('Building cost not found: ' .. level_key)
        return nil
    end

    if cost > cycle.budget then
        -- The gold of a waiting building can come back in the next round
        if cycle.reserved > 0 then
            cycle.recheck_regions[region:name()] = true
        end

        return nil
    end

    local province_name = region:province_name()
    local has_development_cost = uses_development_points(region_cqi, level)
    local has_resource_cost = uses_pooled_resources(region_cqi, slot_index, level)

    if has_development_cost and not region:has_development_points_to_upgrade() then
        return nil
    end

    if (has_development_cost and cycle.development_provinces[province_name])
        or (has_resource_cost and cycle.pooled_resources_used)
        or (is_favorite and waits_for_cap(cycle, level_key, province_name)) then
        defer_level(region, cost, cycle)
        return nil, true
    end

    common.call_context_command(settlement_context, region_cqi,
        level .. '.IssueCommandForBuildingBrowser(' .. slot_expression(slot_index) .. ')'
    )

    cycle.queued_slots[slot_key] = true
    cycle.budget = cycle.budget - cost
    cycle.spent = cycle.spent + cost

    if has_resource_cost then
        cycle.pooled_resources_used = true
    end

    if has_development_cost then
        cycle.development_provinces[province_name] = true
    end

    if is_favorite then
        local provinces = cycle.round_favorites[level_key] or {}

        provinces[province_name] = true
        cycle.round_favorites[level_key] = provinces
    end

    return cost
end

local function log_queued(text, region, cost, cycle)
    log(text .. ', region: ' .. region_title(region)
        .. ', cost: ' .. tostring(cost)
        .. ', budget: ' .. tostring(cycle.budget + cost) .. ' => ' .. tostring(cycle.budget)
    )
end

local function upgrade_slot(region, region_cqi, slot_index, cycle)
    if not is_slot_ready(region_cqi, slot_index) then
        return
    end

    local level_key = get_value(region_cqi,
        slot_expression(slot_index) .. '.BuildingContext.BuildingLevelRecordContext.Key'
    )

    if not level_key then
        log_errors('Building key not found, region: ' .. region:name() .. ', slot: ' .. slot_index)
        return
    end

    local upgrade_key = find_upgrade_key(level_key)

    if not upgrade_key then
        return
    end

    local level = level_expression(slot_index, upgrade_key)
    local cost = queue_level(region, region_cqi, slot_index, level, upgrade_key, cycle)

    if not cost then
        return
    end

    cycle.upgraded = cycle.upgraded + 1

    if is_logging_enabled() then
        log_queued('upgrade ' .. building_title(level_key) .. ' => ' .. building_title(upgrade_key), region, cost, cycle)
    end
end

local function load_favorites()
    local file = io.open(favorites_file_name, "r")

    if not file then return end

    for line in file:lines() do
        local key = string.match(line, '^%s*(.-)%s*$')

        if key ~= '' then
            table.insert(favorites, key)
        end
    end

    file:close()
end

local function save_favorites()
    local file = io.open(favorites_file_name, "w")

    if not file then
        log_errors('Cannot write ' .. favorites_file_name)
        return
    end

    file:write(table.concat(favorites, "\n") .. "\n")
    file:close()
end

local function find_favorite_index(level_key)
    for index, key in ipairs(favorites) do
        if key == level_key then
            return index
        end
    end

    return nil
end

local function toggle_favorite(level_key)
    local index = find_favorite_index(level_key)

    if index then
        table.remove(favorites, index)
    else
        table.insert(favorites, level_key)
    end

    save_favorites()

    if is_logging_enabled() then
        log((index and 'favorite removed: ' or 'favorite added: ') .. building_title(level_key))
    end
end

-- The list is shared with other campaigns, so it can hold keys from mods that are off now
local function get_valid_favorites()
    local valid_favorites = {}

    for _, key in ipairs(favorites) do
        if common.get_context_value('CcoBuildingLevelRecord', key, 'Key') == key then
            table.insert(valid_favorites, key)
        else
            log('unknown favorite building: ' .. key)
        end
    end

    return valid_favorites
end

local function is_slot_free(region_cqi, slot_index)
    local slot = slot_expression(slot_index)

    return get_value(region_cqi, slot .. '.IsEmpty && ' .. slot .. '.ShouldShowSlot'
        .. ' && IsContextValid(' .. slot .. '.ConstructionItemContext) == false'
    )
end

local function favorite_expression(slot_index, level_key)
    return slot_expression(slot_index)
        .. '.PossibleBuildingChainsList.FirstContext(LevelsList.Any(Key == "' .. level_key .. '"))'
        .. '.LevelsList.FirstContext(Key == "' .. level_key .. '")'
end

-- The same checks that make a building clickable in the construction popup
local function is_favorite_buildable(region_cqi, slot_index, level)
    local slot = slot_expression(slot_index)

    if not get_value(region_cqi, 'IsContextValid(' .. level .. ')') then
        return false
    end

    return get_value(region_cqi, level .. '.IsActiveForBuildingBrowser(' .. slot .. ')'
        .. ' && ' .. level .. '.DoesBuildingExceedCap(' .. slot .. ') == false'
        .. ' && ' .. level .. '.IsEpisodicRestricted(' .. slot .. ') == false'
        .. ' && this.BuildingCanEverBeBuilt(' .. level .. ', ' .. slot .. ')'
    )
end

local function build_favorite_in_slot(region, region_cqi, slot_index, cycle, built_in_region)
    if not is_slot_free(region_cqi, slot_index) then
        return
    end

    for _, level_key in ipairs(cycle.favorites) do
        local level = favorite_expression(slot_index, level_key)

        if not built_in_region[level_key] and is_favorite_buildable(region_cqi, slot_index, level) then
            local cost, is_deferred = queue_level(region, region_cqi, slot_index, level, level_key, cycle, true)

            -- The slot is kept for it: a favorite further down the list doesn't take its place
            if is_deferred then
                return
            end

            if cost then
                built_in_region[level_key] = true
                cycle.built = cycle.built + 1

                if is_logging_enabled() then
                    log_queued('favorite ' .. building_title(level_key), region, cost, cycle)
                end

                return
            end
        end
    end
end

local function for_each_slot(region, cycle, handler)
    if region:garrison_residence():is_under_siege() then
        return
    end

    local region_cqi = region:cqi()
    local slot_number = get_value(region_cqi, 'this.BuildingSlotList.Size')

    if not slot_number then
        log_errors('Slot list not found, region: ' .. region:name())
        return
    end

    for slot_index = 0, slot_number - 1 do
        if cycle.budget <= 0 then
            break
        end

        handler(region, region_cqi, slot_index, cycle)
    end
end

-- The first round of a pass goes through all regions, the next ones only through those where
-- a round can change something: a building waits there, or the budget didn't reach them.
local function for_each_region(faction, cycle, pass, region_handler)
    local region_list = faction:region_list()
    local regions = pass.regions

    pass.regions = {}

    for i = 0, region_list:num_items() - 1 do
        local region = region_list:item_at(i)
        local region_name = region:name()

        if not regions or regions[region_name] then
            if cycle.budget > 0 then
                region_handler(region)
            end

            if cycle.budget <= 0 or cycle.recheck_regions[region_name] then
                pass.regions[region_name] = true
            end
        end
    end
end

local function build_favorites(faction, cycle)
    for_each_region(faction, cycle, cycle.favorite_pass, function(region)
        -- Commands are asynchronous, the game doesn't see this region's new buildings yet
        local built_in_region = cycle.built_in_regions[region:name()] or {}

        cycle.built_in_regions[region:name()] = built_in_region

        for_each_slot(region, cycle, function(_, region_cqi, slot_index)
            build_favorite_in_slot(region, region_cqi, slot_index, cycle, built_in_region)
        end)
    end)
end

local function upgrade_buildings(faction, cycle)
    for_each_region(faction, cycle, cycle.upgrade_pass, function(region)
        for_each_slot(region, cycle, upgrade_slot)
    end)
end

-- Returns true if a building waits for the development points or the resources of this round.
-- Upgrades wait for the favorites, which have to get the money first.
local function run_building_round(faction_name, cycle)
    local faction = cm:get_faction(faction_name)

    cycle.budget = cycle.budget + cycle.reserved
    cycle.reserved = 0

    if not faction:is_factions_turn() then
        return false
    end

    for level_key in pairs(cycle.round_favorites) do
        cycle.known_favorites[level_key] = true
    end

    cycle.has_deferred = false
    cycle.recheck_regions = {}
    cycle.round_favorites = {}
    cycle.development_provinces = {}
    cycle.pooled_resources_used = false

    if #cycle.favorites > 0 then
        build_favorites(faction, cycle)
    end

    if cycle.upgrades_enabled and not cycle.has_deferred then
        upgrade_buildings(faction, cycle)
    end

    return cycle.has_deferred
end

-- The treasury is read once: the script counts the gold it spends, so the budget holds
-- both while the commands of a round are in progress and after they're processed.
local function run_turn_start_cycle(faction_name)
    local min_treasury = get_setting('min_treasury')
    local treasury = cm:get_faction(faction_name):treasury()
    local budget = treasury - min_treasury
    local cycle = {
        budget = budget,
        spent = 0,
        upgraded = 0,
        built = 0,
        favorites = {},
        upgrades_enabled = get_setting('auto_upgrade_enabled'),
        built_in_regions = {},
        queued_slots = {},
        reserved = 0,
        round_favorites = {},
        known_favorites = {},
        favorite_pass = {},
        upgrade_pass = {}
    }

    log('auto build, turn: ' .. tostring(cm:turn_number()) .. ', treasury: ' .. tostring(treasury)
        .. ', min_treasury: ' .. tostring(min_treasury) .. ', budget: ' .. tostring(budget)
    )

    if get_setting('favorite_buildings_enabled') then
        cycle.favorites = get_valid_favorites()
    end

    run_rounds('run_building_round', function()
        return run_building_round(faction_name, cycle)
    end, function()
        log('auto build done, budget at start: ' .. tostring(budget)
            .. ', favorite buildings built: ' .. tostring(cycle.built)
            .. ', buildings upgraded: ' .. tostring(cycle.upgraded)
            .. ', total spent: ' .. tostring(cycle.spent)
            .. ', budget at end: ' .. tostring(cycle.budget)
        )
    end)
end

local function load_skill_priorities()
    local file = io.open(skill_priorities_file_name, "r")

    if not file then return end

    for line in file:lines() do
        local key, priority = string.match(line, '^%s*(.-)%s*=%s*(%d+)%s*$')

        if key then
            -- The file can be edited by hand, and an icon exists only for the valid values
            local value = math.min(tonumber(priority), skill_max_priority)

            skill_priorities[key] = value > 0 and value or nil
        end
    end

    file:close()
end

local function save_skill_priorities()
    local file = io.open(skill_priorities_file_name, "w")

    if not file then
        log_errors('Cannot write ' .. skill_priorities_file_name)
        return
    end

    local keys = {}

    for key in pairs(skill_priorities) do
        table.insert(keys, key)
    end

    table.sort(keys)

    for _, key in ipairs(keys) do
        file:write(key .. '=' .. skill_priorities[key] .. "\n")
    end

    file:close()
end

local function get_character_value(character_cqi, expression)
    return common.get_context_value(character_context, character_cqi, expression)
end

local function skill_expression(skill_index)
    return 'SkillList.At(' .. skill_index .. ')'
end

-- The game reports active, inactive (a parent skill is missing) and locked_due_to_rank.
-- Fully levelled skills are active too, and the next level can need a higher rank.
local function can_add_skill_point(character_cqi, skill_index)
    local skill = skill_expression(skill_index)

    return get_character_value(character_cqi, skill .. '.Status == "active"'
        .. ' && ' .. skill .. '.IsBackgroundSkill == false'
        .. ' && ' .. skill .. '.Level < ' .. skill .. '.TotalLevels'
        .. ' && IsContextValid(' .. skill .. '.NextLevelContext)'
        .. ' && ' .. skill .. '.NextLevelContext.RankRequired <= Rank'
    )
end

-- The keys don't change during a turn, unlike the rest of the skill data
local function get_skill_keys(character_cqi)
    local skill_number = get_character_value(character_cqi, 'SkillList.Size') or 0
    local skill_keys = {}

    for skill_index = 0, skill_number - 1 do
        skill_keys[skill_index + 1] = get_character_value(character_cqi, skill_expression(skill_index) .. '.Key') or ''
    end

    return skill_keys
end

-- Skills without a priority go last. Equal priorities go in the order of the skill tree.
local function find_next_skill(character_cqi, entry)
    local best_index = nil
    local best_key = nil
    local best_priority = -1

    for position, key in ipairs(entry.skill_keys) do
        local skill_index = position - 1
        local priority = skill_priorities[key] or 0

        if priority > best_priority and not entry.refused[key]
            and can_add_skill_point(character_cqi, skill_index) then
            best_index = skill_index
            best_key = key
            best_priority = priority
        end
    end

    return best_index, best_key, best_priority
end

local function log_skill_statuses(character_cqi, points)
    local skill_number = get_character_value(character_cqi, 'SkillList.Size') or 0
    local statuses = {}

    for skill_index = 0, skill_number - 1 do
        local status = tostring(get_character_value(character_cqi, skill_expression(skill_index) .. '.Status'))

        statuses[status] = (statuses[status] or 0) + 1
    end

    local parts = {}

    for status, count in pairs(statuses) do
        table.insert(parts, status .. ': ' .. count)
    end

    table.sort(parts)

    log('no skill to buy: ' .. tostring(get_character_value(character_cqi, 'Name'))
        .. ', points: ' .. points .. ', skills: ' .. skill_number .. ', ' .. table.concat(parts, ', ')
    )
end

-- The point is added like a click on the skill card and committed like closing the panel,
-- so the game charges it. Returns the key of the skill, if one was found.
local function spend_skill_point(character_cqi, entry, points)
    local skill_index, key, priority = find_next_skill(character_cqi, entry)

    if not skill_index then
        if is_logging_enabled() then
            log_skill_statuses(character_cqi, points)
        end

        return nil
    end

    common.call_context_command(character_context, character_cqi, skill_expression(skill_index) .. '.AddPoint')
    common.call_context_command(character_context, character_cqi, 'CommitSkillChoices')

    if is_logging_enabled() then
        log('skill: ' .. tostring(get_character_value(character_cqi, 'Name')) .. ', '
            .. with_name(get_character_value(character_cqi, skill_expression(skill_index) .. '.Name'), key)
            .. ', priority: ' .. priority
        )
    end

    return key
end

-- Returns true if the character can take the next point. A point that wasn't charged gets a
-- few rounds, as the game can be slow. After that the skill is refused until the next turn:
-- other skills may still take the points, and each refusal leaves fewer skills to try.
local function check_last_skill_point(character_cqi, entry, points, stats)
    if not entry.last_key then
        return true
    end

    if points < entry.points then
        stats.characters = stats.characters + (entry.has_spent and 0 or 1)
        stats.spent = stats.spent + entry.points - points
        entry.has_spent = true
    elseif entry.rounds_waited < settings.skill_commit_rounds then
        entry.rounds_waited = entry.rounds_waited + 1
        return false
    else
        entry.refused[entry.last_key] = true

        if is_logging_enabled() then
            log('skill point not charged: ' .. tostring(get_character_value(character_cqi, 'Name'))
                .. ', ' .. entry.last_key
            )
        end
    end

    entry.last_key = nil
    entry.rounds_waited = 0

    return true
end

-- One point per character per round. Commands are asynchronous, so only the next round sees
-- the new level of a skill, the skills it unlocked and the skills it locked.
local function run_skill_round(faction_name, waiting, stats)
    if not cm:get_faction(faction_name):is_factions_turn() then
        return false
    end

    for character_cqi, entry in pairs(waiting) do
        local points = get_character_value(character_cqi, 'SkillPointsAvailable') or 0
        local is_ready = check_last_skill_point(character_cqi, entry, points, stats)

        if points == 0 then
            waiting[character_cqi] = nil
        elseif is_ready then
            entry.skill_keys = entry.skill_keys or get_skill_keys(character_cqi)
            entry.last_key = spend_skill_point(character_cqi, entry, points)
            entry.points = points

            if not entry.last_key then
                waiting[character_cqi] = nil
            end
        end
    end

    return next(waiting) ~= nil
end

local function run_auto_skills(faction_name)
    local character_list = cm:get_faction(faction_name):character_list()
    local waiting = {}

    for i = 0, character_list:num_items() - 1 do
        local character = character_list:item_at(i)

        if not character:is_wounded() then
            waiting[character:command_queue_index()] = { refused = {}, rounds_waited = 0 }
        end
    end

    local stats = { characters = 0, spent = 0 }

    run_rounds('run_skill_round', function()
        return run_skill_round(faction_name, waiting, stats)
    end, function()
        log('auto skills done, characters: ' .. stats.characters .. ', points spent: ' .. stats.spent)
    end)
end

local function on_player_turn_start(context)
    local auto_skills_enabled = get_setting('auto_skills_enabled')
    local auto_build_enabled = get_setting('auto_upgrade_enabled') or get_setting('favorite_buildings_enabled')

    if not auto_skills_enabled and not auto_build_enabled then
        return
    end

    local faction_name = context:faction():name()

    -- The context objects are read from the UI, they are not synchronized in multiplayer
    if cm:is_multiplayer() then
        return
    end

    cm:callback(function()
        if auto_build_enabled then
            local is_ok, error_text = pcall(run_turn_start_cycle, faction_name)

            if not is_ok then
                log_errors('run_turn_start_cycle: ' .. tostring(error_text))
            end
        end

        if auto_skills_enabled then
            local is_ok, error_text = pcall(run_auto_skills, faction_name)

            if not is_ok then
                log_errors('run_auto_skills: ' .. tostring(error_text))
            end
        end
    end, settings.turn_start_delay)
end

local function find_component(parent, name)
    local address = parent:Find(name, false)

    return address and UIComponent(address) or nil
end

-- The panels are direct children of the root: unlike Find, this doesn't walk the whole UI
-- on every poll to learn that a panel is closed
local function find_panel(panel_name, name)
    local panel = find_child_uicomponent(core:get_ui_root(), panel_name)

    return panel and find_component(panel, name) or nil
end

-- Components are looked up anew on each poll: one kept between polls may be gone by then
local function find_hovered_slot()
    local settlement_list = find_panel('settlement_panel', 'settlement_list')

    if not settlement_list then
        return nil
    end

    for i = 0, settlement_list:ChildCount() - 1 do
        local slot_list = find_component(UIComponent(settlement_list:Find(i)), 'default_slots_list')

        if slot_list then
            for j = 0, slot_list:ChildCount() - 1 do
                local slot_uic = UIComponent(slot_list:Find(j))

                if slot_uic:IsMouseOverChildren() then
                    return slot_uic
                end
            end
        end
    end

    return nil
end

-- A favorite is stored as the first level of the chain: that's what an empty slot can build
local function get_slot_favorite_key(slot_id)
    local is_own_building = common.get_context_value(slot_context, slot_id,
        'IsEmpty == false && IsPlayerFaction && IsForeignSlot == false'
    )

    if not is_own_building then
        return nil
    end

    return common.get_context_value(slot_context, slot_id,
        'BuildingContext.BuildingLevelRecordContext.BuildingChainRecordContext.LevelsList.FirstContext.Key'
    )
end

local function update_favorite_button(button, level_key)
    if find_favorite_index(level_key) then
        button:SetState('selected')
        button:SetTooltipText('Remove from favorite buildings', true)
    else
        button:SetState('active')
        button:SetTooltipText('Add to favorite buildings', true)
    end
end

-- Also says if the popup is inside the slot: such a popup can't belong to another slot
local function find_options_list(slot_uic)
    local slot_popup = find_component(slot_uic, popup_name)
    local popup = slot_popup or find_component(core:get_ui_root(), popup_name)

    return popup and find_component(popup, 'options_list'), slot_popup ~= nil
end

local function refresh_favorite_button()
    local slot_uic = find_hovered_slot()
    local slot_id = slot_uic and slot_uic:GetContextObjectId(slot_context)
    local is_slot_settled = slot_id == hovered_slot_id

    hovered_slot_id = slot_id

    local level_key = slot_id and get_slot_favorite_key(slot_id)

    if not level_key then
        return
    end

    -- The game opens the popup some time after the mouse enters the slot
    local options_list, is_slot_popup = find_options_list(slot_uic)

    if not options_list then
        return
    end

    -- On the way to the star the mouse can cross another slot while this popup is still open
    local popup_slot_id = options_list:GetContextObjectId(slot_context)

    if popup_slot_id and popup_slot_id ~= '' then
        if popup_slot_id ~= slot_id then
            return
        end
    elseif not is_slot_popup and not is_slot_settled then
        -- Nothing tells whose popup it is: a slot the mouse only crosses doesn't get the star
        return
    end

    -- The option can be turned off with the button already in this popup
    if not get_setting('favorite_buildings_enabled') then
        local old_button = find_component(options_list, favorite_button_name)

        if old_button then
            old_button:SetVisible(false)
        end

        favorite_button_key = nil
        favorite_button_slot_id = nil
        return
    end

    -- Another slot of the same chain can have a popup with a star from before the last click
    if favorite_button_key == level_key and favorite_button_slot_id == slot_id
        and find_component(options_list, favorite_button_name) then
        return
    end

    local button = core:get_or_create_component(favorite_button_name, favorite_button_template, options_list)

    button:SetVisible(true)
    button:SetImagePath(favorite_button_icon, 0)
    update_favorite_button(button, level_key)
    options_list:Layout()

    favorite_button_key = level_key
    favorite_button_slot_id = slot_id
end

-- The game names the parent of a card after the skill:
-- list_box > chain1 > chain > module_<key> > <skill key> > card
local function get_card_skill_key(card)
    local parent = card:Parent()

    return parent and UIComponent(parent):Id() or nil
end

local function skill_priority_image(priority)
    return 'ui/skins/default/af_tweaker_skill_priority_' .. priority .. '.png'
end

local function update_skill_button(button, level_key)
    local priority = skill_priorities[level_key] or 0
    local image = skill_priority_image(priority)

    if button:GetImagePath(0) == image then
        return
    end

    button:SetImagePath(image, 0)

    if priority == 0 then
        button:SetTooltipText('Auto skills: no priority. Click to change.', true)
    else
        button:SetTooltipText('Auto skills: priority ' .. priority .. ' of ' .. skill_max_priority .. '. Click to change.', true)
    end
end

local function refresh_skill_card(card)
    local key = get_card_skill_key(card)

    if not key then
        return
    end

    local button = find_component(card, skill_button_name)

    if not button then
        button = core:get_or_create_component(skill_button_name, skill_button_template, card)

        -- Only the icon is shown: a round frame would leave no room for three stars
        for image_index = 1, button:NumImages() - 1 do
            button:SetImagePath(skill_button_transparent_image, image_index)
        end

        -- The top left corner: the reported size of a card is far bigger than the card you see
        button:SetDockingPoint(1)
        button:SetDockOffset(152, -24)
    end

    if not button:Visible() then
        button:SetVisible(true)
    end

    update_skill_button(button, key)
end

-- The option can be turned off with the buttons already on the cards
local function hide_skill_button(card)
    local button = find_component(card, skill_button_name)

    if button then
        button:SetVisible(false)
    end
end

local function for_each_skill_card(uic, depth, handler)
    for i = 0, uic:ChildCount() - 1 do
        local child = UIComponent(uic:Find(i))

        if child:Id() == 'card' then
            handler(child)
        elseif depth > 1 then
            for_each_skill_card(child, depth - 1, handler)
        end
    end
end

local function refresh_skill_buttons()
    local panel = find_panel('character_details_panel', skill_panel_name)

    if not panel or not panel:Visible(true) then
        return
    end

    local list_box = find_component(panel, 'list_box')

    if list_box then
        for_each_skill_card(list_box, 5,
            get_setting('auto_skills_enabled') and refresh_skill_card or hide_skill_button
        )
    end
end

local function on_skill_button_click(context)
    if not get_setting('auto_skills_enabled') then
        return
    end

    local button = UIComponent(context.component)
    local key = get_card_skill_key(UIComponent(button:Parent()))

    if not key then
        log_errors('Skill priority button: skill not found')
        return
    end

    local priority = ((skill_priorities[key] or 0) + 1) % (skill_max_priority + 1)

    skill_priorities[key] = priority > 0 and priority or nil

    save_skill_priorities()
    update_skill_button(button, key)
    log('skill priority: ' .. key .. ' = ' .. priority)
end

-- Vanilla components don't report hovers to scripts, and the game crashed in a test with
-- common.force_report_of_all_ui_script_events on, so the UI is polled instead.
-- A step survives a few failures in a row, which can come from the UI being rebuilt, and then
-- stops: it would repeat several times per second otherwise. The other step goes on.
local ui_poll_steps = {
    { name = 'refresh_favorite_button', handler = refresh_favorite_button, failures = 0 },
    { name = 'refresh_skill_buttons', handler = refresh_skill_buttons, failures = 0 }
}

local function poll_ui()
    for _, step in ipairs(ui_poll_steps) do
        if step.failures < settings.ui_poll_max_failures then
            local is_ok, error_text = pcall(step.handler)

            if is_ok then
                step.failures = 0
            else
                step.failures = step.failures + 1
                log_errors('poll_ui, ' .. step.name .. ': ' .. tostring(error_text))
            end
        end
    end
end

local function on_favorite_button_click(context)
    if not get_setting('favorite_buildings_enabled') then
        return
    end

    if not favorite_button_key then
        log_errors('Favorite button: building not found')
        return
    end

    toggle_favorite(favorite_button_key)
    update_favorite_button(UIComponent(context.component), favorite_button_key)
end

-- An error inside a UI listener is otherwise lost
local function with_error_log(name, handler)
    return function(context)
        local is_ok, error_text = pcall(handler, context)

        if not is_ok then
            log_errors(name .. ': ' .. tostring(error_text))
        end
    end
end

core:add_listener(
    "AfTweakerSkillButton",
    "ComponentLClickUp",
    function(context)
        return context.string == skill_button_name
    end,
    with_error_log('on_skill_button_click', on_skill_button_click),
    true
)

core:add_listener(
    "AfTweakerFavoriteButton",
    "ComponentLClickUp",
    function(context)
        return context.string == favorite_button_name
    end,
    with_error_log('on_favorite_button_click', on_favorite_button_click),
    true
)

load_favorites()
load_skill_priorities()

-- The first tick is the earliest moment when the MCT settings are certainly loaded
cm:add_first_tick_callback(function()
    log('Tweaker start! ' .. os.date() .. ' v. ' .. mod_version)

    -- The buttons have nothing to work with: the turn start cycle doesn't run in multiplayer
    if not cm:is_multiplayer() then
        cm:repeat_real_callback(poll_ui, settings.ui_poll_ms)
    end
end)

core:add_listener(
    "AfTweakerAutoUpgrade",
    "FactionTurnStart",
    function(context)
        return context:faction():name() == cm:get_local_faction_name(true)
    end,
    on_player_turn_start,
    true
)
