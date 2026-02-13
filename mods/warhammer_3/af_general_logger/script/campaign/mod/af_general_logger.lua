-- General Logger, "Total War Warhammer 3" modification

local mod_version = '1.0.5'
local log_file_name = '!!af_global_logger.csv'
local column_divider = '\t'

local faction_counter = 0
local current_faction_counter = 0
local region_difference = {}

local function log(text)
    local file = io.open(log_file_name, "a")

    if not file then
        out('no file')

        return
    end

    file:write(tostring(text) .. "\n")
    file:close()
end

local function add_log_line(data)
    local function get_current_time()
        return os.date()
    end

    local time = get_current_time()

    local function add_value(value)
        return tostring(value) .. column_divider
    end

    local line = (
        add_value(mod_version)
        .. add_value(time)
        .. add_value(data.log_item_type)
        .. add_value(data.turn)
        .. add_value(data.faction)
        .. add_value(data.is_human)
        .. add_value(data.culture)
        .. add_value(data.subculture)
        .. add_value(data.regions_number)
        .. add_value(data.region_number_difference)
        .. add_value(data.imperium_level)
        .. add_value(data.is_vassal)
        .. add_value(data.income)
        .. add_value(data.net_income)
        .. add_value(data.treasury)
        .. add_value(data.treasury_percent)
        .. add_value(data.at_war)
        .. add_value(data.difficulty_level)
        .. add_value(data.faction_counter)
    )

    log(line)
end 

local function add_titles()
    local data = {
        log_item_type = "header",
        turn = "turn",
        faction = "faction",
        is_human = "is_human",
        culture = "culture",
        subculture = "subculture",
        regions_number = "regions_number",
        region_number_difference = "region_number_difference",
        imperium_level = "imperium_level",
        is_vassal = "is_vassal",
        income = "income",
        net_income = "net_income",
        treasury = "treasury",
        treasury_percent = "treasury_percent",
        at_war = "at_war",
        difficulty_level = "difficulty_level",
        faction_counter = "faction_counter"
    }

    add_log_line(data)
end

add_titles()

local function log_current_faction_turn(context)
    local faction = context:faction()

    if faction:is_null_interface() then
        return
    end

    local faction_name = faction:name()
    local current_turn = cm:turn_number()
    local is_human = faction:is_human()
    local culture = faction:culture()
    local subculture = faction:subculture()
    local regions_number = faction:num_regions()
    local region_number_difference = 0
    local imperium_level = faction:imperium_level()
    local is_vassal = faction:is_vassal()
    local income = faction:income()
    local net_income = faction:net_income()
    local treasury = faction:treasury()
    local treasury_percent = faction:treasury_percent()
    local at_war = faction:at_war()
    local difficulty_level = cm:model():difficulty_level()    

    current_faction_counter = current_faction_counter + 1

    local prev_regions_number = region_difference[faction_name]
    
    region_difference[faction_name] = regions_number

    if (prev_regions_number) then
        region_number_difference = regions_number - prev_regions_number
    end

    if (is_human) then
        faction_counter = current_faction_counter
        current_faction_counter = 0
    end

    local data = {
        log_item_type = "data",
        turn = current_turn,
        faction = faction_name,
        is_human = is_human,
        culture = culture,
        subculture = subculture,
        regions_number = regions_number,
        region_number_difference = region_number_difference,
        imperium_level = imperium_level,
        is_vassal = is_vassal,
        income = income,
        net_income = net_income,
        treasury = treasury,
        treasury_percent = treasury_percent,
        at_war = at_war,
        difficulty_level = difficulty_level,
        faction_counter = faction_counter
    }

    add_log_line(data)
end

core:add_listener(
    "AddMoneyToAI",
    "FactionTurnStart",
    true,
    log_current_faction_turn,
    true
)
