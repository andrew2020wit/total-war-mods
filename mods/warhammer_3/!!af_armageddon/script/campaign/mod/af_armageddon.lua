-- AF Armageddon, "Total War Warhammer 3" modification

local mod_version = '5.0.7'

local settings = {
    enable_logging = false,
    regions_percent = 4,
    time_percent = 2,
    experience_for_character = 100,
    add_chevron_each_turn = 2, -- each second turn
}

local culture_groups = {
    {
        "wh_main_emp_empire",
        "wh_main_brt_bretonnia",
        "wh_main_dwf_dwarfs",
        "wh3_main_ksl_kislev",
        "wh3_main_cth_cathay",
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
        "wh3_dlc23_chd_chaos_dwarfs",
        "wh2_main_def_dark_elves",
        "wh2_main_skv_skaven",
    },
    {
        "wh2_dlc09_tmb_tomb_kings",
        "wh_main_vmp_vampire_counts",
        "wh2_dlc11_cst_vampire_coast",
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

local function log(text)
    if not settings.enable_logging then
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

    return id_a == id_b
end

log('Armageddon start! ' .. os.date() .. ' v. ' .. mod_version)

local function add_xp_to_army(faction_name)
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
    local faction = cm:get_faction(faction_name)
    local xp_bonus = cm:turn_number() * settings.experience_for_character

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
        log('skip rebel')
        return
    end

    if current_faction:is_human() then
        log('settings, current_turn:' .. current_turn ..
            ', regions_gold_bonus_percent: ' .. settings.regions_percent ..
            ', time_gold_bonus_percent: ' .. settings.time_percent ..
            ', add_chevron_each_turn: ' .. settings.add_chevron_each_turn ..
            ', character exp: ' .. settings.experience_for_character
        )

        return
    end

    local player_faction_name = cm:get_local_faction_name(true)
    local player_faction = cm:get_faction(player_faction_name)

    local current_culture = current_faction:culture()
    local player_culture = player_faction:culture()

    log('faction: ' .. current_faction_name .. ', culture: ' .. current_culture)

    if (current_culture == player_culture) then
        log('the same culture, skip')
        return
    end

    if (the_same_culture_group(current_culture, player_culture)) then
        log('the_same_culture_group, skip')
        return
    end

    local player_regions_number = player_faction:region_list():num_items()

    local time_multiplier = settings.time_percent * current_turn / 100
    local region_multiplier = settings.regions_percent * player_regions_number / 100

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

    if current_turn % settings.add_chevron_each_turn == 0 then
        add_xp_to_army(current_faction_name)
    else
        log('skip add_xp_to_army for this turn')
    end
end

core:add_listener(
    "AddMoneyToAI",
    "FactionTurnStart",
    true,
    help_ai_each_turn,
    true
)

local function test_culture_group(culture_a, culture_b, true_result)
    local same = the_same_culture_group(culture_a, culture_b)

    local is_ok = same == true_result

    local result = 'Ok'

    if not is_ok then
        result = 'Test error!'
    end

    log_errors(result .. ' test_culture_group: ' .. culture_a .. ', ' .. culture_b .. ', result: ' .. tostring(same))
end

local function test()
    log_errors('Test, v' .. mod_version)
    test_culture_group("wh_main_chs_chaos", "wh3_main_kho_khorne", true)
    test_culture_group("wh2_main_hef_high_elves", "wh2_dlc09_tmb_tomb_kings", false)
    test_culture_group("wh3_main_ogr_ogre_kingdoms", "wh3_main_ogr_ogre_kingdoms", true)
end

--test()
