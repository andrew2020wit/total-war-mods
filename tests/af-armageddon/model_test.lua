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

-- Runs the MCT file and returns its options by key, with its title and the keys of its sections in order.
local function read_mct_options()
    local mct_source = read_file(mct_path)
    assert(mct_source ~= '', 'run it from the repository root')

    local options = {}
    local title
    local sections = {}
    local option_methods = {
        set_text = function(self, text) self.text = text end,
        set_tooltip_text = function() end,
        set_default_value = function(self, value) self.default = value end,
        set_is_global = function(self, value) self.is_global = value end,
        slider_set_min_max = function(self, min, max) self.min, self.max = min, max end,
        slider_set_step_size = function(self, step) self.step = step end,
        -- Like MCT: the first value is the default until one is marked as the default
        add_dropdown_values = function(self, values)
            self.values = values
            self.default = values[1].key
            for _, value in ipairs(values) do
                if value.is_default then self.default = value.key end
            end
        end
    }
    local mct_mod = {
        set_title = function(_, text) title = text end,
        set_author = function() end,
        set_description = function() end,
        add_new_section = function(_, key) sections[#sections + 1] = key end,
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

    return options, title, sections
end

local mct_options, mct_title, mct_sections = read_mct_options()

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

-- world: { settings, changes, no_mct, no_mct_mod, is_mp, other_is_local, last_turn, ai_is_human, ai_is_rebel,
-- ai_culture, player_culture, other_culture, player_regions, rank, no_general, null_unit, faction_turns,
-- income, bundles_before }
-- The AI is of the greenskins, the player of the empire and the other human player of the dwarfs by default.
-- The income of the AI is 1000 by default, bundles_before are the keys of its bundles before turn 1.
-- settings are the values of the MCT options, changes are the same by the turn they're saved on.
-- Returns what the AI got: xp_turns (one entry per unit), character_xp (turn:amount), gold_count,
-- last_gold, bundles (key by turn) and active_bundles, plus the log file in log, and in rank_reads
-- how many times the rank of a unit was read.
-- Each turn the player and the other human player start it, then the AI. What the humans got: penalties
-- (the value of the diplomacy effect by turn, for the player), and the custom bundles on them in
-- player_bundles and other_bundles (key -> { effects, duration }), stacked if a bundle was applied over
-- itself.
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
    for _, key in ipairs(world.bundles_before or {}) do active_bundles[key] = true end
    local penalties = {}
    local human_bundles = { player = {}, other = {} }
    local stacked = false
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

    local function model_option(option_key)
        return {
            get_finalized_setting = function()
                if overrides[option_key] ~= nil then return overrides[option_key] end
                return mct_options[option_key].default
            end
        }
    end

    if not world.no_mct then
        env.get_mct = function()
            return {
                get_mod_by_key = function(_, key)
                    assert(key == 'af_armageddon', key)
                    if world.no_mct_mod then return nil end
                    return {
                        get_option_by_key = function(_, option_key)
                            -- A culture from another mod has no option
                            if option_key:find('^bonus_multiplier_') and not mct_options[option_key] then
                                return nil
                            end
                            assert(mct_options[option_key], 'no such MCT option: ' .. option_key)
                            return model_option(option_key)
                        end,
                        get_options = function()
                            local options = {}
                            for option_key in pairs(mct_options) do options[option_key] = model_option(option_key) end
                            return options
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
        is_rebel = function() return world.ai_is_rebel == true end,
        is_human = function() return world.ai_is_human == true end,
        culture = function() return world.ai_culture or 'wh_main_grn_greenskins' end,
        income = function() return world.income or 1000 end,
        treasury = function() return 0 end,
        military_force_list = function() return list({ force }) end,
        character_list = function() return list({ character }) end,
        has_effect_bundle = function(_, key) return active_bundles[key] == true end
    }
    local player = {
        name = function() return 'player' end,
        is_rebel = function() return false end,
        is_human = function() return true end,
        culture = function() return world.player_culture or 'wh_main_emp_empire' end,
        has_effect_bundle = function(_, key) return human_bundles.player[key] ~= nil end,
        region_list = function()
            local regions = {}
            for i = 1, world.player_regions or 0 do regions[i] = {} end
            return list(regions)
        end
    }

    local other_player = {
        name = function() return 'other' end,
        is_rebel = function() return false end,
        is_human = function() return true end,
        culture = function() return world.other_culture or 'wh_main_dwf_dwarfs' end,
        has_effect_bundle = function(_, key) return human_bundles.other[key] ~= nil end,
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
        remove_effect_bundle = function(_, key, faction_name)
            if human_bundles[faction_name] then
                human_bundles[faction_name][key] = nil
            else
                assert(faction_name == 'ai', faction_name)
                active_bundles[key] = nil
            end
        end,
        create_new_custom_effect_bundle = function(_, key)
            local custom = { key = key, effects = {} }
            return {
                data = custom,
                add_effect = function(_, effect, scope, value)
                    custom.effects[#custom.effects + 1] = { effect = effect, scope = scope, value = value }
                end,
                set_duration = function(_, duration) custom.duration = duration end
            }
        end,
        apply_custom_effect_bundle_to_faction = function(_, bundle, faction)
            local on_faction = assert(human_bundles[faction:name()], 'a custom bundle on ' .. faction:name())
            local custom = bundle.data
            if on_faction[custom.key] then stacked = true end
            on_faction[custom.key] = custom
            if faction:name() == 'player' and #custom.effects == 1 then penalties[turn] = custom.effects[1].value end
        end,
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
        turn_listener({ faction = function() return player end })
        turn_listener({ faction = function() return other_player end })
        for _ = 1, world.faction_turns or 1 do
            turn_listener({ faction = function() return ai end })
        end
    end

    return {
        xp_turns = table.concat(xp_turns, ','),
        character_xp = table.concat(character_xp, ','),
        gold_count = gold_count,
        last_gold = last_gold,
        bundles = bundles,
        active_bundles = active_bundles,
        penalties = penalties,
        player_bundles = human_bundles.player,
        other_bundles = human_bundles.other,
        stacked = stacked,
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

print('-- unit experience')

check_turns('by default: every 2nd turn from turn 10', { last_turn = 15 }, '10,12,14')

check_turns('every turn', {
    settings = { army_experience_turn_interval = 1 },
    last_turn = 13
}, '10,11,12,13')

check_turns('the old limit of turn 30 is gone', { last_turn = 34 }, '10,12,14,16,18,20,22,24,26,28,30,32,34')

check_turns('every 3rd turn, counted from turn 1', {
    settings = { army_experience_start_turn = 1, army_experience_turn_interval = 3 },
    last_turn = 10
}, '3,6,9')

check_turns('the start turn and the interval work together', {
    settings = { army_experience_turn_interval = 3 },
    last_turn = 22
}, '12,15,18,21')

check_turns('a changed start turn', {
    settings = { army_experience_start_turn = 5, army_experience_turn_interval = 1 },
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
    last_turn = 12
}, '10,12')

print('-- who gets the bonuses')

do
    local function check_no_bonuses(name, world)
        local result = play(world)
        check(name, result.gold_count == 0 and result.xp_turns == '' and result.character_xp == ''
            and next(result.bundles) == nil, result.gold_count)
    end

    check_no_bonuses('the player gets nothing', { last_turn = 10, ai_is_human = true })
    check_no_bonuses('rebels get nothing', { last_turn = 10, ai_is_rebel = true })

    local player_culture = 'wh_main_emp_empire'

    local same = play({ ai_culture = player_culture, last_turn = 10 })
    check('the culture of the player gets all the bonuses',
        same.gold_count == 10 and same.xp_turns == '10' and same.character_xp == '10:2000'
        and same.bundles[10] == 'af_armageddon_effect_bundle_ai_buff_1',
        same.gold_count .. ', ' .. same.xp_turns .. ', ' .. same.character_xp)

    local same_gold = play({
        settings = { bonus_multiplier_wh_main_emp_empire = '2' },
        ai_culture = player_culture,
        last_turn = 1,
        player_regions = 2
    })
    check('the culture of the player gets its own multiplier',
        math.floor(same_gold.last_gold + 0.5) == 200, same_gold.last_gold)

    local same_other_multiplier = play({
        settings = { bonus_multiplier_wh_main_grn_greenskins = '2' },
        ai_culture = player_culture,
        last_turn = 1
    })
    check('the culture of the player: the multiplier of another culture changes nothing',
        math.floor(same_other_multiplier.last_gold + 0.5) == 20, same_other_multiplier.last_gold)

    check_no_bonuses('the culture of the player with the multiplier 0 gets nothing', {
        settings = { bonus_multiplier_wh_main_emp_empire = '0' },
        ai_culture = player_culture,
        last_turn = 10
    })

    local same_unknown = play({ ai_culture = 'unknown_culture', player_culture = 'unknown_culture', last_turn = 3 })
    check('the culture of the player from another mod gets the bonuses', same_unknown.gold_count == 3,
        same_unknown.gold_count)

    local same_no_mct = play({ no_mct = true, ai_culture = player_culture, last_turn = 3 })
    check('without MCT the culture of the player gets the bonuses', same_no_mct.gold_count == 3, same_no_mct.gold_count)

    local same_mp = play({ is_mp = true, other_is_local = true, ai_culture = player_culture, last_turn = 3 })
    check('multiplayer: the culture of the first player gets the bonuses', same_mp.gold_count == 3, same_mp.gold_count)

    local other = play({ last_turn = 3 })
    check('another culture gets the bonuses', other.gold_count == 3, other.gold_count)

    local unknown = play({ last_turn = 3, ai_culture = 'unknown_culture' })
    check('a culture from another mod gets the bonuses', unknown.gold_count == 3, unknown.gold_count)

    local no_mct = play({ no_mct = true, last_turn = 3 })
    check('without MCT another culture gets the bonuses', no_mct.gold_count == 3, no_mct.gold_count)

    -- Multiplayer isn't supported: the rules know one player, the first one
    local multiplayer = play({ is_mp = true, other_is_local = true, ai_culture = 'wh_main_dwf_dwarfs', last_turn = 3 })
    check('multiplayer: the culture of another human player gets the bonuses',
        multiplayer.gold_count == 3, multiplayer.gold_count)

    local logged = play({ settings = { enable_logging = true }, ai_culture = player_culture, last_turn = 1 })
    check('the log has the gold of the culture of the player',
        logged.log:find('Faction: ai', 1, true) ~= nil
        and logged.log:find('culture of the player', 1, true) == nil, logged.log)

    local greenskins_off = { bonus_multiplier_wh_main_grn_greenskins = '0' }

    check_no_bonuses('a culture with the multiplier 0 gets nothing', { settings = greenskins_off, last_turn = 10 })

    local turned_off = play({ changes = { [11] = greenskins_off }, last_turn = 12 })
    check('the multiplier 0 during the campaign removes the bundle at once',
        next(turned_off.active_bundles) == nil and turned_off.bundles[11] == nil and turned_off.gold_count == 10,
        tostring(next(turned_off.active_bundles)) .. ', gold: ' .. turned_off.gold_count)

    local other_on = play({ settings = { bonus_multiplier_wh_main_dwf_dwarfs = '0' }, last_turn = 3 })
    check('the multiplier 0 of another culture changes nothing', other_on.gold_count == 3, other_on.gold_count)

    local logged_off = play({ settings = { enable_logging = true, bonus_multiplier_wh_main_grn_greenskins = '0' }, last_turn = 1 })
    check('the log has the faction of a culture with the multiplier 0',
        logged_off.log:find('no bonuses for the culture, its multiplier is 0, faction: ai', 1, true) ~= nil, logged_off.log)

    local result = play({ last_turn = 10 })
    check('an AI faction gets gold every turn', result.gold_count == 10, result.gold_count)
    check('an AI faction gets unit experience', result.xp_turns == '10', result.xp_turns)
    check('an AI faction gets character experience', result.character_xp == '10:2000', result.character_xp)
    check('an AI faction gets the effect bundle',
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

    local in_debt = play({ income = -1000, last_turn = 3, player_regions = 2 })
    check('a negative income gives no gold and takes none', in_debt.gold_count == 0, in_debt.last_gold)

    local in_debt_late = play({ income = -1000, last_turn = 10, settings = { bonus_multiplier_wh_main_grn_greenskins = '5' } })
    check('a negative income gives no gold with a big multiplier', in_debt_late.gold_count == 0, in_debt_late.last_gold)
    check('a negative income keeps the other bonuses',
        in_debt_late.character_xp == '10:10000' and in_debt_late.bundles[10] == 'af_armageddon_effect_bundle_ai_buff_1',
        in_debt_late.character_xp)

    local no_income = play({ income = 0, last_turn = 2 })
    check('no income gives no gold', no_income.gold_count == 0, no_income.gold_count)
end

print('-- bonus multiplier')

do
    local function greenskins(multiplier, other_settings)
        local result = other_settings or {}
        result.bonus_multiplier_wh_main_grn_greenskins = multiplier
        return result
    end

    local function gold(world)
        return math.floor(play(world).last_gold + 0.5)
    end

    local function check_gold(name, world, expected)
        local value = gold(world)
        check(name, value == expected, value)
    end

    check_gold('gold: 1 by default', { last_turn = 1, player_regions = 2 }, 100)
    check_gold('gold: multiplied by 0.5', { settings = greenskins('0.5'), last_turn = 1, player_regions = 2 }, 50)
    check_gold('gold: multiplied by 2', { settings = greenskins('2'), last_turn = 1, player_regions = 2 }, 200)
    check_gold('gold: multiplied by 0.25', { settings = greenskins('0.25'), last_turn = 1, player_regions = 2 }, 25)
    check_gold('gold: multiplied by 0.1', { settings = greenskins('0.1'), last_turn = 1, player_regions = 2 }, 10)
    check_gold('gold: multiplied by 3', { settings = greenskins('3'), last_turn = 1, player_regions = 2 }, 300)
    check_gold('gold: multiplied by 4', { settings = greenskins('4'), last_turn = 1, player_regions = 2 }, 400)
    check_gold('gold: multiplied by 5', { settings = greenskins('5'), last_turn = 1, player_regions = 2 }, 500)
    check_gold('gold: the multiplier of another culture changes nothing', {
        settings = { bonus_multiplier_wh_main_dwf_dwarfs = '2' },
        last_turn = 1
    }, 20)
    check_gold('gold: a culture from another mod gets 1', {
        settings = greenskins('2'),
        last_turn = 1,
        ai_culture = 'unknown_culture'
    }, 20)
    check_gold('gold: without MCT 1', { no_mct = true, last_turn = 1 }, 20)
    check_gold('gold: multiplayer gets 1', { is_mp = true, settings = greenskins('2'), last_turn = 1 }, 20)
    check_gold('gold: a value that is not a number counts as 1', { settings = greenskins('x'), last_turn = 1 }, 20)
    check_gold('gold: a negative value counts as 1', { settings = greenskins('-1'), last_turn = 1 }, 20)
    check_gold('gold: a change applies from the next turn',
        { changes = { [3] = greenskins('2') }, last_turn = 3 }, 120)

    check_character_xp('character experience: multiplied by 0.5', {
        settings = greenskins('0.5'),
        last_turn = 11
    }, '10:1000,11:1100')
    check_character_xp('character experience: multiplied by 1.75', {
        settings = greenskins('1.75'),
        last_turn = 11
    }, '10:3500,11:3850')
    check_character_xp('character experience: multiplied by 0.1', {
        settings = greenskins('0.1'),
        last_turn = 11
    }, '10:200,11:220')
    check_character_xp('character experience: multiplied by 5', {
        settings = greenskins('5'),
        last_turn = 11
    }, '10:10000,11:11000')
    check_character_xp('character experience: rounded to an integer', {
        settings = greenskins('0.25', { experience_for_character = 50 }),
        last_turn = 11
    }, '10:125,11:138')
    check_character_xp('character experience: the start turn stays', {
        settings = greenskins('2'),
        last_turn = 10
    }, '10:4000')

    -- The default interval is 2
    local function interval_turns(name, multiplier, last_turn, expected, other_settings)
        check_turns('unit experience: ' .. name, {
            settings = greenskins(multiplier, other_settings),
            last_turn = last_turn
        }, expected)
    end

    interval_turns('2 makes the interval twice as short', '2', 13, '10,11,12,13')
    interval_turns('0.5 makes it twice as long', '0.5', 20, '12,16,20')
    interval_turns('0.1: every 20th turn', '0.1', 40, '20,40')
    interval_turns('0.25: every 8th turn', '0.25', 24, '16,24')
    interval_turns('0.75: 2.67 is rounded to 3', '0.75', 18, '12,15,18')
    interval_turns('1.25: 1.6 is rounded to 2', '1.25', 14, '10,12,14')
    interval_turns('1.5: 1.33 is rounded to 1', '1.5', 12, '10,11,12')
    interval_turns('1.75: 1.14 is rounded to 1', '1.75', 12, '10,11,12')
    interval_turns('3: 0.67 is rounded to 1', '3', 12, '10,11,12')
    interval_turns('5: 0.4 is rounded to 0, the interval stays 1', '5', 12, '10,11,12')
    interval_turns('a half is rounded up: 3 / 2 = 1.5 is 2', '2', 14, '10,12,14',
        { army_experience_turn_interval = 3 })
    interval_turns('a changed interval is divided too: 5 / 0.5 = 10', '0.5', 30, '10,20,30',
        { army_experience_turn_interval = 5 })
    interval_turns('the interval never goes below 1', '2', 12, '10,11,12', { army_experience_turn_interval = 1 })
    interval_turns('the interval never goes below 1: 1 / 4 = 0.25', '4', 12, '10,11,12',
        { army_experience_turn_interval = 1 })
    interval_turns('the start turn stays', '2', 11, '10,11', { army_experience_start_turn = 10 })

    local bundles = play({ settings = greenskins('0.25'), last_turn = 40 })
    check('the effect bundle does not depend on the multiplier',
        bundles.bundles[10] == 'af_armageddon_effect_bundle_ai_buff_1'
        and bundles.bundles[40] == 'af_armageddon_effect_bundle_ai_buff_5',
        tostring(bundles.bundles[10]) .. ', ' .. tostring(bundles.bundles[40]))

    local logged = play({ settings = greenskins('0.5', { enable_logging = true }), last_turn = 12 })
    check('the log has the multiplier of the gold', logged.log:find('bonus_multiplier: 0.5', 1, true) ~= nil, logged.log)
    check('the log has the interval of the units',
        logged.log:find('add_xp_to_army, faction: ai, every n-th turn: 4', 1, true) ~= nil, logged.log)
end

print('-- attitude to the player')

do
    local bundle_key = 'af_armageddon_effect_bundle_diplomacy_penalty'

    -- The penalties of the player by turn, 'none' for a turn without the bundle
    local function penalty_turns(world, turns)
        local result = play(world)
        local values = {}
        for _, turn in ipairs(turns) do values[#values + 1] = tostring(result.penalties[turn] or 'none') end
        return table.concat(values, ','), result
    end

    local function check_penalties(name, world, turns, expected)
        local values = penalty_turns(world, turns)
        check(name, values == expected, values)
    end

    -- Each turn the bundle is applied again: the value of a turn is the one it was applied with
    check_penalties('by default: 5 per 10 turns from turn 20, up to 60', { last_turn = 150 },
        { 1, 19, 20, 21, 22, 23, 40, 100, 138, 139, 150 },
        'none,none,none,-1,-1,-2,-10,-40,-59,-60,-60')

    do
        local _, result = penalty_turns({ last_turn = 150 }, {})
        local bundle = result.player_bundles[bundle_key]
        local effect = bundle and bundle.effects[1]
        check('the bundle has one effect: the vanilla relations with all factions',
            bundle ~= nil and #bundle.effects == 1 and effect.effect == 'wh_main_faction_political_diplomacy_mod'
            and effect.scope == 'faction_to_faction_own_unseen' and effect.value == -60,
            effect and (effect.effect .. ' ' .. effect.scope .. ' ' .. effect.value))
        check('the bundle has no end', bundle ~= nil and bundle.duration == 0, bundle and bundle.duration)
        check('the old bundle is removed before the new one', result.stacked == false)
        check('the other human player gets no bundle', next(result.other_bundles) == nil)
        check('the AI gets no bundle of the player', result.active_bundles[bundle_key] == nil)
        check('the player gets no gold', result.gold_count == 150, result.gold_count)
    end

    check_penalties('the penalty comes from MCT', {
        settings = { diplomacy_penalty_per_10_turns = 10 },
        last_turn = 25
    }, { 19, 20, 21, 25 }, 'none,-1,-2,-6')

    check_penalties('the start turn comes from MCT', {
        settings = { diplomacy_penalty_start_turn = 5, diplomacy_penalty_per_10_turns = 10 },
        last_turn = 14
    }, { 4, 5, 14 }, 'none,-1,-10')

    check_penalties('the maximum comes from MCT', {
        settings = { diplomacy_penalty_max = 5 },
        last_turn = 100
    }, { 29, 30, 100 }, '-5,-5,-5')

    check_penalties('50 per 10 turns: 5 per turn', {
        settings = { diplomacy_penalty_per_10_turns = 50, diplomacy_penalty_max = 200 },
        last_turn = 70
    }, { 20, 21, 59, 60, 70 }, '-5,-10,-200,-200,-200')

    do
        local values, result = penalty_turns({ settings = { diplomacy_penalty_per_10_turns = 0 }, last_turn = 150 }, { 150 })
        check('0 turns it off', values == 'none' and next(result.player_bundles) == nil, values)
    end

    do
        local values, result = penalty_turns({
            changes = { [41] = { diplomacy_penalty_per_10_turns = 0 } },
            last_turn = 42
        }, { 40, 41, 42 })
        check('0 during the campaign removes the bundle on the next turn of the player',
            values == '-10,none,none' and next(result.player_bundles) == nil, values)
    end

    check_penalties('a lower maximum during the campaign lowers the penalty', {
        changes = { [41] = { diplomacy_penalty_max = 5 } },
        last_turn = 41
    }, { 40, 41 }, '-10,-5')

    check_penalties('a later start turn during the campaign takes the penalty back', {
        changes = { [41] = { diplomacy_penalty_start_turn = 100 } },
        last_turn = 42
    }, { 40, 41, 42 }, '-10,none,none')

    check_penalties('the multipliers of the cultures change nothing', {
        settings = { bonus_multiplier_wh_main_emp_empire = '0', bonus_multiplier_wh_main_grn_greenskins = '5' },
        last_turn = 40
    }, { 40 }, '-10')

    check_penalties('without MCT: the defaults', { no_mct = true, last_turn = 40 }, { 40 }, '-10')

    do
        local values, result = penalty_turns({
            is_mp = true,
            other_is_local = true,
            settings = { diplomacy_penalty_per_10_turns = 50 },
            last_turn = 40
        }, { 40 })
        check('multiplayer: the defaults, only for the first player',
            values == '-10' and next(result.other_bundles) == nil, values)
    end

    local logged = play({ settings = { enable_logging = true }, last_turn = 40 })
    check('the log has the penalty',
        logged.log:find('diplomacy penalty, faction: player, penalty: 10', 1, true) ~= nil, logged.log)
end

print('-- settings')

do
    check('the sections: three in each column, the cultures last',
        table.concat(mct_sections, ',') == 'gold,character_experience,army_experience,diplomacy,debug,bonus_multiplier',
        table.concat(mct_sections, ','))

    local defaults = read_script_defaults()

    for key, value in pairs(defaults) do
        local option = mct_options[key]
        check('an MCT option for ' .. key, option ~= nil)
        if option then
            check(key .. ': the same default', option.default == value, option.default)
            -- Only the log is global, all the other options belong to a campaign
            local is_global = key == 'enable_logging'
            check(key .. (is_global and ': global' or ': for each campaign'),
                option.is_global == is_global, option.is_global)
            if option.type == 'slider' then
                check(key .. ': the default fits the slider',
                    value >= option.min and value <= option.max and value % option.step == 0, value)
            end
        end
    end

    local multiplier_options = 0
    local multiplier_values = '0,0.1,0.25,0.5,0.75,1,1.25,1.5,1.75,2,3,4,5'

    for key, option in pairs(mct_options) do
        local multiplier_culture = key:match('^bonus_multiplier_(.+)')

        if multiplier_culture then
            multiplier_options = multiplier_options + 1
            check(key .. ': a dropdown', option.type == 'dropdown', option.type)
            check(key .. ': 1 by default', option.default == '1', option.default)
            check(key .. ': for each campaign', option.is_global == false, option.is_global)
            check(key .. ': the name from the game', option.text == 'cultures_name_' .. multiplier_culture, option.text)

            local keys, texts = {}, {}
            for _, value in ipairs(option.values or {}) do
                keys[#keys + 1] = value.key
                texts[#texts + 1] = value.text
            end
            check(key .. ': the values', table.concat(keys, ',') == multiplier_values, table.concat(keys, ','))
            check(key .. ': the texts are the values', table.concat(texts, ',') == multiplier_values)
        else
            check('a default for the MCT option ' .. key, defaults[key] ~= nil)
        end
    end

    check('a multiplier for each culture', multiplier_options == 26, multiplier_options)

    for key in pairs(mct_options) do
        check('no option to skip a culture: ' .. key, key:find('^skip_bonuses_') == nil)
    end
    check('the interval of the units is 2 by default', defaults.army_experience_turn_interval == 2)

    check('logging is off by default', defaults.enable_logging == false)

    local version = mod_source:match("mod_version = '([%d%.]+)'")
    check('the MCT title has the version of the script', mct_title == 'AF Armageddon v' .. version, mct_title)
end

check_turns('without MCT: the defaults', { no_mct = true, last_turn = 12 }, '10,12')
check_turns('MCT without this mod: the defaults', { no_mct_mod = true, last_turn = 12 }, '10,12')

check_turns('multiplayer: the defaults, not the values of this player', {
    is_mp = true,
    settings = {
        army_experience_start_turn = 1,
        army_experience_turn_interval = 1,
        bonus_multiplier_wh_main_grn_greenskins = '0.5'
    },
    last_turn = 12
}, '10,12')

do
    local result = play({ is_mp = true, other_is_local = true, last_turn = 1, player_regions = 1 })
    check('multiplayer: the same player on each machine', math.floor(result.last_gold + 0.5) == 60, result.last_gold)
end

check_turns('a change applies from the next turn', {
    changes = { [11] = { army_experience_turn_interval = 1 } },
    last_turn = 13
}, '10,11,12,13')

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

    local logged = play({
        settings = { enable_logging = true, regions_percent = 10, bonus_multiplier_wh_main_dwf_dwarfs = '3' },
        last_turn = 2,
        faction_turns = 3
    })
    check('the settings are logged once per turn', select(2, logged.log:gsub('settings, turn ', '')) == 2, logged.log)
    check('the log has a changed setting', logged.log:find('regions_percent: 10', 1, true) ~= nil, logged.log)
    check('the log has a default setting', logged.log:find('time_percent: 2', 1, true) ~= nil, logged.log)
    check('the log has a changed multiplier',
        logged.log:find('bonus_multiplier_wh_main_dwf_dwarfs: 3', 1, true) ~= nil, logged.log)
    check('the log has a default multiplier',
        logged.log:find('bonus_multiplier_wh_main_grn_greenskins: 1', 1, true) ~= nil, logged.log)

    for key in pairs(mct_options) do
        check('the log has the option ' .. key, logged.log:find(key .. ': ', 1, true) ~= nil)
    end

    check('the settings are sorted',
        logged.log:find('enable_logging: ', 1, true) < logged.log:find('regions_percent: ', 1, true))
    check('the settings go before the bonuses',
        logged.log:find('settings, turn 1 ', 1, true) < logged.log:find('gold_bonus', 1, true))

    local turned_on = play({ changes = { [2] = { enable_logging = true } }, last_turn = 2 })
    check('the log turned on during the campaign gets the settings',
        turned_on.log:find('settings, turn 2 ', 1, true) ~= nil, turned_on.log)
end

print(failed == 0 and 'ALL PASSED' or (failed .. ' FAILED'))
os.exit(failed == 0 and 0 or 1)
