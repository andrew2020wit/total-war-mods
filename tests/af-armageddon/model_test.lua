-- Runs af_armageddon.lua against a small model of the game. Run it from the repository root,
-- see af_armageddon-agent.md. It isn't part of the mod.
local mod_path = 'mods/warhammer_3/!!af_armageddon/script/campaign/mod/af_armageddon.lua'
local mct_path = 'mods/warhammer_3/!!af_armageddon/script/mct/settings/af_armageddon.lua'
local file_prefix = (os.getenv('TEMP') or os.getenv('TMPDIR') or '/tmp') .. '/af_armageddon_test_'

local failed = 0
local function check(name, ok, detail)
    print((ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -- ' .. tostring(detail)) or ''))
    if not ok then failed = failed + 1 end
end

local function read_file(name)
    local f = io.open(name, 'r')
    if not f then return '' end
    local text = f:read('a')
    f:close()
    return text
end

local mod_source = read_file(mod_path)
assert(mod_source ~= '', 'run it from the repository root')

local function list(items)
    return { num_items = function() return #items end, item_at = function(_, i) return items[i + 1] end }
end

-- Runs the MCT file and returns its options by key, with its title.
local function read_mct_options()
    local mct_source = read_file(mct_path)
    assert(mct_source ~= '', 'run it from the repository root')

    local options = {}
    local title
    local option_methods = {
        set_text = function() end,
        set_tooltip_text = function() end,
        set_default_value = function(self, value) self.default = value end,
        set_is_global = function(self, value) self.is_global = value end,
        slider_set_min_max = function(self, min, max) self.min, self.max = min, max end,
        slider_set_step_size = function(self, step) self.step = step end
    }
    local mct_mod = {
        set_title = function(_, text) title = text end,
        set_author = function() end,
        set_description = function() end,
        add_new_section = function() end,
        add_new_option = function(_, key, option_type)
            local option = setmetatable({ type = option_type }, { __index = option_methods })
            options[key] = option
            return option
        end
    }
    local env = setmetatable({
        get_mct = function()
            return { register_mod = function(_, key) assert(key == 'af_armageddon', key); return mct_mod end }
        end
    }, { __index = _G })

    assert(load(mct_source, 'af_armageddon_mct', 't', env))()

    return options, title
end

local mct_options, mct_title = read_mct_options()

-- The defaults are a local table of the script, so they're read from its text.
local function read_script_defaults()
    local defaults = {}
    local block = mod_source:match('local settings = (%b{})')

    for key, value in block:gmatch('([%w_]+) = (%w+)') do
        if value == 'true' or value == 'false' then
            defaults[key] = value == 'true'
        else
            defaults[key] = tonumber(value)
        end
    end

    return defaults
end

-- world: { settings, changes, no_mct, no_mct_mod, is_mp, other_is_local, last_turn, ai_culture, player_culture,
-- player_regions, rank, no_general, null_unit }
-- settings are the values of the MCT options, changes are the same by the turn they're saved on.
-- Returns what the AI got: xp_turns (one entry per unit), character_xp (turn:amount), gold_count,
-- last_gold, bundles (key by turn) and active_bundles, plus the log file in log, and in rank_reads
-- how many times the rank of a unit was read.
local function play(world)
    local log_name = file_prefix .. 'log.txt'
    os.remove(log_name)

    local turn = 0
    local turn_listener
    local xp_turns = {}
    local character_xp = {}
    local gold_count = 0
    local last_gold = 0
    local bundles, active_bundles = {}, {}
    local rank_reads = 0
    local first_tick
    local env = setmetatable({}, { __index = _G })

    env.io = {
        open = function(name, mode)
            assert(name == '!!af_armageddon.txt', name)
            return io.open(log_name, mode)
        end
    }

    local overrides = world.settings or {}

    if not world.no_mct then
        env.get_mct = function()
            return {
                get_mod_by_key = function(_, key)
                    assert(key == 'af_armageddon', key)
                    if world.no_mct_mod then return nil end
                    return {
                        get_option_by_key = function(_, option_key)
                            assert(mct_options[option_key], 'no such MCT option: ' .. option_key)
                            return { get_finalized_setting = function() return overrides[option_key] end }
                        end
                    }
                end
            }
        end
    end

    local unit = {
        is_null_interface = function() return world.null_unit == true end,
        experience_level = function()
            rank_reads = rank_reads + 1
            return world.rank or 0
        end,
        unit_key = function() return 'unit' end
    }
    local force = {
        has_general = function() return not world.no_general end,
        unit_list = function() return list({ unit }) end
    }
    local character = {
        rank = function() return 1 end,
        character_subtype_key = function() return 'character' end
    }
    local ai = {
        name = function() return 'ai' end,
        is_rebel = function() return false end,
        is_human = function() return false end,
        culture = function() return world.ai_culture or 'wh_main_grn_greenskins' end,
        income = function() return 1000 end,
        treasury = function() return 0 end,
        military_force_list = function() return list({ force }) end,
        character_list = function() return list({ character }) end,
        has_effect_bundle = function(_, key) return active_bundles[key] == true end
    }
    local player = {
        culture = function() return world.player_culture or 'wh_main_emp_empire' end,
        region_list = function()
            local regions = {}
            for i = 1, world.player_regions or 0 do regions[i] = {} end
            return list(regions)
        end
    }

    local other_player = {
        culture = function() return 'wh_main_grn_greenskins' end,
        region_list = function() return list({ {}, {}, {} }) end
    }

    env.cm = {
        add_first_tick_callback = function(_, callback) first_tick = callback end,
        turn_number = function() return turn end,
        is_multiplayer = function() return world.is_mp == true end,
        get_faction = function(_, name)
            if name == 'other' then return other_player end
            return name == 'ai' and ai or player
        end,
        get_human_factions = function() return { 'player', 'other' } end,
        get_local_faction_name = function() return world.other_is_local and 'other' or 'player' end,
        treasury_mod = function(_, _, amount)
            gold_count = gold_count + 1
            last_gold = amount
        end,
        apply_effect_bundle = function(_, key)
            bundles[turn] = key
            active_bundles[key] = true
        end,
        remove_effect_bundle = function(_, key) active_bundles[key] = nil end,
        add_experience_to_unit = function() xp_turns[#xp_turns + 1] = turn end,
        char_lookup_str = function() return 'character_lookup' end,
        add_agent_experience = function(_, _, amount)
            character_xp[#character_xp + 1] = turn .. ':' .. amount
        end
    }
    env.core = {
        add_listener = function(_, _, event, _, handler)
            assert(event == 'FactionTurnStart', event)
            turn_listener = handler
        end
    }

    assert(load(mod_source, 'af_armageddon', 't', env))()
    first_tick()

    for current = 1, world.last_turn do
        turn = current
        for key, value in pairs(world.changes and world.changes[current] or {}) do
            overrides[key] = value
        end
        turn_listener({ faction = function() return ai end })
    end

    return {
        xp_turns = table.concat(xp_turns, ','),
        character_xp = table.concat(character_xp, ','),
        gold_count = gold_count,
        last_gold = last_gold,
        bundles = bundles,
        active_bundles = active_bundles,
        rank_reads = rank_reads,
        log = read_file(log_name)
    }
end

local function check_turns(name, world, expected)
    local result = play(world)
    check(name, result.xp_turns == expected, result.xp_turns)
end

local function check_character_xp(name, world, expected)
    local result = play(world)
    check(name, result.character_xp == expected, result.character_xp)
end

-- The turn bonuses are the only sign of the culture check outside the script.
local function check_culture(name, ai_culture, player_culture, gets_bonuses, settings)
    local result = play({
        settings = settings,
        last_turn = 1,
        ai_culture = ai_culture,
        player_culture = player_culture
    })
    check(name, (result.gold_count > 0) == gets_bonuses, result.gold_count)
end

print('-- unit experience')

check_turns('by default: every turn from turn 10', { last_turn = 14 }, '10,11,12,13,14')

check_turns('the old limit of turn 30 is gone', {
    settings = { army_experience_turn_interval = 2 },
    last_turn = 34
}, '10,12,14,16,18,20,22,24,26,28,30,32,34')

check_turns('every 3rd turn, counted from turn 1', {
    settings = { army_experience_start_turn = 1, army_experience_turn_interval = 3 },
    last_turn = 10
}, '3,6,9')

check_turns('the start turn and the interval work together', {
    settings = { army_experience_turn_interval = 3 },
    last_turn = 22
}, '12,15,18,21')

check_turns('a changed start turn', {
    settings = { army_experience_start_turn = 5 },
    last_turn = 7
}, '5,6,7')

check_turns('experience starts exactly on the start turn', {
    settings = { army_experience_start_turn = 12 },
    last_turn = 12
}, '12')

check_turns('no experience at the top rank', { last_turn = 12, rank = 9 }, '')
check_turns('one rank below the top still gets it', { last_turn = 10, rank = 8 }, '10')
check_turns('no experience for an army without a general', { last_turn = 12, no_general = true }, '')
check_turns('null units are skipped', { last_turn = 12, null_unit = true }, '')
check_turns('no experience for the culture of the player', {
    last_turn = 12,
    ai_culture = 'wh_main_emp_empire'
}, '')

print('-- character experience')

check_character_xp('by default: every turn from turn 10, scaled by the turn', { last_turn = 11 }, '10:2000,11:2200')

check_character_xp('a changed start turn', {
    settings = { character_experience_start_turn = 5 },
    last_turn = 6
}, '5:1000,6:1200')

check_character_xp('it does not depend on the start turn of the units', {
    settings = { army_experience_start_turn = 20 },
    last_turn = 11
}, '10:2000,11:2200')

check_turns('the units do not depend on the start turn of the characters', {
    settings = { character_experience_start_turn = 20 },
    last_turn = 11
}, '10,11')

print('-- cultures')

local empire = 'wh_main_emp_empire'
local same_culture_on = { bonus_for_same_culture = true }

check_culture('another culture gets bonuses', 'wh_main_grn_greenskins', empire, true)
check_culture('another culture of the Order gets them', 'wh_main_dwf_dwarfs', empire, true)
check_culture('another culture of Chaos gets them', 'wh_main_chs_chaos', 'wh3_main_kho_khorne', true)
check_culture('a culture from another mod gets them', 'unknown_culture', empire, true)
check_culture('the same culture from another mod gets none', 'unknown_culture', 'unknown_culture', false)

print('-- bonuses for the culture of the player')

check_culture('off: the same culture gets none', empire, empire, false)
check_culture('on: the same culture gets bonuses', empire, empire, true, same_culture_on)
check_culture('on: another culture still gets them', 'wh_main_grn_greenskins', empire, true, same_culture_on)

do
    local result = play({
        settings = same_culture_on,
        last_turn = 10,
        ai_culture = empire
    })
    check('the same culture gets gold every turn', result.gold_count == 10, result.gold_count)
    check('the same culture gets unit experience', result.xp_turns == '10', result.xp_turns)
    check('the same culture gets character experience', result.character_xp == '10:2000', result.character_xp)
    check('the same culture gets the effect bundle',
        result.bundles[10] == 'af_armageddon_effect_bundle_ai_buff_1', result.bundles[10])
end

print('-- effect bundles')

do
    local result = play({ last_turn = 41 })
    local expected = {
        [8] = 'none',
        [9] = 'none',
        [10] = 'af_armageddon_effect_bundle_ai_buff_1',
        [19] = 'af_armageddon_effect_bundle_ai_buff_1',
        [20] = 'af_armageddon_effect_bundle_ai_buff_2',
        [30] = 'af_armageddon_effect_bundle_ai_buff_3',
        [35] = 'af_armageddon_effect_bundle_ai_buff_4',
        [39] = 'af_armageddon_effect_bundle_ai_buff_4',
        [40] = 'af_armageddon_effect_bundle_ai_buff_5',
        [41] = 'af_armageddon_effect_bundle_ai_buff_5'
    }

    for turn = 1, 41 do
        if expected[turn] then
            local bundle = result.bundles[turn] or 'none'
            check('the bundle of turn ' .. turn, bundle == expected[turn], bundle)
        end
    end

    local active = {}
    for key in pairs(result.active_bundles) do active[#active + 1] = key end
    check('only the last bundle stays active',
        #active == 1 and active[1] == 'af_armageddon_effect_bundle_ai_buff_5', table.concat(active, ','))
end

print('-- gold')

do
    local function gold(world)
        return math.floor(play(world).last_gold + 0.5)
    end

    check('by default: 2% of income per turn', gold({ last_turn = 1 }) == 20, gold({ last_turn = 1 }))
    check('time_percent comes from MCT',
        gold({ settings = { time_percent = 10 }, last_turn = 1 }) == 100,
        gold({ settings = { time_percent = 10 }, last_turn = 1 }))
    check('by default: 4% of income per region',
        gold({ last_turn = 1, player_regions = 2 }) == 100, gold({ last_turn = 1, player_regions = 2 }))
    check('regions_percent comes from MCT',
        gold({ settings = { regions_percent = 10 }, last_turn = 1, player_regions = 2 }) == 220,
        gold({ settings = { regions_percent = 10 }, last_turn = 1, player_regions = 2 }))
end

print('-- settings')

do
    local defaults = read_script_defaults()

    for key, value in pairs(defaults) do
        local option = mct_options[key]
        check('an MCT option for ' .. key, option ~= nil)
        if option then
            check(key .. ': the same default', option.default == value, option.default)
            check(key .. ': global', option.is_global == true)
            if option.type == 'slider' then
                check(key .. ': the default fits the slider',
                    value >= option.min and value <= option.max and value % option.step == 0, value)
            end
        end
    end

    for key in pairs(mct_options) do
        check('a default for the MCT option ' .. key, defaults[key] ~= nil)
    end

    check('logging is off by default', defaults.enable_logging == false)

    local version = mod_source:match("mod_version = '([%d%.]+)'")
    check('the MCT title has the version of the script', mct_title == 'AF Armageddon v' .. version, mct_title)
end

check_turns('without MCT: the defaults', { no_mct = true, last_turn = 11 }, '10,11')
check_turns('MCT without this mod: the defaults', { no_mct_mod = true, last_turn = 11 }, '10,11')

check_turns('multiplayer: the defaults, not the values of this player', {
    is_mp = true,
    settings = { army_experience_start_turn = 1, army_experience_turn_interval = 2 },
    last_turn = 11
}, '10,11')

do
    local result = play({ is_mp = true, other_is_local = true, last_turn = 1, player_regions = 1 })
    check('multiplayer: the same player on each machine', math.floor(result.last_gold + 0.5) == 60, result.last_gold)
end

check_turns('a change applies from the next turn', {
    changes = { [11] = { army_experience_turn_interval = 2 } },
    last_turn = 13
}, '10,12')

do
    local off = play({ last_turn = 10 })
    check('no log file by default', off.log == '', off.log)
    check('the log option off: nothing is read for the log', off.rank_reads == 1, off.rank_reads)

    local no_mct = play({ no_mct = true, last_turn = 10 })
    check('no log file without MCT', no_mct.log == '', no_mct.log)

    local on = play({ settings = { enable_logging = true }, last_turn = 10 })
    check('the option writes the log', on.log:find('Armageddon start!', 1, true) ~= nil)
    check('the log has the bonuses', on.log:find('add_xp_to_army', 1, true) ~= nil)
    check('the log has the units', on.log:find('rank: 0 => 0', 1, true) ~= nil, on.log)
    check('the log has the characters', on.log:find('add xp to character', 1, true) ~= nil, on.log)
    check('the log has the gold', on.log:find('treasury_before - after: 0 => 0', 1, true) ~= nil, on.log)

    local version = mod_source:match("mod_version = '([%d%.]+)'")
    check('the start line has the version', on.log:find('v. ' .. version, 1, true) ~= nil)
end

print(failed == 0 and 'ALL PASSED' or (failed .. ' FAILED'))
os.exit(failed == 0 and 0 or 1)
