-- AF Tweaker settings for Mod Configuration Tool

if not get_mct then
    return
end

local mod_version = '0.3.3'

local mct_mod = get_mct():register_mod("af_tweaker")

mct_mod:set_title("AF Tweaker v" .. mod_version)
mct_mod:set_author("Andrew Faurash")
mct_mod:set_description("Small campaign tweaks.")

mct_mod:add_new_section("auto_upgrade", "Automatic building upgrades")

local enabled = mct_mod:add_new_option("auto_upgrade_enabled", "checkbox")
enabled:set_text("Upgrade buildings at the start of the turn")
enabled:set_tooltip_text("At the start of your turn, buildings that can be upgraded are queued automatically.")
enabled:set_default_value(true)
enabled:set_is_global(true)

local min_treasury = mct_mod:add_new_option("min_treasury", "slider")
min_treasury:set_text("Minimum treasury")
min_treasury:set_tooltip_text("Automatic building only spends the money above this amount.")
min_treasury:slider_set_min_max(0, 200000)
min_treasury:slider_set_step_size(1000)
min_treasury:set_default_value(5000)
min_treasury:set_is_global(true)

mct_mod:add_new_section("favorite_buildings", "Favorite buildings")

local favorites = mct_mod:add_new_option("favorite_buildings_enabled", "checkbox")
favorites:set_text("Build favorite buildings at the start of the turn")
favorites:set_tooltip_text("Mark a building with the star button in its popup. At the start of your turn favorite buildings are built in free slots. The minimum treasury applies.")
favorites:set_default_value(true)
favorites:set_is_global(true)

mct_mod:add_new_section("debug", "Debug")

local logging = mct_mod:add_new_option("enable_logging", "checkbox")
logging:set_text("Write a log file")
logging:set_tooltip_text("Writes !!af_tweaker.txt to the game folder. Errors are always written to !!af_tweaker-errors.txt.")
logging:set_default_value(false)
logging:set_is_global(true)
