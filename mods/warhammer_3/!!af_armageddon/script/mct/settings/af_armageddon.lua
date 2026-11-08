-- AF Armageddon settings for Mod Configuration Tool

if not get_mct then
    return
end

local mod_version = '9.8.0'

local mct_mod = get_mct():register_mod("af_armageddon")

mct_mod:set_title("AF Armageddon v" .. mod_version)
mct_mod:set_author("Andrew Faurash")
mct_mod:set_description("Increases difficulty for the middle and late game: AI factions get bonuses that grow over time.")

-- All the options but the log belong to a campaign (set_is_global(false)): MCT keeps them in the
-- save, and a value set in the main menu applies to the next new campaign only

mct_mod:add_new_section("gold", "Gold")

local regions_percent = mct_mod:add_new_option("regions_percent", "slider")
regions_percent:set_text("Percent of income per player region")
regions_percent:set_tooltip_text("Each region of the player adds this percent of the AI faction's income to its bonus gold.")
regions_percent:slider_set_min_max(0, 100)
regions_percent:slider_set_step_size(1)
regions_percent:set_default_value(4)
regions_percent:set_is_global(false)

local time_percent = mct_mod:add_new_option("time_percent", "slider")
time_percent:set_text("Percent of income per turn")
time_percent:set_tooltip_text("Each turn of the campaign adds this percent of the AI faction's income to its bonus gold.")
time_percent:slider_set_min_max(0, 100)
time_percent:slider_set_step_size(1)
time_percent:set_default_value(2)
time_percent:set_is_global(false)

mct_mod:add_new_section("character_experience", "Character experience")

local experience_for_character = mct_mod:add_new_option("experience_for_character", "slider")
experience_for_character:set_text("Experience per turn number")
experience_for_character:set_tooltip_text("Each character of the AI faction gets this amount multiplied by the turn number, every turn.")
experience_for_character:slider_set_min_max(0, 5000)
experience_for_character:slider_set_step_size(50)
experience_for_character:set_default_value(200)
experience_for_character:set_is_global(false)

local character_start_turn = mct_mod:add_new_option("character_experience_start_turn", "slider")
character_start_turn:set_text("Start turn")
character_start_turn:set_tooltip_text("Characters get experience from this turn on.")
character_start_turn:slider_set_min_max(1, 200)
character_start_turn:slider_set_step_size(1)
character_start_turn:set_default_value(10)
character_start_turn:set_is_global(false)

mct_mod:add_new_section("army_experience", "Unit experience")

local army_start_turn = mct_mod:add_new_option("army_experience_start_turn", "slider")
army_start_turn:set_text("Start turn")
army_start_turn:set_tooltip_text("Units in armies with a general get experience from this turn on.")
army_start_turn:slider_set_min_max(1, 200)
army_start_turn:slider_set_step_size(1)
army_start_turn:set_default_value(10)
army_start_turn:set_is_global(false)

local army_turn_interval = mct_mod:add_new_option("army_experience_turn_interval", "slider")
army_turn_interval:set_text("Every n-th turn")
army_turn_interval:set_tooltip_text("1 - every turn, 3 - only turns divisible by 3 (3, 6, 9 ...). Divided by the bonus multiplier of the culture and rounded, but never below 1.")
army_turn_interval:slider_set_min_max(1, 50)
army_turn_interval:slider_set_step_size(1)
army_turn_interval:set_default_value(2)
army_turn_interval:set_is_global(false)

mct_mod:add_new_section("debug", "Debug")

local logging = mct_mod:add_new_option("enable_logging", "checkbox")
logging:set_text("Write a log file")
logging:set_tooltip_text("Writes !!af_armageddon.txt to the game folder.")
logging:set_default_value(false)
-- The only global option: the log is for finding problems, not a part of a campaign
logging:set_is_global(true)

-- The last section: MCT puts ceil(n / 2) sections into the first column, so this long list gets
-- the scroll of the second column and doesn't push the other settings down
mct_mod:add_new_section("bonus_multiplier", "Bonus multiplier for cultures")

-- The keys of db/cultures_tables, by their English names, without the prologue Kislev
local cultures = {
    "wh_dlc03_bst_beastmen",
    "wh_main_brt_bretonnia",
    "wh3_dlc23_chd_chaos_dwarfs",
    "wh3_main_dae_daemons",
    "wh2_main_def_dark_elves",
    "wh_main_dwf_dwarfs",
    "wh3_main_cth_cathay",
    "wh_main_grn_greenskins",
    "wh2_main_hef_high_elves",
    "wh3_main_kho_khorne",
    "wh3_main_ksl_kislev",
    "wh2_main_lzd_lizardmen",
    "wh_dlc08_nor_norsca",
    "wh3_main_nur_nurgle",
    "wh3_main_ogr_ogre_kingdoms",
    "wh2_main_rogue",
    "wh2_main_skv_skaven",
    "wh3_main_sla_slaanesh",
    "wh_main_emp_empire",
    "wh2_dlc09_tmb_tomb_kings",
    "wh3_main_tze_tzeentch",
    "wh3_dlc29_nag_undead_legions",
    "wh2_dlc11_cst_vampire_coast",
    "wh_main_vmp_vampire_counts",
    "wh_main_chs_chaos",
    "wh_dlc05_wef_wood_elves",
}

-- The keys of the dropdown are strings, the script turns them into numbers. 0 turns the bonuses off
local bonus_multipliers = { "0", "0.1", "0.25", "0.5", "0.75", "1", "1.25", "1.5", "1.75", "2", "3", "4", "5" }
local bonus_multiplier_values = {}

for _, multiplier in ipairs(bonus_multipliers) do
    bonus_multiplier_values[#bonus_multiplier_values + 1] = {
        key = multiplier,
        -- Not a loc key: MCT shows such a text as it is
        text = multiplier,
        is_default = multiplier == "1"
    }
end

for _, culture in ipairs(cultures) do
    local bonus_multiplier = mct_mod:add_new_option("bonus_multiplier_" .. culture, "dropdown")
    -- A loc key of the game: MCT shows the name in the language of the game
    bonus_multiplier:set_text("cultures_name_" .. culture)
    bonus_multiplier:set_tooltip_text("The gold and the character experience of the AI factions of this culture are multiplied by this value, the interval of the unit experience is divided by it. The effect bundle doesn't change. 0 turns off all the bonuses of this culture, the effect bundle included. It applies to the AI factions of the player's culture too.")
    bonus_multiplier:add_dropdown_values(bonus_multiplier_values)
    -- Each campaign has its own values: MCT keeps them in the save
    bonus_multiplier:set_is_global(false)
end
