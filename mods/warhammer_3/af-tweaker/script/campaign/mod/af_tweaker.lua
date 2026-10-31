-- AF Tweaker, "Total War Warhammer 3" modification
-- af_tweaker

local mod_version = '0.1.4'

local mct_mod_key = 'af_tweaker'

-- enable_logging, auto_upgrade_enabled and min_treasury are defaults, used when MCT is not installed
local settings = {
    enable_logging = false,
    auto_upgrade_enabled = true,
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

local function is_level_available(region, region_cqi, slot_index, level_key)
    local slot = slot_expression(slot_index)
    local level = level_expression(slot_index, level_key)

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

    if not is_level_available(region, region_cqi, slot_index, upgrade_key) then
        return
    end

    local level = level_expression(slot_index, upgrade_key)
    local cost = get_value(region_cqi, level .. '.CreateCost(this)')

    if not cost then
        log_errors('Building cost not found: ' .. upgrade_key)
        return
    end

    if cost > cycle.budget then
        return
    end

    common.call_context_command(settlement_context, region_cqi,
        level .. '.IssueCommandForBuildingBrowser(' .. slot_expression(slot_index) .. ')'
    )

    local budget_before = cycle.budget

    cycle.budget = budget_before - cost
    cycle.spent = cycle.spent + cost
    cycle.upgraded = cycle.upgraded + 1

    log('upgrade ' .. building_title(level_key) .. ' => ' .. building_title(upgrade_key)
        .. ', region: ' .. region_title(region)
        .. ', cost: ' .. tostring(cost) .. ', budget: ' .. tostring(budget_before) .. ' => ' .. tostring(cycle.budget)
    )
end

local function upgrade_region(region, cycle)
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

        upgrade_slot(region, region_cqi, slot_index, cycle)
    end
end

-- The treasury is read once: commands are asynchronous, it doesn't change during this loop.
local function upgrade_buildings(faction_name)
    local faction = cm:get_faction(faction_name)
    local min_treasury = get_setting('min_treasury')
    local treasury = faction:treasury()
    local budget = treasury - min_treasury
    local cycle = { budget = budget, spent = 0, upgraded = 0 }

    log('auto upgrade, turn: ' .. tostring(cm:turn_number()) .. ', treasury: ' .. tostring(treasury)
        .. ', min_treasury: ' .. tostring(min_treasury) .. ', budget: ' .. tostring(budget)
    )

    local region_list = faction:region_list()

    for i = 0, region_list:num_items() - 1 do
        if cycle.budget <= 0 then
            break
        end

        upgrade_region(region_list:item_at(i), cycle)
    end

    log('auto upgrade done, budget at start: ' .. tostring(budget)
        .. ', buildings upgraded: ' .. tostring(cycle.upgraded)
        .. ', total spent: ' .. tostring(cycle.spent)
        .. ', budget at end: ' .. tostring(cycle.budget)
    )
end

local function on_player_turn_start(context)
    if not get_setting('auto_upgrade_enabled') then
        return
    end

    local faction_name = context:faction():name()

    -- The context objects are read from the UI, they are not synchronized in multiplayer
    if cm:is_multiplayer() then
        return
    end

    cm:callback(function()
        local is_ok, error_text = pcall(upgrade_buildings, faction_name)

        if not is_ok then
            log_errors('upgrade_buildings: ' .. tostring(error_text))
        end
    end, settings.turn_start_delay)
end

-- The first tick is the earliest moment when the MCT settings are certainly loaded
cm:add_first_tick_callback(function()
    log('Tweaker start! ' .. os.date() .. ' v. ' .. mod_version)
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
