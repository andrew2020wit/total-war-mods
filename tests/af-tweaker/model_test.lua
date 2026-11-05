-- Runs af_tweaker.lua against a small model of the game, UI included. Run it from the
-- repository root, see af-tweaker-agent.md. It isn't part of the mod.
local mod_path = 'mods/warhammer_3/af-tweaker/script/campaign/mod/af_tweaker.lua'
local file_prefix = (os.getenv('TEMP') or os.getenv('TMPDIR') or '/tmp') .. '/af_tweaker_test_'
local favorites_file = file_prefix .. 'favorites.txt'
local priorities_file = file_prefix .. 'priorities.txt'

local failed = 0
local function check(name, ok, detail)
    print((ok and 'ok   ' or 'FAIL ') .. name .. (detail and (' -- ' .. tostring(detail)) or ''))
    if not ok then failed = failed + 1 end
end

local function write_file(name, text)
    local f = assert(io.open(name, 'w'))
    f:write(text)
    f:close()
end

local function read_file(name)
    local f = io.open(name, 'r')
    if not f then return '' end
    local text = f:read('a')
    f:close()
    return text
end

local function count(text, pattern)
    local n = 0
    for _ in text:gmatch(pattern) do n = n + 1 end
    return n
end

-- world: { skills, points, commit_delay, buildings..., settings, no_mct, is_mp }
-- Buildings go in world.slots of one region, or in world.regions: { { cqi, name, province, slots, siege } }.
-- world.caps limit a key: { limit, per_province }. The game sees new buildings a round later.
-- world.upgrades is a key or a list of keys per level, world.chains the chains of the keys.
-- The character is the world itself, or several are in world.heroes: { { cqi, points, skills, wounded } }.
-- level_up_points of a character come with its next charged point.
-- world.items are the magic items of the faction: { key, level, category, equipped, refuse }.
-- The game fuses a pair world.fuse_delay rounds after the command, never with world.refuse_fusions,
-- and the new item comes world.new_item_delay rounds after the event.
local function start(world)
    local log_name = file_prefix .. 'log.txt'
    local err_name = file_prefix .. 'errors.txt'
    os.remove(log_name); os.remove(err_name)
    write_file(favorites_file, table.concat(world.favorites or {}, '\n') .. '\n')
    write_file(priorities_file, world.priorities or '')

    local timers, listeners, first_tick, polls = {}, {}, {}, {}
    local pending_commits = {}
    local pending_buildings = {}
    local commands = {}
    local size_queries = {}
    local env = setmetatable({}, { __index = _G })

    env.io = {
        open = function(name, mode)
            local map = {
                ['!!af_tweaker.txt'] = log_name,
                ['!!af_tweaker-errors.txt'] = err_name,
                ['!!af_tweaker-favorites.txt'] = favorites_file,
                ['!!af_tweaker-skill-priorities.txt'] = priorities_file
            }
            return io.open(map[name], mode)
        end
    }

    local overrides = world.settings or {}
    overrides.enable_logging = true

    if not world.no_mct then
        env.get_mct = function()
            return {
                get_mod_by_key = function()
                    return {
                        get_option_by_key = function(_, key)
                            return { get_finalized_setting = function() return overrides[key] end }
                        end
                    }
                end
            }
        end
    end

    local region_data = world.regions or (world.slots and { { cqi = 7, name = 'r1', province = 'p1', slots = world.slots } }) or {}
    local regions = {}
    local region_of_cqi = {}
    for i, data in ipairs(region_data) do
        region_of_cqi[data.cqi] = data
        regions[i] = {
            cqi = function() return data.cqi end,
            name = function() return data.name end,
            province_name = function() return data.province end,
            has_development_points_to_upgrade = function() return (world.development_points or 0) > 0 end,
            garrison_residence = function() return { is_under_siege = function() return data.siege == true end } end
        }
    end
    local function list(items)
        return { num_items = function() return #items end, item_at = function(_, i) return items[i + 1] end }
    end
    local heroes = world.heroes or (world.skills and { world }) or {}
    local hero_of_cqi = {}
    local characters = {}
    for i, hero in ipairs(heroes) do
        local cqi = hero.cqi or i
        hero_of_cqi[cqi] = hero
        characters[i] = {
            is_wounded = function() return hero.wounded == true end,
            command_queue_index = function() return cqi end
        }
    end
    local faction = {
        name = function() return 'player' end,
        command_queue_index = function() return 42 end,
        treasury = function() return world.treasury or 100000 end,
        region_list = function() return list(regions) end,
        character_list = function() return list(characters) end,
        is_factions_turn = function() return world.turn_over ~= true end
    }

    env.cm = {
        callback = function(_, f) table.insert(timers, f) end,
        add_first_tick_callback = function(_, f) table.insert(first_tick, f) end,
        repeat_real_callback = function(_, f) table.insert(polls, f) end,
        get_faction = function() return faction end,
        get_local_faction_name = function() return 'player' end,
        is_multiplayer = function() return world.is_mp == true end,
        turn_number = function() return 1 end,
        get_building_level_upgrades = function(_, key)
            local upgrades = world.upgrades and world.upgrades[key]
            if type(upgrades) == 'table' then return upgrades end
            return world.upgrades and { upgrades }
        end,
        building_chain_key_for_building = function(_, key) return world.chains and world.chains[key] or 'chain' end
    }
    env.core = {
        add_listener = function(_, name, event, cond, handler) listeners[name] = { cond = cond, handler = handler } end,
        get_ui_root = function() return world.root end,
        get_or_create_component = function(_, name, _, parent) return world.make_button(name, parent) end
    }
    env.find_child_uicomponent = function(parent, name) return world.find_child and world.find_child(parent, name) or false end
    env.UIComponent = function(x) return x end

    local function slot_of(expr) return tonumber(expr:match('At%((%d+)%)')) end
    local function level_of(expr)
        local key = nil
        for k in expr:gmatch('Key == "(.-)"') do key = k end
        return key
    end
    local function level_info(key) return world.levels[key] or {} end

    world.items = world.items or {}
    world.fusions = {}
    local pending_fusions = {}
    local pending_items = {}
    local next_level = { common = 'uncommon', uncommon = 'rare', rare = 'legendary' }

    local function item_value(expr)
        local items = world.items
        local item = items[tonumber(expr:match('At%((%d+)%)')) + 1]
        if expr:find('^IsContextValid%(AncillaryList%.At%(%d+%)%.CharacterEquippedToContext%) == false && ') then
            assert(expr:find('IsFusable', 1, true) and expr:find('CanBeDestroyed', 1, true), expr)
            return not item.equipped and item.category ~= 'general' and item.category ~= 'mount'
        end
        local other = expr:match('%.CanFuse%(AncillaryList%.At%((%d+)%)%)$')
        if other then
            local second = items[tonumber(other) + 1]
            return item.level == second.level and not item.refuse and not second.refuse
        end
        if expr:find('%.AncillaryRecordContext%.FrameState$') then return item.level end
        if expr:find('%.CategoryContext%.Category$') then return item.category end
        if expr:find('%.AncillaryRecordContext%.Key$') then return item.key end
        if expr:find('%.Name$') then return item.key .. ' name' end
        error('item expression: ' .. expr)
    end

    local function remove_item(item)
        for i, other in ipairs(world.items) do
            if other == item then
                table.remove(world.items, i)
                return
            end
        end
    end

    -- Like the game and the vanilla listener of AncillariesFused
    local function apply_fusions()
        for i = #pending_items, 1, -1 do
            local pending = pending_items[i]
            if pending.rounds == 0 then
                table.remove(pending_items, i)
                table.insert(world.items, pending.item)
            else
                pending.rounds = pending.rounds - 1
            end
        end

        for i = #pending_fusions, 1, -1 do
            local fusion = pending_fusions[i]
            if fusion.rounds == 0 then
                table.remove(pending_fusions, i)
                remove_item(fusion.first)
                remove_item(fusion.second)
                table.insert(world.fusions, fusion.first.key .. '+' .. fusion.second.key)
                local context = { faction = function() return faction end }
                local listener = listeners.AfTweakerAncillariesFused
                if listener.cond(context) then listener.handler(context) end
                local item = {
                    key = 'new_' .. #world.fusions,
                    level = next_level[fusion.first.level],
                    category = fusion.first.category
                }
                local delay = world.new_item_delay or 0
                if delay == 0 then
                    table.insert(world.items, item)
                else
                    table.insert(pending_items, { rounds = delay - 1, item = item })
                end
            else
                fusion.rounds = fusion.rounds - 1
            end
        end
    end
    local function cap_key(key, cqi)
        local cap = world.caps and world.caps[key]
        return cap and cap.per_province and (key .. ':' .. region_of_cqi[cqi].province) or key
    end
    local function is_under_cap(key, cqi)
        local cap = world.caps and world.caps[key]
        return not cap or (world.built_counts[cap_key(key, cqi)] or 0) < cap.limit
    end

    env.common = {
        get_localised_string = function(key)
            return ({
                ui_text_replacements_localised_text_replacement = 'Replaced',
                direct_key = 'Direct'
            })[key] or ''
        end,
        get_context_value = function(context, id, expr)
            if context == 'CcoCampaignFaction' then
                assert(id == 42, 'the faction cqi: ' .. tostring(id))
                if expr == 'AncillaryList.Size' then return #world.items end
                return item_value(expr)
            end

            if context == 'CcoBuildingLevelRecord' then
                if expr == 'Key' then return id end
                return 'Name of ' .. id
            end

            if context == 'CcoCampaignBuildingSlot' then
                if expr:find('IsEmpty == false') then return true end
                return world.slot_keys and world.slot_keys[id] or 'chain_first_level'
            end

            if context == 'CcoCampaignCharacter' then
                local hero = hero_of_cqi[id]
                local index = tonumber(expr:match('^SkillList%.At%((%d+)%)'))
                if expr == 'SkillPointsAvailable' then return hero.points end
                if expr == 'SkillList.Size' then return #hero.skills end
                if expr == 'Name' then return 'Hero' end
                local skill = index and hero.skills[index + 1]
                if expr:find('%.Status == "active"') then return skill.level < skill.total end
                if expr:find('%.Key$') then return skill.key end
                if expr:find('%.Level$') then return skill.level end
                if expr:find('%.Name$') then return skill.name or (skill.key .. ' name') end
                if expr:find('%.Status$') then return 'active' end
                error('skill expression: ' .. expr)
            end

            -- settlement
            local slots = region_of_cqi[id].slots
            if expr == 'this.BuildingSlotList.Size' then
                size_queries[id] = (size_queries[id] or 0) + 1
                return #slots
            end
            if expr == 'this.Name' then return 'Region' end
            local slot = slot_of(expr)
            local data = slot and slots[slot + 1]
            if expr:find('%.IsEmpty == false && ') then
                return data.level ~= nil and data.upgrade == true and not data.busy
            end
            if expr:find('%.IsEmpty && ') then return data.level == nil and not data.busy end
            if expr:find('BuildingLevelRecordContext%.Key$') then return data.level end
            if expr:find('^IsContextValid') and expr:find('Pooled') then
                return level_info(level_of(expr)).pooled == true
            end
            if expr:find('^IsContextValid') then
                return world.is_favorite_possible == nil or world.is_favorite_possible(level_of(expr), slot, id)
            end
            if expr:find('IsActiveForBuildingBrowser') then return is_under_cap(level_of(expr), id) end
            if expr:find('IsLockedByAnyTech') then return true end
            if expr:find('CreateCost') then return level_info(level_of(expr)).cost or 100 end
            if expr:find('DevelopmentPointCost') then return level_info(level_of(expr)).development or 0 end
            error('settlement expression: ' .. expr)
        end,
        call_context_command = function(context, id, expr)
            table.insert(commands, expr)
            if context == 'CcoCampaignFaction' then
                local first, second = expr:match('^AncillaryList%.At%((%d+)%)%.FuseForPlayer%(AncillaryList%.At%((%d+)%)%)$')
                assert(first, 'fuse command: ' .. expr)
                if not world.refuse_fusions then
                    table.insert(pending_fusions, {
                        rounds = world.fuse_delay or 0,
                        first = world.items[tonumber(first) + 1],
                        second = world.items[tonumber(second) + 1]
                    })
                end
            elseif context == 'CcoCampaignCharacter' then
                local hero = hero_of_cqi[id]
                if expr == 'CommitSkillChoices' then
                    local pending = hero.added
                    hero.added = nil
                    table.insert(pending_commits, { rounds = world.commit_delay or 0, skill = pending, hero = hero })
                else
                    hero.added = hero.skills[tonumber(expr:match('At%((%d+)%)')) + 1]
                end
            else
                local slot = region_of_cqi[id].slots[slot_of(expr) + 1]
                if not world.refuse_buildings then slot.busy = true end
                table.insert(world.queued, level_of(expr) or 'upgrade ' .. slot_of(expr))
                table.insert(pending_buildings, { key = level_of(expr), cqi = id })
            end
        end
    }

    local function apply_commits()
        world.built_counts = world.built_counts or {}
        for _, building in ipairs(pending_buildings) do
            if building.key then
                local key = cap_key(building.key, building.cqi)
                world.built_counts[key] = (world.built_counts[key] or 0) + 1
            end
        end
        pending_buildings = {}

        for i = #pending_commits, 1, -1 do
            local commit = pending_commits[i]
            if commit.rounds == 0 then
                table.remove(pending_commits, i)
                if commit.skill and not commit.skill.refuse then
                    commit.skill.level = commit.skill.level + 1
                    commit.hero.points = commit.hero.points - 1 + (commit.hero.level_up_points or 0)
                    commit.hero.level_up_points = nil
                end
            else
                commit.rounds = commit.rounds - 1
            end
        end
    end

    local chunk = assert(loadfile(mod_path, 't', env))
    chunk()
    for _, f in ipairs(first_tick) do f() end

    local game = { polls = polls, commands = commands, listeners = listeners, size_queries = size_queries }

    function game.run_timers()
        local steps = 0
        while #timers > 0 do
            steps = steps + 1
            if steps > 200 then error('rounds never end') end
            local batch = timers
            timers = {}
            world.round = steps
            apply_commits()
            apply_fusions()
            for _, f in ipairs(batch) do f() end
        end
        apply_commits()
        apply_fusions()
        game.steps = steps
    end

    function game.turn()
        apply_commits()
        listeners.AfTweakerAutoUpgrade.handler({
            faction = function() return faction end
        })
        game.run_timers()
    end

    -- The first round runs in the click itself
    function game.click_fuse()
        local listener = listeners.AfTweakerAutoFuseButton
        local context = { string = 'af_tweaker_auto_fuse_button' }
        if listener.cond(context) then listener.handler(context) end
    end

    function game.fuse()
        game.click_fuse()
        game.run_timers()
    end

    function game.log() return read_file(log_name) end
    function game.errors() return read_file(err_name) end
    return game
end

-- Skills
do
    local world = {
        points = 3,
        priorities = 'locked=3\n',
        skills = {
            { key = 'locked', level = 0, total = 3, refuse = true },
            { key = 'a', level = 0, total = 1 },
            { key = 'b', level = 0, total = 5 }
        }
    }
    local game = start(world)
    game.turn()
    check('a refused skill does not block the others', world.points == 0, 'points left ' .. world.points)
    check('the refused skill is tried once', count(game.log(), 'not charged') == 1)
    check('the stats count real points', game.log():find('characters: 1, points spent: 3', 1, true) ~= nil)
    check('no errors', game.errors() == '', game.errors())
end

do
    local world = {
        points = 2,
        skills = { { key = 'a', level = 0, total = 5, refuse = true } }
    }
    local game = start(world)
    game.turn()
    check('a refused skill stays unpaid', world.points == 2 and count(game.log(), 'not charged') == 1)
    world.skills[1].refuse = false
    game.turn()
    check('a skill refused last turn is tried again', world.points == 0, 'points left ' .. world.points)
end

do
    local world = {
        points = 2,
        level_up_points = 1,
        skills = { { key = 'a', level = 0, total = 5 } }
    }
    local game = start(world)
    game.turn()
    check('a level up during the rounds is not a refusal', count(game.log(), 'not charged') == 0, game.log())
    check('a level up: all points are spent', world.points == 0, 'points left ' .. world.points)
    check('a level up: the stats count the hidden point', game.log():find('points spent: 3', 1, true) ~= nil, game.log())
end

do
    local world = {
        heroes = {
            { cqi = 1, points = 2, skills = { { key = 'a', level = 0, total = 5 } } },
            { cqi = 2, points = 1, skills = { { key = 'b', level = 0, total = 5 } } },
            { cqi = 3, points = 3, wounded = true, skills = { { key = 'c', level = 0, total = 5 } } }
        }
    }
    local game = start(world)
    game.turn()
    check('each character spends their own points', world.heroes[1].points == 0 and world.heroes[2].points == 0)
    check('a wounded character is skipped', world.heroes[3].points == 3)
    check('the stats count the characters', game.log():find('characters: 2, points spent: 3', 1, true) ~= nil, game.log())
end

do
    local world = {
        points = 3,
        commit_delay = 2,
        skills = { { key = 'a', level = 0, total = 5 } }
    }
    local game = start(world)
    game.turn()
    check('a slow commit is not a refusal', count(game.log(), 'not charged') == 0, game.log())
    check('slow commits still spend everything', world.points == 0, 'points left ' .. world.points)
end

do
    local world = {
        points = 2,
        skills = { { key = 'a', level = 0, total = 5, refuse = true }, { key = 'b', level = 0, total = 5, refuse = true } }
    }
    local game = start(world)
    game.turn()
    check('all skills refused: the rounds end', world.points == 2 and count(game.log(), 'not charged') == 2)
    check('no skill left is logged', game.log():find('no skill to buy', 1, true) ~= nil)
end

do
    local world = {
        points = 1,
        settings = { auto_upgrade_enabled = false, favorite_buildings_enabled = false, auto_skills_enabled = true },
        skills = { { key = 'a', level = 0, total = 5 } }
    }
    local game = start(world)
    game.turn()
    check('skills alone: the point is spent', world.points == 0)
    check('skills alone: no building cycle', game.log():find('auto build', 1, true) == nil, game.log())
end

do
    local world = {
        points = 5,
        skills = { { key = 'a', level = 0, total = 5 } }
    }
    local game = start(world)
    world.turn_over = true
    game.turn()
    check('nothing is spent after the turn ended', world.points == 5)
end

do
    local world = {
        points = 4,
        skills = {
            { key = 'a', level = 0, total = 1, name = '{{tr:replacement}}' },
            { key = 'b', level = 0, total = 1, name = '{{tr:direct_key}}' },
            { key = 'c', level = 0, total = 1, name = 'The {{tr:replacement}} of {{tr:direct_key}}' },
            { key = 'd', level = 0, total = 1, name = '{{tr:no_text}}' }
        }
    }
    local game = start(world)
    game.turn()
    check('a name from ui_text_replacements', game.log():find('Replaced (a)', 1, true) ~= nil, game.log())
    check('a name from a whole loc key', game.log():find('Direct (b)', 1, true) ~= nil, game.log())
    check('several references in one name', game.log():find('The Replaced of Direct (c)', 1, true) ~= nil, game.log())
    check('a reference without a text stays', game.log():find('{{tr:no_text}} (d)', 1, true) ~= nil, game.log())
    check('the references break nothing', game.errors() == '', game.errors())
end

-- Buildings
local function building_world()
    return {
        queued = {},
        favorites = { 'fav_pooled', 'fav_pooled2', 'fav_gold' },
        settings = { auto_upgrade_enabled = true, favorite_buildings_enabled = true, auto_skills_enabled = false, min_treasury = 0 },
        development_points = 1,
        upgrades = { l1 = 'up_pooled1', l2 = 'up_pooled2', l3 = 'up_gold', l4 = 'up_dev1', l5 = 'up_dev2' },
        levels = {
            fav_pooled = { pooled = true },
            fav_pooled2 = { pooled = true },
            up_pooled1 = { pooled = true },
            up_pooled2 = { pooled = true },
            up_dev1 = { development = 1 },
            up_dev2 = { development = 1 }
        },
        slots = {
            { level = 'l1', upgrade = true },
            { level = 'l2', upgrade = true },
            { level = 'l3', upgrade = true },
            { level = 'l4', upgrade = true },
            { level = 'l5', upgrade = true },
            {},
            {}
        }
    }
end

do
    local world = building_world()
    local game = start(world)
    game.turn()
    local queued = table.concat(world.queued, ' ')
    print('     queued: ' .. queued)
    check('all buildings are queued', #world.queued == 7, queued)
    check('favorites go first', world.queued[1] == 'fav_pooled' and world.queued[2] == 'fav_pooled2', queued)
    check('the deferred favorite keeps its slot', not queued:find('fav_gold', 1, true), queued)
    check('the summary is logged once', count(game.log(), 'auto build done') == 1)
    check('no errors', game.errors() == '', game.errors())
end

do
    local world = building_world()
    world.refuse_buildings = true
    local game = start(world)
    game.turn()
    check('refused commands end the rounds', game.steps < 20, 'steps ' .. tostring(game.steps))
    local seen, repeated = {}, false
    for _, command in ipairs(game.commands) do
        local slot = command:match('At%((%d+)%)')
        if seen[slot] then repeated = true end
        seen[slot] = true
    end
    check('each slot gets one command', not repeated)
end

do
    local world = building_world()
    world.treasury = 250
    local game = start(world)
    game.turn()
    check('the budget holds across rounds', #world.queued == 2, table.concat(world.queued, ' '))
end

do
    local world = building_world()
    world.treasury = 1000
    world.settings.min_treasury = 5000
    local game = start(world)
    game.turn()
    check('a treasury under the minimum spends nothing', #world.queued == 0, table.concat(world.queued, ' '))
    check('the negative budget is logged', game.log():find('budget: -4000', 1, true) ~= nil, game.log())
    check('a negative budget: no errors', game.errors() == '', game.errors())
end

do
    local world = building_world()
    world.is_mp = true
    world.points = 5
    world.skills = { { key = 'a', level = 0, total = 5 } }
    world.settings.auto_skills_enabled = true
    local game = start(world)
    game.turn()
    check('multiplayer: a turn does nothing', #game.commands == 0, #game.commands)
end

local function favorites_world(favorites, regions, levels)
    return {
        queued = {},
        favorites = favorites,
        settings = { auto_upgrade_enabled = false, favorite_buildings_enabled = true, auto_skills_enabled = false, min_treasury = 0 },
        levels = levels or {},
        regions = regions
    }
end

local function queued_count(world, key)
    local n = 0
    for _, queued in ipairs(world.queued) do
        if queued == key then n = n + 1 end
    end
    return n
end

do
    local world = favorites_world({ 'fav_a', 'fav_b', 'fav_c' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {}, {}, {} } }
    }, {
        fav_a = { pooled = true, cost = 100 },
        fav_b = { pooled = true, cost = 200 },
        fav_c = { cost = 200 }
    })
    world.treasury = 300
    world.is_favorite_possible = function(key, slot) return not (key == 'fav_b' and slot == 2) end
    local game = start(world)
    game.turn()
    check('a waiting favorite keeps its gold', table.concat(world.queued, ' ') == 'fav_a fav_b', table.concat(world.queued, ' '))
    check('no errors', game.errors() == '', game.errors())
end

do
    local world = favorites_world({ 'fav_a', 'fav_b', 'fav_c' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {}, {} } },
        { cqi = 2, name = 'r2', province = 'p2', slots = { {} } }
    }, {
        fav_a = { pooled = true, cost = 100 },
        fav_b = { pooled = true, cost = 100 },
        fav_c = { cost = 50 }
    })
    world.treasury = 200
    world.is_favorite_possible = function(key) return not (key == 'fav_b' and world.round >= 2) end
    local game = start(world)
    game.turn()
    check('gold that came back reaches the next region', queued_count(world, 'fav_c') == 2, table.concat(world.queued, ' '))
end

do
    local world = favorites_world({ 'fav_a', 'fav_b' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {}, {} } },
        { cqi = 2, name = 'r2', province = 'p2', slots = { { level = 'l1' } } }
    }, { fav_a = { pooled = true }, fav_b = { pooled = true } })
    world.settings.auto_upgrade_enabled = true
    world.upgrades = {}
    local game = start(world)
    game.turn()
    check('later rounds skip a region with nothing to do', game.size_queries[2] == 2, game.size_queries[2])
    check('later rounds go to the region that waits', #world.queued == 2, table.concat(world.queued, ' '))
end

do
    local world = favorites_world({ 'fav_capped', 'fav_other' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {} } },
        { cqi = 2, name = 'r2', province = 'p2', slots = { {} } },
        { cqi = 3, name = 'r3', province = 'p2', slots = { {} } }
    })
    world.caps = { fav_capped = { limit = 1 } }
    local game = start(world)
    game.turn()
    check('a cap of one per faction holds', queued_count(world, 'fav_capped') == 1, table.concat(world.queued, ' '))
    check('the slots go to the next favorite', queued_count(world, 'fav_other') == 2, table.concat(world.queued, ' '))
    check('a cap: no errors', game.errors() == '', game.errors())
end

do
    local world = favorites_world({ 'fav_capped', 'fav_other' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {} } },
        { cqi = 2, name = 'r2', province = 'p1', slots = { {} } },
        { cqi = 3, name = 'r3', province = 'p2', slots = { {} } },
        { cqi = 4, name = 'r4', province = 'p2', slots = { {} } }
    })
    world.caps = { fav_capped = { limit = 1, per_province = true } }
    local game = start(world)
    game.turn()
    check('a cap of one per province holds', queued_count(world, 'fav_capped') == 2, table.concat(world.queued, ' '))
    check('its other slots go to the next favorite', queued_count(world, 'fav_other') == 2, table.concat(world.queued, ' '))
end

do
    local regions = {}
    for i = 1, 6 do
        regions[i] = { cqi = i, name = 'r' .. i, province = 'p' .. i, slots = { {} } }
    end
    local world = favorites_world({ 'fav_a' }, regions)
    local game = start(world)
    game.turn()
    check('without a cap all copies are built', queued_count(world, 'fav_a') == 6, table.concat(world.queued, ' '))
    check('copies take few rounds', game.steps <= 3, game.steps)
end

do
    local world = favorites_world({ 'fav_a' }, {
        { cqi = 1, name = 'r1', province = 'p1', siege = true, slots = { {} } },
        { cqi = 2, name = 'r2', province = 'p2', slots = { {} } }
    })
    local game = start(world)
    game.turn()
    check('a settlement under siege is skipped', game.size_queries[1] == nil and #world.queued == 1, table.concat(world.queued, ' '))
end

-- Priorities of favorites
do
    local world = favorites_world({ 'fav_low=1', 'fav_high=3' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {} } },
        { cqi = 2, name = 'r2', province = 'p2', slots = { {} } }
    })
    world.treasury = 100
    world.is_favorite_possible = function(key, _, cqi) return not (key == 'fav_high' and cqi == 1) end
    local game = start(world)
    game.turn()
    check('more stars get the money first in all regions', table.concat(world.queued, ' ') == 'fav_high', table.concat(world.queued, ' '))
    check('the log shows the priority', game.log():find(', priority: 3', 1, true) ~= nil, game.log())
end

do
    local world = favorites_world({ 'fav_one_a', 'fav_two=2', 'fav_three=3', 'fav_one_b=1' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {}, {}, {}, {} } }
    })
    local game = start(world)
    game.turn()
    check('more stars first, equal ones in the order of adding, a line with only a key has one star',
        table.concat(world.queued, ' ') == 'fav_three fav_two fav_one_a fav_one_b', table.concat(world.queued, ' '))
    check('priorities: no errors', game.errors() == '', game.errors())
end

do
    local world = favorites_world({ 'fav_zero=0', 'fav_big=9', 'fav_three=3', ' fav_spaces = 2 ' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {}, {}, {}, {} } }
    })
    local game = start(world)
    game.turn()
    check('hand-edited values: 0 is no favorite, too much is 3, spaces are ignored',
        table.concat(world.queued, ' ') == 'fav_big fav_three fav_spaces', table.concat(world.queued, ' '))
end

do
    local function tiers_of(slots)
        local world = favorites_world({ 'fav_a=3', 'fav_b=3', 'fav_c=1' }, {
            { cqi = 1, name = 'r1', province = 'p1', slots = slots }
        }, { fav_a = { pooled = true }, fav_b = { pooled = true } })
        local game = start(world)
        game.turn()
        return world
    end

    local world = tiers_of({ {}, {} })
    check('a lower tier does not take the slot of a waiting building',
        table.concat(world.queued, ' ') == 'fav_a fav_b', table.concat(world.queued, ' '))

    world = tiers_of({ {}, {}, {} })
    check('a lower tier goes on after the waiting building',
        table.concat(world.queued, ' ') == 'fav_a fav_b fav_c', table.concat(world.queued, ' '))
end

do
    local world = favorites_world({ 'fav_a=3', 'fav_b=1' }, { { cqi = 1, name = 'r1', province = 'p1', slots = { {} } } })
    world.refuse_buildings = true
    local game = start(world)
    game.turn()
    check('the next tier skips a slot queued in the same round', table.concat(world.queued, ' ') == 'fav_a', table.concat(world.queued, ' '))
end

do
    local world = favorites_world({ 'fav_a=3', 'fav_b=1' }, { { cqi = 1, name = 'r1', province = 'p1', slots = { {} } } })
    world.is_favorite_possible = function(key) return key ~= 'fav_a' end
    local game = start(world)
    game.turn()
    check('a slot that more stars cannot use goes to fewer stars', table.concat(world.queued, ' ') == 'fav_b', table.concat(world.queued, ' '))
end

do
    local world = favorites_world({ 'fav_a=3', 'fav_b=1' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {} } }
    }, { fav_a = { cost = 500 } })
    world.treasury = 100
    local game = start(world)
    game.turn()
    check('fewer stars get the money that more stars cannot use', table.concat(world.queued, ' ') == 'fav_b', table.concat(world.queued, ' '))
end

do
    local world = favorites_world({}, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { {}, { level = 'l1', upgrade = true } } }
    })
    world.settings.auto_upgrade_enabled = true
    world.upgrades = { l1 = 'up_a' }
    local game = start(world)
    game.turn()
    check('without stars nothing new is built, upgrades go on', table.concat(world.queued, ' ') == 'up_a', table.concat(world.queued, ' '))
end

do
    local world = favorites_world({ 'fav_low=1', 'fav_high=2' }, {
        { cqi = 1, name = 'r1', province = 'p1', slots = { { level = 'l1', upgrade = true }, {}, {} } }
    })
    world.settings.auto_upgrade_enabled = true
    world.upgrades = { l1 = 'up_a' }
    local game = start(world)
    game.turn()
    check('upgrades go after all tiers', table.concat(world.queued, ' ') == 'fav_high fav_low up_a', table.concat(world.queued, ' '))
end

do
    local function upgrade_of(upgrades, chains)
        local world = favorites_world({}, {
            { cqi = 1, name = 'r1', province = 'p1', slots = { { level = 'l1', upgrade = true } } }
        })
        world.settings.auto_upgrade_enabled = true
        world.upgrades = { l1 = upgrades }
        world.chains = chains
        local game = start(world)
        game.turn()
        return world, game
    end

    local world, game = upgrade_of({ 'up_a', 'up_b' })
    check('a choice inside the chain is left to the player', #world.queued == 0, table.concat(world.queued, ' '))
    check('the choice is logged', game.log():find('skip branching building', 1, true) ~= nil, game.log())

    world = upgrade_of({ 'up_other', 'up_same' }, { up_other = 'other_chain' })
    check('an upgrade into another chain is ignored', table.concat(world.queued, ' ') == 'up_same', table.concat(world.queued, ' '))

    world = upgrade_of({ 'up_other' }, { up_other = 'other_chain' })
    check('only another chain: no upgrade', #world.queued == 0, table.concat(world.queued, ' '))
end

do
    local regions = { { cqi = 1, name = 'r1', province = 'p1', slots = { {} } } }
    local world = favorites_world({ '\239\187\191fav_a' }, regions)
    world.priorities = '\239\187\191skill_a=3\n'
    world.settings.auto_skills_enabled = true
    world.points = 1
    world.skills = { { key = 'skill_b', level = 0, total = 5 }, { key = 'skill_a', level = 0, total = 5 } }
    local game = start(world)
    game.turn()
    check('a BOM: the first favorite is read', queued_count(world, 'fav_a') == 1, table.concat(world.queued, ' '))
    check('a BOM: the first priority is read', world.skills[2].level == 1, game.log())
end

do
    local function defaults_world(treasury)
        local world = favorites_world({ 'fav_a' }, { { cqi = 1, name = 'r1', province = 'p1', slots = { {} } } })
        world.no_mct = true
        world.treasury = treasury
        local game = start(world)
        game.turn()
        return world, game
    end

    local world, game = defaults_world(5100)
    check('without MCT: the favorites are built', #world.queued == 1, table.concat(world.queued, ' '))
    check('without MCT: no log file', game.log() == '', game.log())

    world = defaults_world(5050)
    check('without MCT: the minimum treasury is the default', #world.queued == 0, table.concat(world.queued, ' '))
end

-- Polling
do
    local world = { settings = {} }
    world.root = {}
    local game = start(world)
    check('the poll starts in single player', #game.polls == 1)
    for _ = 1, 3 do game.polls[1]() end
    check('closed panels: no errors', game.errors() == '', game.errors())
end

do
    local world = { is_mp = true, settings = {} }
    local game = start(world)
    check('no poll in multiplayer', #game.polls == 0)
end

do
    local world = { settings = {} }
    world.root = {}
    world.find_child = function() error('boom') end
    local game = start(world)
    for _ = 1, 30 do game.polls[1]() end
    check('a failing step stops after the limit', count(game.errors(), 'poll_ui') == 30, count(game.errors(), 'poll_ui'))
end

do
    local world = { settings = {} }
    world.root = {}
    local polls = 0
    world.find_child = function()
        polls = polls + 1
        if polls % 4 <= 1 then error('boom') end
        return false
    end
    local game = start(world)
    for _ = 1, 100 do game.polls[1]() end
    -- Three steps take 300 calls, and every other pair of them fails
    check('failures with successes in between do not stop a step', count(game.errors(), 'poll_ui') == 150, count(game.errors(), 'poll_ui'))
end

-- A small UI tree
local ui = {}
ui.__index = ui
local function node(id, parent)
    local n = setmetatable({ id = id, children = {}, parent = parent, images = { 'frame0', 'frame1', 'frame2' }, visible = true }, ui)
    if parent then table.insert(parent.children, n) end
    return n
end
function ui:Id() return self.id end
function ui:ChildCount() return #self.children end
function ui:Parent() return self.parent end
function ui:Visible() return self.visible end
function ui:SetVisible(value) self.visible = value end
function ui:NumImages() return #self.images end
function ui:GetImagePath(i) return self.images[i + 1] end
function ui:SetImagePath(path, i) self.images[i + 1] = path end
function ui:SetTooltipText(text, _, all_states)
    self.tooltip = text
    self.tooltip_all_states = all_states
end
function ui:SetDockingPoint() end
function ui:SetDockOffset() end
function ui:Layout() end
function ui:IsMouseOverChildren() return self.hovered == true end
function ui:CurrentState() return self.state or 'active' end
function ui:SetState(state) self.state = state end
function ui:GetContextObjectId() return self.context_id or '' end
function ui:Find(what)
    if type(what) == 'number' then return self.children[what + 1] end
    for _, child in ipairs(self.children) do
        if child.id == what then return child end
        local found = child:Find(what)
        if found then return found end
    end
    return nil
end

local function ui_world(settings)
    local root = node('root')
    local character_panel = node('character_details_panel', root)
    local parent = node('tab_panels', character_panel)
    local skills = node('character_details_panel_skills', parent)
    local chain = node('chain', node('chain1', node('list_box', skills)))
    local card = node('card', node('skill_key', node('module_skill_key', chain)))
    local equipment = node('equipment_holder', parent)
    local other_header = node('header', node('ancillary_parent', equipment))
    local global_pool = node('global_pool', equipment)
    local pool_header = node('header', global_pool)
    local settlement_panel = node('settlement_panel', root)
    local slots = node('default_slots_list', node('settlement', node('settlement_list', settlement_panel)))
    local slot = node('slot', slots)
    slot.hovered = true
    slot.context_id = 'slot_1'
    local options_list = node('options_list', node('building_construction_popup', slot))
    return {
        settings = settings,
        root = root,
        card = card,
        global_pool = global_pool,
        pool_header = pool_header,
        other_header = other_header,
        slot = slot,
        slots_list = slots,
        options_list = options_list,
        find_child = function(parent_uic, name)
            for _, child in ipairs(parent_uic.children) do
                if child.id == name then return child end
            end
            return false
        end,
        make_button = function(name, parent_uic)
            return parent_uic:Find(name) or node(name, parent_uic)
        end
    }
end

do
    local settings = { favorite_buildings_enabled = true, auto_skills_enabled = true }
    local world = ui_world(settings)
    local game = start(world)
    game.polls[1]()
    local star = world.card:Find('af_tweaker_skill_priority_button')
    local favorite = world.options_list:Find('af_tweaker_favorite_button')
    check('the skill star appears', star ~= nil and star.visible)
    check('the favorite star appears', favorite ~= nil and favorite.visible)
    check('the star shows no priority', star and star.images[1]:find('priority_0') ~= nil)
    check('tooltips are set for all states', star.tooltip_all_states == true and favorite.tooltip_all_states == true)

    game.listeners.AfTweakerSkillButton.handler({ component = star, string = star.id })
    check('a click sets the priority', star.images[1]:find('priority_1') ~= nil, star.images[1])
    check('the priority is saved', read_file(priorities_file):find('skill_key=1', 1, true) ~= nil)

    game.listeners.AfTweakerFavoriteButton.handler({ component = favorite, string = favorite.id })
    check('a click adds the favorite', read_file(favorites_file):find('chain_first_level=1', 1, true) ~= nil)
    check('the favorite star shows the priority', favorite.images[1]:find('favorite_priority_1', 1, true) ~= nil, favorite.images[1])

    settings.favorite_buildings_enabled = false
    settings.auto_skills_enabled = false
    game.polls[1]()
    check('options off hide the stars', not star.visible and not favorite.visible)

    local before = read_file(priorities_file)
    game.listeners.AfTweakerSkillButton.handler({ component = star, string = star.id })
    check('a click does nothing while off', read_file(priorities_file) == before)

    settings.favorite_buildings_enabled = true
    settings.auto_skills_enabled = true
    game.polls[1]()
    check('options on show the stars again', star.visible and favorite.visible)
    check('no UI errors', game.errors() == '', game.errors())
end

do
    local world = ui_world({ favorite_buildings_enabled = true, auto_skills_enabled = false })
    local second = node('slot', world.slots_list)
    second.context_id = 'slot_2'
    local second_list = node('options_list', node('building_construction_popup', second))
    local game = start(world)
    game.polls[1]()
    world.slot.hovered, second.hovered = false, true
    game.polls[1]()
    local first_star = world.options_list:Find('af_tweaker_favorite_button')
    local second_star = second_list:Find('af_tweaker_favorite_button')
    game.listeners.AfTweakerFavoriteButton.handler({ component = second_star, string = second_star.id })
    world.slot.hovered, second.hovered = true, false
    game.polls[1]()
    check('a star of the same chain follows the last click', first_star.images[1]:find('favorite_priority_1', 1, true) ~= nil, first_star.images[1])
end

do
    local world = ui_world({ favorite_buildings_enabled = true, auto_skills_enabled = false })
    world.slot_keys = { slot_1 = 'first_chain', slot_2 = 'second_chain' }
    local second = node('slot', world.slots_list)
    second.context_id = 'slot_2'
    local second_list = node('options_list', node('building_construction_popup', second))
    local game = start(world)
    game.polls[1]()
    world.slot.hovered, second.hovered = false, true
    game.polls[1]()
    local second_star = second_list:Find('af_tweaker_favorite_button')
    world.slot.hovered, second.hovered = true, false
    game.polls[1]()
    -- The star of the second slot is clicked before a poll sees the mouse there
    game.listeners.AfTweakerFavoriteButton.handler({ component = second_star, string = second_star.id })
    check('a click goes to the slot of its star', read_file(favorites_file) == 'second_chain=1\n', read_file(favorites_file))
    check('the clicked star shows its own building', second_star.images[1]:find('favorite_priority_1', 1, true) ~= nil, second_star.images[1])
    check('such a click: no errors', game.errors() == '', game.errors())
end

do
    local world = ui_world({ favorite_buildings_enabled = true, auto_skills_enabled = false })
    world.favorites = { 'other=2' }
    local game = start(world)
    game.polls[1]()
    local star = world.options_list:Find('af_tweaker_favorite_button')
    local function click_shows(priority, file_text)
        game.listeners.AfTweakerFavoriteButton.handler({ component = star, string = star.id })
        check('a click: the icon of priority ' .. priority, star.images[1]:find('favorite_priority_' .. priority, 1, true) ~= nil, star.images[1])
        check('a click: the file with priority ' .. priority, read_file(favorites_file) == file_text, read_file(favorites_file))
    end

    check('a building without stars has the grey star', star.images[1]:find('favorite_priority_0', 1, true) ~= nil, star.images[1])
    check('the tooltip of no stars', star.tooltip:find('not built automatically', 1, true) ~= nil, star.tooltip)
    click_shows(1, 'other=2\nchain_first_level=1\n')
    click_shows(2, 'other=2\nchain_first_level=2\n')
    click_shows(3, 'other=2\nchain_first_level=3\n')
    check('the tooltip of the priority', star.tooltip:find('priority 3 of 3', 1, true) ~= nil, star.tooltip)
    click_shows(0, 'other=2\n')
    check('the stars: no errors', game.errors() == '', game.errors())
end

do
    local world = ui_world({ favorite_buildings_enabled = true, auto_skills_enabled = false })
    world.favorites = { 'chain_first_level', 'other=2' }
    local game = start(world)
    game.polls[1]()
    local star = world.options_list:Find('af_tweaker_favorite_button')
    check('a favorite of an old list has one star', star.images[1]:find('favorite_priority_1', 1, true) ~= nil, star.images[1])
    game.listeners.AfTweakerFavoriteButton.handler({ component = star, string = star.id })
    check('a new priority keeps the place in the list', read_file(favorites_file) == 'chain_first_level=2\nother=2\n', read_file(favorites_file))
end

do
    local world = ui_world({ favorite_buildings_enabled = true, auto_skills_enabled = false })
    local second = node('slot', world.slots_list)
    second.context_id = 'slot_2'
    local game = start(world)
    world.slot.hovered, second.hovered = false, true
    game.polls[1]()
    check('a popup of another slot gets no star', world.options_list:Find('af_tweaker_favorite_button') == nil)
end

do
    local world = ui_world({ favorite_buildings_enabled = true, auto_skills_enabled = false })
    local game = start(world)
    game.polls[1]()
    local star = world.options_list:Find('af_tweaker_favorite_button')
    world.slot.context_id = nil
    game.listeners.AfTweakerFavoriteButton.handler({ component = star, string = star.id })
    check('a star without a slot changes nothing', read_file(favorites_file):find('chain_first_level', 1, true) == nil, read_file(favorites_file))
    check('a star without a slot is logged', game.errors():find('building not found', 1, true) ~= nil, game.errors())
end

-- Auto fuse
local function fuse_world(items, settings)
    local world = ui_world(settings or { auto_fuse_enabled = true })
    world.items = items
    return world
end

local function item(key, level, category, extra)
    local result = { key = key, level = level, category = category or 'weapon' }
    for name, value in pairs(extra or {}) do result[name] = value end
    return result
end

local function item_keys(world)
    local keys = {}
    for _, data in ipairs(world.items) do table.insert(keys, data.key) end
    table.sort(keys)
    return table.concat(keys, ' ')
end

local function fusions(world)
    return table.concat(world.fusions, ' ')
end

do
    local world = fuse_world({
        item('u1', 'uncommon'),
        item('c1', 'common'),
        item('c2', 'common'),
        item('c3', 'common'),
        item('a1', 'common', 'armour'),
        item('a2', 'common', 'armour', { equipped = true }),
        item('r1', 'rare'),
        item('r2', 'rare'),
        item('f1', 'common', 'general'),
        item('f2', 'common', 'general'),
        item('x1', 'crafted', 'enchanted_item'),
        item('x2', 'crafted', 'enchanted_item')
    })
    local game = start(world)
    game.fuse()
    check('auto fuse: common pairs first, then uncommon ones with the new items', fusions(world) == 'c1+c2 u1+new_1', fusions(world))
    check('auto fuse: equipped, rare, crafted items and followers are kept',
        item_keys(world) == 'a1 a2 c3 f1 f2 new_2 r1 r2 x1 x2', item_keys(world))
    check('auto fuse: one fusion per round', game.steps == 2, game.steps)
    check('auto fuse: the log', game.log():find('auto fuse done, common pairs: 1, uncommon pairs: 1', 1, true) ~= nil, game.log())
    check('auto fuse: no errors', game.errors() == '', game.errors())

    game.fuse()
    check('auto fuse: a second click finds nothing',
        #world.fusions == 2 and game.log():find('common pairs: 0, uncommon pairs: 0', 1, true) ~= nil, game.log())
end

do
    local world = fuse_world({ item('c1', 'common'), item('c2', 'common'), item('u1', 'uncommon') })
    world.fuse_delay = 2
    world.new_item_delay = 1
    local game = start(world)
    game.fuse()
    check('auto fuse: a slow game and a late new item', fusions(world) == 'c1+c2 u1+new_1', fusions(world))
    check('auto fuse: a slow game is no error', game.errors() == '', game.errors())
end

do
    local world = fuse_world({ item('c1', 'common', 'weapon', { refuse = true }), item('c2', 'common'), item('c3', 'common') })
    local game = start(world)
    game.fuse()
    check('auto fuse: a pair the game refuses is skipped', fusions(world) == 'c2+c3', fusions(world))
end

do
    local world = fuse_world({ item('c1', 'common'), item('c2', 'common') })
    world.refuse_fusions = true
    local game = start(world)
    game.fuse()
    check('auto fuse: a fusion that never comes stops the run',
        #game.commands == 1 and game.errors():find('did not fuse common: c1 name (c1) + c2 name (c2)', 1, true) ~= nil, game.errors())
    world.refuse_fusions = false
    game.fuse()
    check('auto fuse: a new click works after that', fusions(world) == 'c1+c2', fusions(world))
end

do
    local world = fuse_world({ item('c1', 'common'), item('c2', 'common'), item('c3', 'common'), item('c4', 'common') })
    world.fuse_delay = 1
    local game = start(world)
    game.click_fuse()
    world.turn_over = true
    game.run_timers()
    check('auto fuse: the run stops when the turn ends',
        #game.commands == 1 and game.log():find('auto fuse stopped', 1, true) ~= nil, game.log())

    game.fuse()
    check('auto fuse: no fusion out of the turn', #game.commands == 1, #game.commands)
end

do
    local world = fuse_world({ item('c1', 'common'), item('c2', 'common') }, { auto_fuse_enabled = false })
    local game = start(world)
    game.fuse()
    check('auto fuse: no fusion with the option off', #game.commands == 0, #game.commands)
end

do
    local settings = { auto_fuse_enabled = true }
    local world = fuse_world({ item('c1', 'common'), item('c2', 'common') }, settings)
    world.fuse_delay = 1
    local game = start(world)
    game.polls[1]()
    local button = world.pool_header:Find('af_tweaker_auto_fuse_button')
    check('the fuse button appears in the header of the pool', button ~= nil and button.visible)
    check('the fuse button is not in another header', world.other_header:Find('af_tweaker_auto_fuse_button') == nil)
    check('the fuse button has its icon', button.images[1] == 'ui/skins/default/af_tweaker_auto_fuse.png', button.images[1])
    check('the fuse button has a tooltip for all states', button.tooltip_all_states == true)

    game.click_fuse()
    game.polls[1]()
    check('the fuse button is inactive during a run', button:CurrentState() == 'inactive', button:CurrentState())
    game.click_fuse()
    check('a click during a run starts nothing', #game.commands == 1, #game.commands)
    game.run_timers()
    game.polls[1]()
    check('the fuse button is active after the run', button:CurrentState() == 'active', button:CurrentState())

    settings.auto_fuse_enabled = false
    game.polls[1]()
    check('the option off hides the fuse button', not button.visible)
    settings.auto_fuse_enabled = true
    game.polls[1]()
    check('the option on shows the fuse button again', button.visible)
    check('the fuse button: no errors', game.errors() == '', game.errors())
end

-- Settings: the MCT file against the defaults of the script
do
    local mct_source = read_file('mods/warhammer_3/af-tweaker/script/mct/settings/af_tweaker.lua')
    local mod_source = read_file(mod_path)
    assert(mct_source ~= '' and mod_source ~= '', 'run it from the repository root')

    local options, title = {}, nil
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
            options[key] = setmetatable({ type = option_type }, { __index = option_methods })
            return options[key]
        end
    }
    local env = setmetatable({
        get_mct = function()
            return { register_mod = function(_, key) assert(key == 'af_tweaker', key); return mct_mod end }
        end
    }, { __index = _G })
    assert(load(mct_source, 'af_tweaker_mct', 't', env))()

    -- The timings and the limits aren't settings of the player
    local internal = {
        turn_start_delay = true, round_delay = true, skill_commit_rounds = true, fuse_confirm_rounds = true,
        ui_poll_ms = true, ui_poll_max_failures = true
    }
    local defaults = {}

    for key, value in mod_source:match('local settings = (%b{})'):gmatch('([%w_]+) = ([%w%.]+)') do
        if value == 'true' or value == 'false' then
            defaults[key] = value == 'true'
        else
            defaults[key] = tonumber(value)
        end
    end

    for key, value in pairs(defaults) do
        local option = options[key]
        if internal[key] then
            check(key .. ': not an MCT option', option == nil)
        else
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
    end

    for key in pairs(options) do
        check('a default for the MCT option ' .. key, defaults[key] ~= nil)
    end

    local version = mod_source:match("mod_version = '([%d%.]+)'")
    check('the MCT title has the version of the script', title == 'AF Tweaker v' .. version, title)
end

print(failed == 0 and 'ALL PASSED' or (failed .. ' FAILED'))
os.exit(failed == 0 and 0 or 1)
