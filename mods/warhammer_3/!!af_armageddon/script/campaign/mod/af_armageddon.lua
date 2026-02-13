-- Armageddon, "Total War Warhammer 3" modification

local mod_version = '3.0.11'

local settings = {
    enable_logging = false,
    regions_percent = 4,
    time_percent = 2,
    log_file_name = '!!af_armageddon.txt',
    experience_for_character = 200
}

local function log(text)
    if not settings.enable_logging then
        return
    end

    local file = io.open(settings.log_file_name, "a")

    if not file then return end

    file:write(tostring(text) .. "\n")
    file:close()
end

log('Armageddon start! ' .. os.date() .. ' v. ' .. mod_version)

local function add_xp_to_army(faction_name)
    local faction =  cm:get_faction(faction_name)  
    local force_list = faction:military_force_list()

    log('add_xp_to_army, faction: '.. faction_name)

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
        local faction =  cm:get_faction(faction_name)    
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
         ', time_gold_bonus_percent: ' .. settings.time_percent
         .. ', character exp: ' .. settings.experience_for_character
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

    local player_regions_number = player_faction:region_list():num_items()

    local time_multiplier = settings.time_percent * current_turn / 100
    local region_multiplier = settings.regions_percent * player_regions_number / 100

    local ai_income = current_faction:income()

    local gold_bonus = (region_multiplier + time_multiplier) * ai_income;

    local debug_treasury_before = current_faction:treasury()

    -- Add money
    cm:treasury_mod(current_faction_name, gold_bonus)

    local debug_treasury_after = current_faction:treasury()

    log('=========== gold_bonus ===============\n'..
        'Faction: ' .. current_faction_name ..  '\n' ..
        "$$$$ ai_income: " .. tostring(ai_income) .. '\n' ..
        "++++ gold_bonus: " .. tostring(gold_bonus) .. '\n' ..
        ". time_multiplier: " .. tostring(time_multiplier) .. '\n' ..
        ". player_regions_number: " .. tostring(player_regions_number) .. '\n' ..
        ". region_multiplier: " .. tostring(region_multiplier) .. '\n' ..        
        ". treasury_before - after: " .. tostring(debug_treasury_before) .. ' => ' .. debug_treasury_after .. '\n' ..        
        "===================="
    )

    add_xp_to_army(current_faction_name)

    add_xp_to_characters(current_faction_name)
end

core:add_listener(
    "AddMoneyToAI",
    "FactionTurnStart",
    true,
    help_ai_each_turn,
    true
)
