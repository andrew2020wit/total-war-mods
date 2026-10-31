-- Runs af_armageddon.lua against a small model of the game. Run it from the repository root,
-- see af_armageddon-agent.md. It isn't part of the mod.
local mod_path = 'mods/warhammer_3/!!af_armageddon/script/campaign/mod/af_armageddon.lua'
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

-- The settings are a local table of the script, so they're changed in its text.
local function apply_settings(source, settings)
    for key, value in pairs(settings) do
        local changed, count = source:gsub(key .. ' = %d+', key .. ' = ' .. value)
        assert(count == 1, 'setting not found: ' .. key)
        source = changed
    end
    return source
end

-- world: { settings, last_turn, ai_culture, rank, no_general, null_unit }
-- Returns the turns on which units got experience, one entry per unit, and the error log.
local function play(world)
    local log_name = file_prefix .. 'log.txt'
    local err_name = file_prefix .. 'errors.txt'
    os.remove(log_name); os.remove(err_name)

    local turn = 0
    local turn_listener
    local xp_turns = {}
    local env = setmetatable({}, { __index = _G })

    env.io = {
        open = function(name, mode)
            local map = {
                ['!!af_armageddon.txt'] = log_name,
                ['!!af_armageddon-errors.txt'] = err_name
            }
            return io.open(map[name], mode)
        end
    }

    local unit = {
        is_null_interface = function() return world.null_unit == true end,
        experience_level = function() return world.rank or 0 end,
        unit_key = function() return 'unit' end
    }
    local force = {
        has_general = function() return not world.no_general end,
        unit_list = function() return list({ unit }) end
    }
    local ai = {
        name = function() return 'ai' end,
        is_rebel = function() return false end,
        is_human = function() return false end,
        culture = function() return world.ai_culture or 'wh_main_grn_greenskins' end,
        income = function() return 1000 end,
        treasury = function() return 0 end,
        military_force_list = function() return list({ force }) end,
        character_list = function() return list({}) end,
        has_effect_bundle = function() return false end
    }
    local player = {
        culture = function() return 'wh_main_emp_empire' end,
        region_list = function() return list({}) end
    }

    env.cm = {
        turn_number = function() return turn end,
        get_faction = function(_, name) return name == 'ai' and ai or player end,
        get_local_faction_name = function() return 'player' end,
        treasury_mod = function() end,
        apply_effect_bundle = function() end,
        remove_effect_bundle = function() end,
        add_experience_to_unit = function() xp_turns[#xp_turns + 1] = turn end
    }
    env.core = {
        add_listener = function(_, _, event, _, handler)
            assert(event == 'FactionTurnStart', event)
            turn_listener = handler
        end
    }

    assert(load(apply_settings(mod_source, world.settings or {}), 'af_armageddon', 't', env))()

    for current = 1, world.last_turn do
        turn = current
        turn_listener({ faction = function() return ai end })
    end

    return table.concat(xp_turns, ','), read_file(err_name)
end

local function check_turns(name, world, expected)
    local turns, errors = play(world)
    check(name, turns == expected, turns)
    check(name .. ': no errors', errors == '', errors)
end

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
check_turns('no experience for the culture group of the player', {
    last_turn = 12,
    ai_culture = 'wh_main_dwf_dwarfs'
}, '')

print(failed == 0 and 'ALL PASSED' or (failed .. ' FAILED'))
os.exit(failed == 0 and 0 or 1)
