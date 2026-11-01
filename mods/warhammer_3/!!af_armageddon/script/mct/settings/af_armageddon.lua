-- AF Armageddon settings for Mod Configuration Tool

if not get_mct then
    return
end

local mod_version = '9.1.3'

local mct_mod = get_mct():register_mod("af_armageddon")

mct_mod:set_title("AF Armageddon v" .. mod_version)
mct_mod:set_author("Andrew Faurash")
mct_mod:set_description("Increases difficulty for the middle and late game: AI factions get bonuses that grow over time.")

mct_mod:add_new_section("who_gets_bonuses", "Who gets the bonuses")

local same_culture = mct_mod:add_new_option("bonus_for_same_culture", "checkbox")
same_culture:set_text("AI factions of your culture")
same_culture:set_tooltip_text("AI factions of the same culture as the player get the bonuses too.")
same_culture:set_default_value(false)
same_culture:set_is_global(true)

local same_culture_group = mct_mod:add_new_option("bonus_for_same_culture_group", "checkbox")
same_culture_group:set_text("AI factions of your culture group")
same_culture_group:set_tooltip_text("AI factions of the other cultures of the player's culture group get the bonuses too, for example Bretonnia when you play as the Empire.")
same_culture_group:set_default_value(false)
same_culture_group:set_is_global(true)

mct_mod:add_new_section("gold", "Gold")

local regions_percent = mct_mod:add_new_option("regions_percent", "slider")
regions_percent:set_text("Percent of income per player region")
regions_percent:set_tooltip_text("Each region of the player adds this percent of the AI faction's income to its bonus gold.")
regions_percent:slider_set_min_max(0, 100)
regions_percent:slider_set_step_size(1)
regions_percent:set_default_value(4)
regions_percent:set_is_global(true)

local time_percent = mct_mod:add_new_option("time_percent", "slider")
time_percent:set_text("Percent of income per turn")
time_percent:set_tooltip_text("Each turn of the campaign adds this percent of the AI faction's income to its bonus gold.")
time_percent:slider_set_min_max(0, 100)
time_percent:slider_set_step_size(1)
time_percent:set_default_value(2)
time_percent:set_is_global(true)

mct_mod:add_new_section("character_experience", "Character experience")

local experience_for_character = mct_mod:add_new_option("experience_for_character", "slider")
experience_for_character:set_text("Experience per turn number")
experience_for_character:set_tooltip_text("Each character of the AI faction gets this amount multiplied by the turn number, every turn.")
experience_for_character:slider_set_min_max(0, 5000)
experience_for_character:slider_set_step_size(50)
experience_for_character:set_default_value(200)
experience_for_character:set_is_global(true)

local character_start_turn = mct_mod:add_new_option("character_experience_start_turn", "slider")
character_start_turn:set_text("Start turn")
character_start_turn:set_tooltip_text("Characters get experience from this turn on.")
character_start_turn:slider_set_min_max(1, 200)
character_start_turn:slider_set_step_size(1)
character_start_turn:set_default_value(10)
character_start_turn:set_is_global(true)

mct_mod:add_new_section("army_experience", "Unit experience")

local army_start_turn = mct_mod:add_new_option("army_experience_start_turn", "slider")
army_start_turn:set_text("Start turn")
army_start_turn:set_tooltip_text("Units in armies with a general get experience from this turn on.")
army_start_turn:slider_set_min_max(1, 200)
army_start_turn:slider_set_step_size(1)
army_start_turn:set_default_value(10)
army_start_turn:set_is_global(true)

local army_turn_interval = mct_mod:add_new_option("army_experience_turn_interval", "slider")
army_turn_interval:set_text("Every n-th turn")
army_turn_interval:set_tooltip_text("1 - every turn, 3 - only turns divisible by 3 (3, 6, 9 ...).")
army_turn_interval:slider_set_min_max(1, 50)
army_turn_interval:slider_set_step_size(1)
army_turn_interval:set_default_value(1)
army_turn_interval:set_is_global(true)

mct_mod:add_new_section("debug", "Debug")

local logging = mct_mod:add_new_option("enable_logging", "checkbox")
logging:set_text("Write a log file")
logging:set_tooltip_text("Writes !!af_armageddon.txt to the game folder. Errors are always written to !!af_armageddon-errors.txt.")
logging:set_default_value(false)
logging:set_is_global(true)
