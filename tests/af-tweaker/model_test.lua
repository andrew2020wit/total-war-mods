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

-- world: { skills, points, commit_delay, buildings..., settings, is_mp }
local function start(world)
    local log_name = file_prefix .. 'log.txt'
    local err_name = file_prefix .. 'errors.txt'
    os.remove(log_name); os.remove(err_name)
    write_file(favorites_file, table.concat(world.favorites or {}, '\n') .. '\n')
    write_file(priorities_file, world.priorities or '')

    local timers, listeners, first_tick, polls = {}, {}, {}, {}
    local pending_commits = {}
    local commands = {}
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

    local region = {
        cqi = function() return 7 end,
        name = function() return 'r1' end,
        province_name = function() return 'p1' end,
        has_development_points_to_upgrade = function() return (world.development_points or 0) > 0 end,
        garrison_residence = function() return { is_under_siege = function() return false end } end
    }
    local function list(items)
        return { num_items = function() return #items end, item_at = function(_, i) return items[i + 1] end }
    end
    local character = {
        is_wounded = function() return false end,
        command_queue_index = function() return 1 end
    }
    local faction = {
        name = function() return 'player' end,
        treasury = function() return world.treasury or 100000 end,
        region_list = function() return list(world.slots and { region } or {}) end,
        character_list = function() return list(world.skills and { character } or {}) end,
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
        get_building_level_upgrades = function(_, key) return world.upgrades and { world.upgrades[key] } end,
        building_chain_key_for_building = function() return 'chain' end
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

    env.common = {
        get_context_value = function(context, id, expr)
            if context == 'CcoBuildingLevelRecord' then
                if expr == 'Key' then return id end
                return 'Name of ' .. id
            end

            if context == 'CcoCampaignBuildingSlot' then
                if expr:find('IsEmpty == false') then return true end
                return 'chain_first_level'
            end

            if context == 'CcoCampaignCharacter' then
                local index = tonumber(expr:match('^SkillList%.At%((%d+)%)'))
                if expr == 'SkillPointsAvailable' then return world.points end
                if expr == 'SkillList.Size' then return #world.skills end
                if expr == 'Name' then return 'Hero' end
                local skill = index and world.skills[index + 1]
                if expr:find('%.Status == "active"') then return skill.level < skill.total end
                if expr:find('%.Key$') then return skill.key end
                if expr:find('%.Name$') then return skill.key .. ' name' end
                if expr:find('%.Status$') then return 'active' end
                error('skill expression: ' .. expr)
            end

            -- settlement
            if expr == 'this.BuildingSlotList.Size' then return #world.slots end
            if expr == 'this.Name' then return 'Region' end
            local slot = slot_of(expr)
            local data = slot and world.slots[slot + 1]
            if expr:find('%.IsEmpty == false && ') then
                return data.level ~= nil and data.upgrade == true and not data.busy
            end
            if expr:find('%.IsEmpty && ') then return data.level == nil and not data.busy end
            if expr:find('BuildingLevelRecordContext%.Key$') then return data.level end
            if expr:find('^IsContextValid') and expr:find('Pooled') then
                return level_info(level_of(expr)).pooled == true
            end
            if expr:find('^IsContextValid') then
                return world.is_favorite_possible == nil or world.is_favorite_possible(level_of(expr))
            end
            if expr:find('IsActiveForBuildingBrowser') then return true end
            if expr:find('IsLockedByAnyTech') then return true end
            if expr:find('CreateCost') then return level_info(level_of(expr)).cost or 100 end
            if expr:find('DevelopmentPointCost') then return level_info(level_of(expr)).development or 0 end
            error('settlement expression: ' .. expr)
        end,
        call_context_command = function(context, id, expr)
            table.insert(commands, expr)
            if context == 'CcoCampaignCharacter' then
                if expr == 'CommitSkillChoices' then
                    local pending = world.added
                    world.added = nil
                    table.insert(pending_commits, { rounds = world.commit_delay or 0, skill = pending })
                else
                    local skill = world.skills[tonumber(expr:match('At%((%d+)%)')) + 1]
                    world.added = skill
                end
            else
                local slot = world.slots[slot_of(expr) + 1]
                if not world.refuse_buildings then slot.busy = true end
                table.insert(world.queued, level_of(expr) or 'upgrade ' .. slot_of(expr))
            end
        end
    }

    local function apply_commits()
        for i = #pending_commits, 1, -1 do
            local commit = pending_commits[i]
            if commit.rounds == 0 then
                table.remove(pending_commits, i)
                if commit.skill and not commit.skill.refuse then
                    commit.skill.level = commit.skill.level + 1
                    world.points = world.points - 1
                end
            else
                commit.rounds = commit.rounds - 1
            end
        end
    end

    local chunk = assert(loadfile(mod_path, 't', env))
    chunk()
    for _, f in ipairs(first_tick) do f() end

    local game = { polls = polls, commands = commands, listeners = listeners }

    function game.turn()
        listeners.AfTweakerAutoUpgrade.handler({
            faction = function() return faction end
        })
        local steps = 0
        while #timers > 0 do
            steps = steps + 1
            if steps > 200 then error('rounds never end') end
            local batch = timers
            timers = {}
            apply_commits()
            for _, f in ipairs(batch) do f() end
        end
        apply_commits()
        game.steps = steps
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
    game.turn()
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
        points = 5,
        skills = { { key = 'a', level = 0, total = 5 } }
    }
    local game = start(world)
    world.turn_over = true
    game.turn()
    check('nothing is spent after the turn ended', world.points == 5)
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
    check('a failing step stops after the limit', count(game.errors(), 'poll_ui') == 20, count(game.errors(), 'poll_ui'))
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
function ui:SetTooltipText(text) self.tooltip = text end
function ui:SetDockingPoint() end
function ui:SetDockOffset() end
function ui:SetState(state) self.state = state end
function ui:Layout() end
function ui:IsMouseOverChildren() return self.hovered == true end
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

    game.listeners.AfTweakerSkillButton.handler({ component = star, string = star.id })
    check('a click sets the priority', star.images[1]:find('priority_1') ~= nil, star.images[1])
    check('the priority is saved', read_file(priorities_file):find('skill_key=1', 1, true) ~= nil)

    game.listeners.AfTweakerFavoriteButton.handler({ component = favorite, string = favorite.id })
    check('a click adds the favorite', read_file(favorites_file):find('chain_first_level', 1, true) ~= nil)
    check('the favorite star is selected', favorite.state == 'selected')

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

print(failed == 0 and 'ALL PASSED' or (failed .. ' FAILED'))
os.exit(failed == 0 and 0 or 1)
