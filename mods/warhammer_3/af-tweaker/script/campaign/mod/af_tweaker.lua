-- AF Tweaker, "Total War Warhammer 3" modification
-- af_tweaker

local mod_version = '0.3.4'

local mct_mod_key = 'af_tweaker'

-- All values except the timings are defaults, used when MCT is not installed
local settings = {
    enable_logging = false,
    auto_upgrade_enabled = true,
    favorite_buildings_enabled = true,
    min_treasury = 5000,
    turn_start_delay = 0.5,
    favorite_poll_ms = 250
}

local settlement_context = 'CcoCampaignSettlement'
local slot_context = 'CcoCampaignBuildingSlot'

-- Lives in the game folder, not in a save: favorites are shared by all campaigns
local favorites_file_name = '!!af_tweaker-favorites.txt'
local popup_name = 'building_construction_popup'
local favorite_button_name = 'af_tweaker_favorite_button'
local favorite_button_poll_name = 'af_tweaker_favorite_button_poll'
local favorite_button_template = 'ui/templates/round_small_button_toggle'
local favorite_button_icon = 'ui/skins/default/af_tweaker_favorite_star.png'

local favorites = {}
local favorite_button_key = nil
local logged_hover_key = nil

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
    log((index and 'favorite removed: ' or 'favorite added: ') .. building_title(level_key))
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
    local cycle = { budget = budget, spent = 0, upgraded = 0, built = 0, favorites = {} }

    log('auto build, turn: ' .. tostring(cm:turn_number()) .. ', treasury: ' .. tostring(treasury)
        .. ', min_treasury: ' .. tostring(min_treasury) .. ', budget: ' .. tostring(budget)
    )

    if get_setting('favorite_buildings_enabled') then
        cycle.favorites = get_valid_favorites()
    end

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
    if not get_setting('auto_upgrade_enabled') and not get_setting('favorite_buildings_enabled') then
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

local function find_component(parent, name)
    local address = parent:Find(name, false)

    return address and UIComponent(address) or nil
end

-- Components are looked up anew on each poll: one kept between polls may be gone by then
local function find_hovered_slot()
    local settlement_list = find_component(core:get_ui_root(), 'settlement_list')

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
local function get_slot_favorite_key(slot_uic)
    local slot_id = slot_uic:GetContextObjectId(slot_context)

    if not slot_id then
        return nil
    end

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

local function find_options_list(slot_uic)
    local popup = find_component(slot_uic, popup_name) or find_component(core:get_ui_root(), popup_name)

    return popup and find_component(popup, 'options_list')
end

local function refresh_favorite_button()
    if not get_setting('favorite_buildings_enabled') then
        return
    end

    local slot_uic = find_hovered_slot()
    local level_key = slot_uic and get_slot_favorite_key(slot_uic)

    if not level_key then
        return
    end

    if logged_hover_key ~= level_key then
        logged_hover_key = level_key
        log('favorite button: hovered ' .. slot_uic:Id() .. ', building: ' .. level_key)
    end

    -- The game opens the popup some time after the mouse enters the slot
    local options_list = find_options_list(slot_uic)

    if not options_list then
        return
    end

    if favorite_button_key == level_key and find_component(options_list, favorite_button_name) then
        return
    end

    local button = core:get_or_create_component(favorite_button_name, favorite_button_template, options_list)

    button:SetImagePath(favorite_button_icon, 0)
    update_favorite_button(button, level_key)
    options_list:Layout()

    favorite_button_key = level_key
    log('favorite button: shown, building: ' .. level_key)
end

-- Vanilla slots don't report hovers to scripts, and the game crashed in a test with
-- common.force_report_of_all_ui_script_events on, so the slots are polled instead.
-- A failure stops the polling: it would repeat several times per second otherwise.
local function poll_favorite_button()
    local is_ok, error_text = pcall(refresh_favorite_button)

    if not is_ok then
        cm:remove_real_callback(favorite_button_poll_name)
        log_errors('refresh_favorite_button: ' .. tostring(error_text))
    end
end

local function on_favorite_button_click(context)
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
    "AfTweakerFavoriteButton",
    "ComponentLClickUp",
    function(context)
        return context.string == favorite_button_name
    end,
    with_error_log('on_favorite_button_click', on_favorite_button_click),
    true
)

load_favorites()

-- The first tick is the earliest moment when the MCT settings are certainly loaded
cm:add_first_tick_callback(function()
    log('Tweaker start! ' .. os.date() .. ' v. ' .. mod_version)

    cm:repeat_real_callback(poll_favorite_button, settings.favorite_poll_ms, favorite_button_poll_name)
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
