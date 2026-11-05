-- AF Tweaker settings for Mod Configuration Tool

if not get_mct then
    return
end

local mod_version = '0.8.0'

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
favorites:set_tooltip_text("The star button in the popup of a building sets a priority from 1 to 3. At the start of your turn such buildings are built in free slots, higher priorities first. Buildings without a priority are not built. The minimum treasury applies.")
favorites:set_default_value(true)
favorites:set_is_global(true)

mct_mod:add_new_section("auto_skills", "Character skills")

local auto_skills = mct_mod:add_new_option("auto_skills_enabled", "checkbox")
auto_skills:set_text("Spend skill points at the start of the turn")
auto_skills:set_tooltip_text("Characters spend their skill points automatically. The star button on a skill card in the character panel sets a priority from 1 to 3: higher priorities go first, skills without a priority go last.")
auto_skills:set_default_value(true)
auto_skills:set_is_global(true)

mct_mod:add_new_section("auto_fuse", "Magic items")

local auto_fuse = mct_mod:add_new_option("auto_fuse_enabled", "checkbox")
auto_fuse:set_text("Auto fuse button in the global pool")
auto_fuse:set_tooltip_text("A button in the header of the global pool of magic items fuses unequipped items in pairs of the same rarity and category: common ones first, then uncommon ones, the new items included. Rare and unique items are kept. A fusion can't be undone.")
auto_fuse:set_default_value(true)
auto_fuse:set_is_global(true)

local auto_fuse_uncommon = mct_mod:add_new_option("auto_fuse_uncommon", "checkbox")
auto_fuse_uncommon:set_text("Fuse uncommon items too")
auto_fuse_uncommon:set_tooltip_text("On: after the common items the button fuses the uncommon ones into rare items, the ones you had before included. Off: it fuses only common items, and all uncommon ones are kept, the new ones too.")
auto_fuse_uncommon:set_default_value(true)
auto_fuse_uncommon:set_is_global(true)

mct_mod:add_new_section("debug", "Debug")

local logging = mct_mod:add_new_option("enable_logging", "checkbox")
logging:set_text("Write a log file")
logging:set_tooltip_text("Writes !!af_tweaker.txt to the game folder. Errors are always written to !!af_tweaker-errors.txt.")
logging:set_default_value(false)
logging:set_is_global(true)
