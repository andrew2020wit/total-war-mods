-- AF Armageddon, "Total War Warhammer 3" modification
-- af_armageddon

local mod_version = '9.9.0'

local mct_mod_key = 'af_armageddon'

-- Defaults, used when MCT is not installed
local settings = {
    enable_logging = false,
    regions_percent = 4,
    time_percent = 2,
    experience_for_character = 200,
    character_experience_start_turn = 10,
    army_experience_start_turn = 10,
    -- 1 - every turn, 3 - only turns divisible by 3 (3, 6, 9 ...), before the bonus multiplier
    army_experience_turn_interval = 2,
    -- How much worse the attitude of all the factions to the player gets in 10 turns, 0 turns it off
    diplomacy_penalty_per_10_turns = 5,
    diplomacy_penalty_start_turn = 20,
    diplomacy_penalty_max = 60
}

-- A culture without an option, from another mod or without MCT, gets the bonuses as they are
local default_bonus_multiplier = 1

local effect_bundles = {
    "af_armageddon_effect_bundle_ai_buff_5",
    "af_armageddon_effect_bundle_ai_buff_4",
    "af_armageddon_effect_bundle_ai_buff_3",
    "af_armageddon_effect_bundle_ai_buff_2",
    "af_armageddon_effect_bundle_ai_buff_1",
}

-- 40 day - apply_effect_bundle bundle_ai_buff_5
local effect_bundles_turns = { 40 , 35, 30, 20, 10 }

-- On the faction of the player, an empty bundle of the pack: the script adds the effect with its value
local diplomacy_penalty_bundle = "af_armageddon_effect_bundle_diplomacy_penalty"
-- The vanilla "Diplomatic relations with all factions", the Sword of Khaine has it at -10 to -40
local diplomacy_penalty_effect = "wh_main_faction_political_diplomacy_mod"
local diplomacy_penalty_effect_scope = "faction_to_faction_own_unseen"

local settings_logged_turn = 0

local function get_mct_mod()
    -- Multiplayer isn't supported: the players could have different values there, a desync
    if not get_mct or cm:is_multiplayer() then
        return nil
    end

    return get_mct():get_mod_by_key(mct_mod_key)
end

local function get_setting(option_key)
    local default_value = settings[option_key]
    local mct_mod = get_mct_mod()

    if not mct_mod then
        return default_value
    end

    -- true: no warning in the log of MCT for a culture without an option
    local option = mct_mod:get_option_by_key(option_key, true)

    if not option then
        return default_value
    end

    local value = option:get_finalized_setting()

    if value == nil then
        return default_value
    end

    return value
end

-- Call sites check it first when building the text takes calls to the game
local function is_logging_enabled()
    return get_setting('enable_logging')
end

local function log(text)
    if not is_logging_enabled() then
        return
    end

    local file = io.open('!!af_armageddon.txt', "a")

    if not file then return end

    file:write(tostring(text) .. "\n")
    file:close()
end

-- The values of the dropdown are strings, '0' to '5'. 0 turns all the bonuses of the culture off
local function get_bonus_multiplier(culture)
    local multiplier = tonumber(get_setting('bonus_multiplier_' .. culture))

    if not multiplier or multiplier < 0 then
        return default_bonus_multiplier
    end

    return multiplier
end

-- The multiplier shortens the interval: 2 makes it twice as short, 0.5 twice as long
local function get_army_experience_turn_interval(bonus_multiplier)
    local interval = math.floor(get_setting('army_experience_turn_interval') / bonus_multiplier + 0.5)

    return math.max(1, interval)
end

-- Once per turn, on the first faction. The keys come from MCT, as the cultures are listed only there
local function log_settings()
    local current_turn = cm:turn_number()

    if current_turn == settings_logged_turn or not is_logging_enabled() then
        return
    end

    settings_logged_turn = current_turn

    local mct_mod = get_mct_mod()

    if not mct_mod then
        return
    end

    local keys = {}

    for key in pairs(mct_mod:get_options()) do
        keys[#keys + 1] = key
    end

    table.sort(keys)

    local lines = { '=========== settings, turn ' .. tostring(current_turn) .. ' ===============' }

    for _, key in ipairs(keys) do
        lines[#lines + 1] = key .. ': ' .. tostring(get_setting(key))
    end

    lines[#lines + 1] = '===================='

    log(table.concat(lines, '\n'))
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

local function add_xp_to_army(faction_name, bonus_multiplier)
    local current_turn =  cm:turn_number()

    if current_turn < get_setting('army_experience_start_turn') then
        return
    end

    local interval = get_army_experience_turn_interval(bonus_multiplier)

    if current_turn % interval ~= 0 then
        return
    end

    local faction = cm:get_faction(faction_name)
    local force_list = faction:military_force_list()
    local is_logging = is_logging_enabled()

    log('add_xp_to_army, faction: ' .. faction_name .. ', every n-th turn: ' .. tostring(interval))

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

                    if is_logging then
                        log(
                            'unit ' .. unit:unit_key()
                            .. ' rank: ' .. tostring(rank) .. ' => ' .. tostring(unit:experience_level())
                        )
                    end
                end
            end
        end
    end
end

local function add_xp_to_characters(faction_name, bonus_multiplier)
    local current_turn = cm:turn_number()

    if current_turn < get_setting('character_experience_start_turn') then
        return
    end

    local faction = cm:get_faction(faction_name)
    -- Rounded: 0.25 of 50 is 12.5 per turn
    local xp_bonus = math.floor(current_turn * get_setting('experience_for_character') * bonus_multiplier + 0.5)
    local is_logging = is_logging_enabled()

    local characters = faction:character_list()

    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)

        local character_str = cm:char_lookup_str(character)

        local level_before = is_logging and character:rank()

        cm:add_agent_experience(character_str, xp_bonus)

        if is_logging then
            log('add xp to character ' .. character:character_subtype_key() .. ' : ' .. tostring(xp_bonus)
                .. ' level: ' .. tostring(level_before) .. ' => ' .. tostring(character:rank())
            )
        end
    end
end

-- From the turn, not added up turn by turn: a change of the settings applies both ways, nothing is saved
local function get_diplomacy_penalty(turn)
    local start_turn = get_setting('diplomacy_penalty_start_turn')

    if turn < start_turn then
        return 0
    end

    -- The start turn counts: 5 per 10 turns is 0.5 on it, rounded down to 0
    local penalty = math.floor((turn - start_turn + 1) * get_setting('diplomacy_penalty_per_10_turns') / 10)

    return math.max(0, math.min(get_setting('diplomacy_penalty_max'), penalty))
end

-- On each turn of the player, like Kislev does with its supporters: the old bundle goes, the new one has the
-- penalty of this turn. The culture multipliers don't change it: the effect is one for all the factions
local function update_diplomacy_penalty(faction)
    local faction_name = faction:name()
    local penalty = get_diplomacy_penalty(cm:turn_number())

    log('diplomacy penalty, faction: ' .. faction_name .. ', penalty: ' .. tostring(penalty))

    if faction:has_effect_bundle(diplomacy_penalty_bundle) then
        cm:remove_effect_bundle(diplomacy_penalty_bundle, faction_name)
    end

    if penalty == 0 then
        return
    end

    local bundle = cm:create_new_custom_effect_bundle(diplomacy_penalty_bundle)

    bundle:add_effect(diplomacy_penalty_effect, diplomacy_penalty_effect_scope, -penalty)
    -- 0: no end, it's replaced on the next turn of the player
    bundle:set_duration(0)

    cm:apply_custom_effect_bundle_to_faction(bundle, faction)
end

local function help_ai_each_turn(context)
    log_settings()

    local current_faction = context:faction()
    local current_faction_name = current_faction:name()
    local current_turn = cm:turn_number()

    if (current_faction:is_rebel()) then
        return
    end

    if current_faction:is_human() then
        -- The rules know one player, like the region count of the gold
        if current_faction_name == cm:get_human_factions()[1] then
            update_diplomacy_penalty(current_faction)
        end

        return
    end

    -- Every culture by its own multiplier, the culture of the player too: only the player itself
    -- gets nothing. For the gold, the character experience and the unit experience, not for the
    -- effect bundle
    local bonus_multiplier = get_bonus_multiplier(current_faction:culture())

    -- 0 turns off all the bonuses of the culture, the effect bundle included
    if bonus_multiplier == 0 then
        log('no bonuses for the culture, its multiplier is 0, faction: ' .. current_faction_name)
        remove_all_effect_bundles(current_faction_name)
        return
    end

    -- Not the local faction: in multiplayer it's different on each machine, a desync again
    local player_faction = cm:get_faction(cm:get_human_factions()[1])
    local player_regions_number = player_faction:region_list():num_items()

    local time_multiplier = get_setting('time_percent') * current_turn / 100
    local region_multiplier = get_setting('regions_percent') * player_regions_number / 100

    local ai_income = current_faction:income()

    -- A share of the income: a faction with a negative income gets nothing instead of losing gold
    local gold_bonus = math.max(0, (region_multiplier + time_multiplier) * ai_income * bonus_multiplier)

    local is_logging = is_logging_enabled()
    local debug_treasury_before = is_logging and current_faction:treasury()

    -- Add money
    if gold_bonus > 0 then
        cm:treasury_mod(current_faction_name, gold_bonus)
    end

    if is_logging then
        log('=========== gold_bonus ===============\n' ..
            'Faction: ' .. current_faction_name .. '\n' ..
            "$$$$ ai_income: " .. tostring(ai_income) .. '\n' ..
            "++++ gold_bonus: " .. tostring(gold_bonus) .. '\n' ..
            ". time_multiplier: " .. tostring(time_multiplier) .. '\n' ..
            ". player_regions_number: " .. tostring(player_regions_number) .. '\n' ..
            ". region_multiplier: " .. tostring(region_multiplier) .. '\n' ..
            ". bonus_multiplier: " .. tostring(bonus_multiplier) .. '\n' ..
            ". treasury_before - after: " ..
            tostring(debug_treasury_before) .. ' => ' .. current_faction:treasury() .. '\n' ..
            "===================="
        )
    end

    add_xp_to_characters(current_faction_name, bonus_multiplier)

    add_xp_to_army(current_faction_name, bonus_multiplier)

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
