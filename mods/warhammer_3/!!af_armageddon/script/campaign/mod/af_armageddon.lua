-- AF Armageddon, "Total War Warhammer 3" modification
-- af_armageddon

local mod_version = '9.1.2'

local mct_mod_key = 'af_armageddon'

-- Defaults, used when MCT is not installed
local settings = {
    enable_logging = false,
    bonus_for_same_culture = false,
    bonus_for_same_culture_group = false,
    regions_percent = 4,
    time_percent = 2,
    experience_for_character = 200,
    character_experience_start_turn = 10,
    army_experience_start_turn = 10,
    -- 1 - every turn, 3 - only turns divisible by 3 (3, 6, 9 ...)
    army_experience_turn_interval = 1
}

local effect_bundles = {
    "af_armageddon_effect_bundle_ai_buff_5",
    "af_armageddon_effect_bundle_ai_buff_4",
    "af_armageddon_effect_bundle_ai_buff_3",
    "af_armageddon_effect_bundle_ai_buff_2",
    "af_armageddon_effect_bundle_ai_buff_1",
}

-- 40 day - apply_effect_bundle bundle_ai_buff_5
local effect_bundles_turns = { 40 , 35, 30, 20, 10 }

local culture_groups = {
    {
        "wh_main_emp_empire",
        "wh_main_brt_bretonnia",
        "wh_main_dwf_dwarfs",
        "wh3_main_ksl_kislev",
        "wh3_main_pro_ksl_kislev",
        "wh3_main_cth_cathay",
    },
    {
        "wh2_main_hef_high_elves",
        "wh_dlc05_wef_wood_elves",
    },
    {
        "wh_main_chs_chaos",
        "wh3_main_dae_daemons",
        "wh3_main_kho_khorne",
        "wh3_main_nur_nurgle",
        "wh3_main_sla_slaanesh",
        "wh3_main_tze_tzeentch",
        "wh_dlc08_nor_norsca",
        "wh_dlc03_bst_beastmen",        
    },
    {
        "wh3_dlc23_chd_chaos_dwarfs",
    },
    {
        "wh2_main_def_dark_elves"
    },
    {
        "wh2_main_skv_skaven"
    },
    {
        "wh2_dlc09_tmb_tomb_kings",
        "wh_main_vmp_vampire_counts",
        "wh2_dlc11_cst_vampire_coast",
        "wh3_dlc29_nag_undead_legions",
    },
    {
        "wh3_main_ogr_ogre_kingdoms",
    },
    {
        "wh2_main_lzd_lizardmen",
    },
    {
        "wh_main_grn_greenskins",
    },
    {
        "wh2_main_rogue",
    }
}

local culture_group_ids = {}

for group_id, group in ipairs(culture_groups) do
    for _, culture in ipairs(group) do
        culture_group_ids[culture] = group_id
    end
end

local function get_setting(option_key)
    local default_value = settings[option_key]

    -- Each player has own values of global options, and different values would be a desync
    if not get_mct or cm:is_multiplayer() then
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

    local file = io.open('!!af_armageddon.txt', "a")

    if not file then return end

    file:write(tostring(text) .. "\n")
    file:close()
end

local function log_errors(text)
    local file = io.open('!!af_armageddon-errors.txt', "a")

    if not file then return end

    file:write(tostring(text) .. "\n")
    file:close()
end

local function the_same_culture_group(faction_a, faction_b)
    local id_a = culture_group_ids[faction_a]
    local id_b = culture_group_ids[faction_b]

    if not id_a then
        log_errors('Faction group not found, faction: ' .. faction_a)
    end

    if not id_b then
        log_errors('Faction group not found, faction: ' .. faction_b)
    end

    return id_a ~= nil and id_a == id_b
end

local function culture_gets_bonuses(culture, player_culture)
    if culture == player_culture then
        return get_setting('bonus_for_same_culture')
    end

    -- Checked first, as this is what logs a culture missing from the groups
    return not the_same_culture_group(culture, player_culture)
        or get_setting('bonus_for_same_culture_group')
end

local function get_current_bundle_key(turn)
    for i = 1, #effect_bundles_turns do
        if turn >= effect_bundles_turns[i] then
            return effect_bundles[i]
        end 
    end

    return nil
end    

local function remove_all_effect_bundles(faction_name)
    local faction = cm:get_faction(faction_name)

    for i = 1, #effect_bundles do
        if  faction:has_effect_bundle(effect_bundles[i]) then
            cm:remove_effect_bundle(effect_bundles[i], faction_name)            
        end 
    end
end

local function set_effect_bundle(faction_name)
    local current_bundle_key = get_current_bundle_key(cm:turn_number())

    if not current_bundle_key then
        return
    end

    remove_all_effect_bundles(faction_name)

    cm:apply_effect_bundle(current_bundle_key, faction_name, 2)
end

local function add_xp_to_army(faction_name)
    local current_turn =  cm:turn_number()

    if current_turn < get_setting('army_experience_start_turn') then
        return
    end

    if current_turn % get_setting('army_experience_turn_interval') ~= 0 then
        return
    end


    local faction = cm:get_faction(faction_name)
    local force_list = faction:military_force_list()

    log('add_xp_to_army, faction: ' .. faction_name)

    for i = 0, force_list:num_items() - 1 do
        local force = force_list:item_at(i)

        if force:has_general() then
            local unit_list = force:unit_list()

            for j = 0, unit_list:num_items() - 1 do
                local unit = unit_list:item_at(j)

                if not unit:is_null_interface() then
                    local rank = unit:experience_level()

                    if rank < 9 then
                        cm:add_experience_to_unit(unit, 1)
                    end

                    local new_rank = unit:experience_level()

                    log(
                        'unit ' .. unit:unit_key()
                        .. ' rank: ' .. tostring(rank) .. ' => ' .. tostring(new_rank)
                    )
                end
            end
        end
    end
end

local function add_xp_to_characters(faction_name)
    local current_turn = cm:turn_number()

    if current_turn < get_setting('character_experience_start_turn') then
        return
    end

    local faction = cm:get_faction(faction_name)
    local xp_bonus = current_turn * get_setting('experience_for_character')

    local characters = faction:character_list()

    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)

        local character_str = cm:char_lookup_str(character)

        local level_before = character:rank()

        cm:add_agent_experience(character_str, xp_bonus)

        local level_after = character:rank()

        local name = character:character_subtype_key()

        log('add xp to character ' .. name .. ' : ' .. tostring(xp_bonus)
            .. ' level: ' .. tostring(level_before) .. ' => ' .. tostring(level_after)
        )
    end
end

local function help_ai_each_turn(context)
    local current_faction = context:faction()
    local current_faction_name = current_faction:name()
    local current_turn = cm:turn_number()

    if (current_faction:is_rebel()) then
        return
    end

    if current_faction:is_human() then
        return
    end

    -- Not the local faction: in multiplayer it's different on each machine, a desync again
    local player_faction_name = cm:get_human_factions()[1]
    local player_faction = cm:get_faction(player_faction_name)

    local current_culture = current_faction:culture()
    local player_culture = player_faction:culture()

    if not culture_gets_bonuses(current_culture, player_culture) then
        return
    end

    local player_regions_number = player_faction:region_list():num_items()

    local time_multiplier = get_setting('time_percent') * current_turn / 100
    local region_multiplier = get_setting('regions_percent') * player_regions_number / 100

    local ai_income = current_faction:income()

    local gold_bonus = (region_multiplier + time_multiplier) * ai_income;

    local debug_treasury_before = current_faction:treasury()

    -- Add money
    cm:treasury_mod(current_faction_name, gold_bonus)

    local debug_treasury_after = current_faction:treasury()

    log('=========== gold_bonus ===============\n' ..
        'Faction: ' .. current_faction_name .. '\n' ..
        "$$$$ ai_income: " .. tostring(ai_income) .. '\n' ..
        "++++ gold_bonus: " .. tostring(gold_bonus) .. '\n' ..
        ". time_multiplier: " .. tostring(time_multiplier) .. '\n' ..
        ". player_regions_number: " .. tostring(player_regions_number) .. '\n' ..
        ". region_multiplier: " .. tostring(region_multiplier) .. '\n' ..
        ". treasury_before - after: " ..
        tostring(debug_treasury_before) .. ' => ' .. debug_treasury_after .. '\n' ..
        "===================="
    )

    add_xp_to_characters(current_faction_name)

    add_xp_to_army(current_faction_name)

    set_effect_bundle(current_faction_name)
end

core:add_listener(
    "AddMoneyToAI",
    "FactionTurnStart",
    true,
    help_ai_each_turn,
    true
)

-- The first tick is the earliest moment when the MCT settings are certainly loaded
cm:add_first_tick_callback(function()
    log('Armageddon start! ' .. os.date() .. ' v. ' .. mod_version)
end)
