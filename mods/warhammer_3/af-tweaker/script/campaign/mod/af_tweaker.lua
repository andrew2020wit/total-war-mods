-- AF Tweaker, "Total War Warhammer 3" modification
-- af_tweaker

local mod_version = '0.2.1'

local mct_mod_key = 'af_tweaker'

-- All values except turn_start_delay are defaults, used when MCT is not installed
local settings = {
    enable_logging = false,
    auto_upgrade_enabled = true,
    favorite_buildings = '',
    min_treasury = 5000,
    turn_start_delay = 0.5
}

local settlement_context = 'CcoCampaignSettlement'

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

local function log(text)
    if not get_setting('enable_logging') then
        return
    end

    local file = io.open('!!af_tweaker.txt', "a")

    if not file then return end

    file:write(tostring(text) .. "\n")
    file:close()
end

local function log_errors(text)
    local file = io.open('!!af_tweaker-errors.txt', "a")

    if not file then return end

    file:write(tostring(text) .. "\n")
    file:close()
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
                log('skip branching building: ' .. building_title(level_key))
                return nil
            end

            upgrade_key = key
        end
    end

    return upgrade_key
end

local function is_level_available(region, region_cqi, slot_index, level)
    local slot = slot_expression(slot_index)

    local available = get_value(region_cqi, level .. '.IsLockedByAnyTech == false'
        .. ' && ' .. level .. '.IsLockedByLevel(' .. slot .. ') == false'
        .. ' && ' .. level .. '.CanAfford(this)'
        .. ' && ' .. level .. '.CanAffordResourceCostForSlot(' .. slot .. ')'
    )

    if not available then
        return false
    end

    local development_points = get_value(region_cqi, level .. '.DevelopmentPointCost(this)')

    if development_points and development_points > 0 then
        return region:has_development_points_to_upgrade()
    end

    return true
end

-- Returns the cost if the building was queued
local function queue_level(region, region_cqi, slot_index, level, level_key, cycle)
    if not is_level_available(region, region_cqi, slot_index, level) then
        return nil
    end

    local cost = get_value(region_cqi, level .. '.CreateCost(this)')

    if not cost then
        log_errors('Building cost not found: ' .. level_key)
        return nil
    end

    if cost > cycle.budget then
        return nil
    end

    common.call_context_command(settlement_context, region_cqi,
        level .. '.IssueCommandForBuildingBrowser(' .. slot_expression(slot_index) .. ')'
    )

    cycle.budget = cycle.budget - cost
    cycle.spent = cycle.spent + cost

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

    log_queued('upgrade ' .. building_title(level_key) .. ' => ' .. building_title(upgrade_key), region, cost, cycle)
end

local function parse_favorites(text)
    local favorites = {}

    for key in string.gmatch(text, '[^%s,;]+') do
        if common.get_context_value('CcoBuildingLevelRecord', key, 'Key') == key then
            table.insert(favorites, key)
        else
            log('unknown favorite building: ' .. key)
        end
    end

    return favorites
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
            local cost = queue_level(region, region_cqi, slot_index, level, level_key, cycle)

            if cost then
                built_in_region[level_key] = true
                cycle.built = cycle.built + 1

                log_queued('favorite ' .. building_title(level_key), region, cost, cycle)
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

local function for_each_region(faction, cycle, region_handler)
    local region_list = faction:region_list()

    for i = 0, region_list:num_items() - 1 do
        if cycle.budget <= 0 then
            break
        end

        region_handler(region_list:item_at(i))
    end
end

local function build_favorites(faction, cycle)
    for_each_region(faction, cycle, function(region)
        -- Commands are asynchronous, the game doesn't see this region's new buildings yet
        local built_in_region = {}

        for_each_slot(region, cycle, function(_, region_cqi, slot_index)
            build_favorite_in_slot(region, region_cqi, slot_index, cycle, built_in_region)
        end)
    end)
end

local function upgrade_buildings(faction, cycle)
    for_each_region(faction, cycle, function(region)
        for_each_slot(region, cycle, upgrade_slot)
    end)
end

-- The treasury is read once: commands are asynchronous, it doesn't change during this loop.
local function run_turn_start_cycle(faction_name)
    local faction = cm:get_faction(faction_name)
    local min_treasury = get_setting('min_treasury')
    local treasury = faction:treasury()
    local budget = treasury - min_treasury
    local cycle = { budget = budget, spent = 0, upgraded = 0, built = 0, favorites = parse_favorites(get_setting('favorite_buildings')) }

    log('auto build, turn: ' .. tostring(cm:turn_number()) .. ', treasury: ' .. tostring(treasury)
        .. ', min_treasury: ' .. tostring(min_treasury) .. ', budget: ' .. tostring(budget)
    )

    if #cycle.favorites > 0 then
        build_favorites(faction, cycle)
    end

    if get_setting('auto_upgrade_enabled') then
        upgrade_buildings(faction, cycle)
    end

    log('auto build done, budget at start: ' .. tostring(budget)
        .. ', favorite buildings built: ' .. tostring(cycle.built)
        .. ', buildings upgraded: ' .. tostring(cycle.upgraded)
        .. ', total spent: ' .. tostring(cycle.spent)
        .. ', budget at end: ' .. tostring(cycle.budget)
    )
end

local function on_player_turn_start(context)
    if not get_setting('auto_upgrade_enabled') and get_setting('favorite_buildings') == '' then
        return
    end

    local faction_name = context:faction():name()

    -- The context objects are read from the UI, they are not synchronized in multiplayer
    if cm:is_multiplayer() then
        return
    end

    cm:callback(function()
        local is_ok, error_text = pcall(run_turn_start_cycle, faction_name)

        if not is_ok then
            log_errors('run_turn_start_cycle: ' .. tostring(error_text))
        end
    end, settings.turn_start_delay)
end

local function count_available_levels(region_cqi, levels)
    local chain_number = get_value(region_cqi, 'this.PlayersFactionChainList.Size')

    if not chain_number then
        log_errors('Faction building chains not found')
        return
    end

    for chain_index = 0, chain_number - 1 do
        local level_list = 'this.PlayersFactionChainList.At(' .. chain_index .. ').LevelsList'
        local level_number = get_value(region_cqi, level_list .. '.Size') or 0

        for level_index = 0, level_number - 1 do
            local level_key = get_value(region_cqi, level_list .. '.At(' .. level_index .. ').Key')

            if level_key and level_key ~= '' then
                levels[level_key] = levels[level_key] or 0
            end
        end
    end
end

local function count_built_levels(region_cqi, levels)
    local slot_number = get_value(region_cqi, 'this.BuildingSlotList.Size') or 0

    for slot_index = 0, slot_number - 1 do
        local level_key = get_value(region_cqi,
            slot_expression(slot_index) .. '.BuildingContext.BuildingLevelRecordContext.Key'
        )

        if level_key and level_key ~= '' then
            levels[level_key] = (levels[level_key] or 0) + 1
        end
    end
end

-- Lists what the faction can build, plus anything it owns from other cultures
local function log_faction_buildings()
    if not get_setting('enable_logging') then
        return
    end

    local faction_name = cm:get_local_faction_name(true)
    local region_list = cm:get_faction(faction_name):region_list()

    if region_list:num_items() == 0 then
        log('faction buildings: ' .. faction_name .. ' has no regions')
        return
    end

    local levels = {}

    -- The chain list is the same for every settlement of the faction
    count_available_levels(region_list:item_at(0):cqi(), levels)

    for i = 0, region_list:num_items() - 1 do
        count_built_levels(region_list:item_at(i):cqi(), levels)
    end

    local level_keys = {}

    for level_key in pairs(levels) do
        table.insert(level_keys, level_key)
    end

    table.sort(level_keys)

    local lines = { 'faction buildings: ' .. faction_name .. ', levels: ' .. #level_keys }

    for _, level_key in ipairs(level_keys) do
        table.insert(lines, 'building: ' .. building_title(level_key) .. ', built: ' .. levels[level_key])
    end

    log(table.concat(lines, '\n'))
end

-- The first tick is the earliest moment when the MCT settings are certainly loaded
cm:add_first_tick_callback(function()
    log('Tweaker start! ' .. os.date() .. ' v. ' .. mod_version)

    cm:callback(function()
        local is_ok, error_text = pcall(log_faction_buildings)

        if not is_ok then
            log_errors('log_faction_buildings: ' .. tostring(error_text))
        end
    end, settings.turn_start_delay)
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
