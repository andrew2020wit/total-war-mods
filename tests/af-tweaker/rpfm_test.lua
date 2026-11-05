-- Runs the mod with the game's real script libraries, through run_lua_tests of RPFM's MCP
-- server, see af-tweaker-agent.md. The scripts come from the open pack, so rebuild it first.
-- There are no CCOs or UI in the test engine: the answers of the game below are a model, so
-- the context expressions themselves stay unverified. It isn't part of the mod.

-- The test engine of RPFM v5.3.3 doesn't quite match the current game
getmetatable(out).__call = function() end
rawset(out, "tab_levels", setmetatable({}, { __index = function() return 0 end }))
CampaignUI = setmetatable({}, { __index = function() return function() return false end end })
real_timer = { register_repeating = function() end, register_singleshot = function() end, unregister = function() end }

FILES = { ['!!af_tweaker-skill-priorities.txt'] = 'locked=3\n', ['!!af_tweaker-favorites.txt'] = 'fav_pooled2\nfav_pooled=2\n' }
local real_open = io.open
io.open = function(name, mode)
    if not string.find(name, '!!af_tweaker', 1, true) then return real_open(name, mode) end
    if mode == 'r' and not FILES[name] then return nil end
    if mode == 'w' then FILES[name] = '' end
    return {
        lines = function() return string.gmatch(FILES[name], '[^\n]+') end,
        write = function(_, text) FILES[name] = (FILES[name] or '') .. text end,
        close = function() end
    }
end

OVERRIDES = { enable_logging = true, min_treasury = 0 }
get_mct = function()
    return { get_mod_by_key = function() return { get_option_by_key = function(_, key)
        return { get_finalized_setting = function() return OVERRIDES[key] end }
    end } end }
end

local slots_region = rpfm.region {
    key = "wh3_main_combi_region_altdorf", cqi = 7, province_name = "p1", has_development_points_to_upgrade = true,
    garrison_residence = rpfm.object("GARRISON_RESIDENCE_SCRIPT_INTERFACE", { is_under_siege = false })
}
local player = rpfm.faction { key = "wh_main_vmp_vampire_counts", is_human = true, treasury = 1000, is_factions_turn = true, region_list = { slots_region } }
local hero = rpfm.character { faction = player, is_wounded = false, command_queue_index = 1 }
rpfm.mock(player, "character_list", { hero })

-- string.find with a pattern always returns nil in the test engine
local function has(text, pattern) return string.match(text, pattern) ~= nil end
local function has_plain(text, part) return string.find(text, part, 1, true) ~= nil end

local function count(text, part)
    local n, from = 0, 1
    while true do
        local at = string.find(text, part, from, true)
        if not at then return n end
        n = n + 1
        from = at + 1
    end
end

-- rpfm.advance_time doesn't fire the timers of cm:callback
local clock, timers = 0, {}

local function pump(seconds)
    local stop = clock + seconds
    while true do
        local best = nil
        for i, timer in ipairs(timers) do
            if timer.at <= stop and (not best or timer.at < timers[best].at) then best = i end
        end
        if not best then break end
        local timer = table.remove(timers, best)
        clock = timer.at
        timer.f()
    end
    clock = stop
end

local function install_model(world)
    world.queued = {}
    local function slot_of(expr) return tonumber(string.match(expr, 'At%((%d+)%)')) end
    local function level_of(expr)
        local key = nil
        for k in string.gmatch(expr, 'Key == "(.-)"') do key = k end
        return key
    end
    local function info(key) return world.levels[key] or {} end
    cm.callback = function(_, f, delay) table.insert(timers, { at = clock + delay, f = f }) end
    cm.get_local_faction_name = function() return "wh_main_vmp_vampire_counts" end
    cm.get_building_level_upgrades = function(_, key) return { world.upgrades[key] } end
    cm.building_chain_key_for_building = function() return 'chain' end
    common.get_context_value = function(context, id, expr)
        if context == 'CcoBuildingLevelRecord' then
            if expr == 'Key' then return id end
            return 'Name of ' .. id
        end
        if context == 'CcoCampaignFaction' then
            local items = world.items
            if expr == 'AncillaryList.Size' then return #items end
            local data = items[tonumber(string.match(expr, 'At%((%d+)%)')) + 1]
            if has(expr, '^IsContextValid%(AncillaryList') then
                return not data.equipped and not has_plain(expr, '.FrameState != "' .. data.level .. '"')
            end
            local other = string.match(expr, '%.CanFuse%(AncillaryList%.At%((%d+)%)%)$')
            if other then return data.level == items[tonumber(other) + 1].level end
            if has(expr, '%.FrameState$') then return data.level end
            if has(expr, '%.Category$') then return 'weapon' end
            if has(expr, '%.Key$') or has(expr, '%.Name$') then return data.key end
            error('item expression: ' .. expr)
        end
        if context == 'CcoCampaignCharacter' then
            local index = tonumber(string.match(expr, '^SkillList%.At%((%d+)%)'))
            if expr == 'SkillPointsAvailable' then return world.points end
            if expr == 'SkillList.Size' then return #world.skills end
            if expr == 'Name' then return 'Hero' end
            local skill = index and world.skills[index + 1]
            if has_plain(expr, '.Status == "active"') then return skill.level < skill.total end
            if has(expr, '%.Key$') then return skill.key end
            if has(expr, '%.Level$') then return skill.level end
            if has(expr, '%.Name$') then return skill.key end
            if has(expr, '%.Status$') then return 'active' end
            error('skill expression: ' .. expr)
        end
        if expr == 'this.BuildingSlotList.Size' then return #world.slots end
        if expr == 'this.Name' then return 'Region' end
        local slot = slot_of(expr)
        local data = slot and world.slots[slot + 1]
        if has_plain(expr, '.IsEmpty == false && ') then return data.level ~= nil and not data.busy end
        if has_plain(expr, '.IsEmpty && ') then return data.level == nil and not data.busy end
        if has(expr, 'BuildingLevelRecordContext%.Key$') then return data.level end
        if has(expr, '^IsContextValid') and has_plain(expr, 'Pooled') then return info(level_of(expr)).pooled == true end
        if has(expr, '^IsContextValid') then return true end
        if has_plain(expr, 'IsActiveForBuildingBrowser') then return true end
        if has_plain(expr, 'IsLockedByAnyTech') then return true end
        if has_plain(expr, 'CreateCost') then return info(level_of(expr)).cost or 100 end
        if has_plain(expr, 'DevelopmentPointCost') then return info(level_of(expr)).development or 0 end
        error('settlement expression: ' .. expr)
    end
    common.call_context_command = function(context, _, expr)
        if context == 'CcoCampaignFaction' then
            local first, second = string.match(expr, '^AncillaryList%.At%((%d+)%)%.FuseForPlayer%(AncillaryList%.At%((%d+)%)%)$')
            local pair = { world.items[tonumber(first) + 1], world.items[tonumber(second) + 1] }
            -- Like the game and the vanilla listener of the event
            cm:callback(function()
                for _, data in ipairs(pair) do
                    for i, other in ipairs(world.items) do
                        if other == data then table.remove(world.items, i) break end
                    end
                end
                world.fused = (world.fused or 0) + 1
                rpfm.fire("AncillariesFused", {
                    faction = player, first_ancillary_key = pair[1].key, second_ancillary_key = pair[2].key
                })
                table.insert(world.items, { key = 'new' .. world.fused, level = pair[1].level == 'common' and 'uncommon' or 'rare' })
            end, 0.1)
        elseif context == 'CcoCampaignCharacter' then
            if expr == 'CommitSkillChoices' then
                local skill = world.added
                world.added = nil
                cm:callback(function()
                    if skill and not skill.refuse then
                        skill.level = skill.level + 1
                        world.points = world.points - 1
                    end
                end, world.commit_time or 0.1)
            else
                world.added = world.skills[tonumber(string.match(expr, 'At%((%d+)%)')) + 1]
            end
        else
            local data = world.slots[slot_of(expr) + 1]
            cm:callback(function() data.busy = true end, 0.1)
            table.insert(world.queued, level_of(expr) or 'upgrade')
        end
    end
end

local function log_text() return FILES['!!af_tweaker.txt'] or '' end
local function errors_text() return FILES['!!af_tweaker-errors.txt'] or '' end

local function play()
    rpfm.fire("FactionTurnStart", { faction = player })
    pump(60)
end

local function report(name) print('AFT ' .. name .. ' | errors: ' .. errors_text() .. ' | log: ' .. string.gsub(log_text(), '\n', ' / ')) end

rpfm.test("first tick ran", function()
    rpfm.assert_equal(has_plain(log_text(), 'Tweaker start'), true)
end)

rpfm.test("skills", function()
    OVERRIDES.auto_upgrade_enabled = false
    OVERRIDES.favorite_buildings_enabled = false
    OVERRIDES.auto_skills_enabled = true
    local world = {
        points = 3, levels = {}, upgrades = {}, slots = {},
        skills = { { key = 'locked', level = 0, total = 3, refuse = true }, { key = 'a', level = 0, total = 1 }, { key = 'b', level = 0, total = 5 } }
    }
    install_model(world)
    play()
    report('skills')
    rpfm.assert_equal(world.points, 0)
    rpfm.assert_equal(count(log_text(), 'not charged'), 1)
    rpfm.assert_equal(has_plain(log_text(), 'characters: 1, points spent: 3'), true)
    rpfm.assert_equal(errors_text(), '')
end)

rpfm.test("a slow commit", function()
    OVERRIDES.auto_upgrade_enabled = false
    OVERRIDES.favorite_buildings_enabled = false
    OVERRIDES.auto_skills_enabled = true
    local world = { points = 3, commit_time = 1.2, levels = {}, upgrades = {}, slots = {}, skills = { { key = 'a', level = 0, total = 5 } } }
    install_model(world)
    play()
    report('slow')
    rpfm.assert_equal(world.points, 0)
    rpfm.assert_equal(count(log_text(), 'not charged'), 0)
end)

rpfm.test("buildings", function()
    OVERRIDES.auto_upgrade_enabled = true
    OVERRIDES.favorite_buildings_enabled = true
    OVERRIDES.auto_skills_enabled = false
    local world = {
        upgrades = { l1 = 'up_pooled1', l2 = 'up_gold', l3 = 'up_dev1', l4 = 'up_dev2' },
        levels = { fav_pooled = { pooled = true }, fav_pooled2 = { pooled = true }, up_pooled1 = { pooled = true }, up_dev1 = { development = 1 }, up_dev2 = { development = 1 } },
        slots = { { level = 'l1' }, { level = 'l2' }, { level = 'l3' }, { level = 'l4' }, {}, {} }
    }
    install_model(world)
    play()
    print('AFT queued: ' .. table.concat(world.queued, ' '))
    report('buildings')
    rpfm.assert_equal(#world.queued, 6)
    rpfm.assert_equal(world.queued[1], 'fav_pooled')
    rpfm.assert_equal(world.queued[2], 'fav_pooled2')
    rpfm.assert_equal(count(log_text(), 'auto build done'), 1)
    rpfm.assert_equal(errors_text(), '')
end)

rpfm.test("auto fuse", function()
    OVERRIDES.auto_upgrade_enabled = false
    OVERRIDES.favorite_buildings_enabled = false
    OVERRIDES.auto_skills_enabled = false
    OVERRIDES.auto_fuse_enabled = true
    OVERRIDES.auto_fuse_uncommon = true
    local world = {
        levels = {}, upgrades = {}, slots = {}, skills = {},
        items = {
            { key = 'u1', level = 'uncommon' }, { key = 'c1', level = 'common' },
            { key = 'c2', level = 'common' }, { key = 'c3', level = 'common', equipped = true }
        }
    }
    install_model(world)
    rpfm.fire("ComponentLClickUp", { string = 'af_tweaker_auto_fuse_button' })
    pump(60)
    report('fuse')
    rpfm.assert_equal(world.fused, 2)
    rpfm.assert_equal(has_plain(log_text(), 'common pairs: 1, uncommon pairs: 1'), true)
    rpfm.assert_equal(errors_text(), '')
end)

rpfm.test("auto fuse keeps uncommon items", function()
    OVERRIDES.auto_upgrade_enabled = false
    OVERRIDES.favorite_buildings_enabled = false
    OVERRIDES.auto_skills_enabled = false
    OVERRIDES.auto_fuse_enabled = true
    OVERRIDES.auto_fuse_uncommon = false
    local world = {
        levels = {}, upgrades = {}, slots = {}, skills = {},
        items = { { key = 'u1', level = 'uncommon' }, { key = 'c1', level = 'common' }, { key = 'c2', level = 'common' } }
    }
    install_model(world)
    rpfm.fire("ComponentLClickUp", { string = 'af_tweaker_auto_fuse_button' })
    pump(60)
    report('fuse uncommon off')
    rpfm.assert_equal(world.fused, 1)
    rpfm.assert_equal(has_plain(log_text(), 'auto fuse done, common pairs: 1'), true)
    rpfm.assert_equal(errors_text(), '')
end)

rpfm.test("the turn ends during the rounds", function()
    OVERRIDES.auto_upgrade_enabled = false
    OVERRIDES.favorite_buildings_enabled = false
    OVERRIDES.auto_skills_enabled = true
    local world = { points = 5, levels = {}, upgrades = {}, slots = {}, skills = { { key = 'a', level = 0, total = 5 } } }
    install_model(world)
    rpfm.fire("FactionTurnStart", { faction = player })
    pump(1.6)
    rpfm.mock(player, "is_factions_turn", false)
    pump(60)
    report('turn end')
    rpfm.assert_equal(world.points > 0, true)
    rpfm.assert_equal(errors_text(), '')
end)
