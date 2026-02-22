-- Turn crash debug logger, "Total War Warhammer 3" modification

local mod_version = '2.0.2'
local column_divider = '\t'

local function log(event, context)
    local file = io.open('!af_turn_crash_debug_logger.csv', "a")

    if not file then
        out('no file')

        return
    end

    file:write(
        mod_version .. column_divider ..
        os.date("%Y-%m-%d %H.%M.%S") .. column_divider ..
        tostring(event) .. column_divider ..
        tostring(context) .. "\n"
        )

    file:close()
end

local turn_start_event =  "FactionTurnStart"
core:add_listener(
    turn_start_event,
    turn_start_event,
    true,
    function (context)
        local faction = context:faction()

        if faction:is_null_interface() then
            log(turn_start_event, "is_null_interface()")
        else
            local faction_name = context:faction():name()
            log(turn_start_event, faction_name)
        end
    end,
    true
)

local turn_end_event =  "FactionTurnEnd"
core:add_listener(
    turn_end_event,
    turn_end_event,
    true,
    function (context)
        local faction = context:faction()

        if faction:is_null_interface() then
            log(turn_end_event, "is_null_interface()")
        else
            local faction_name = context:faction():name()
            log(turn_end_event, faction_name)
        end
    end,
    true
)

local function compute_character_log_text(character)
    return " Name: " ..
            character:character_subtype_key() ..
            " Level: " ..
            character:rank()..
            " cqi: " ..
            character:command_queue_index()
end

local character_turn_start_event =  "CharacterTurnStart"
core:add_listener(
    character_turn_start_event,
    character_turn_start_event,    
    true,
    function(context)
        local character = context:character()

        local context_log_text = compute_character_log_text(character)

        log(character_turn_start_event, context_log_text)
    end,
    true
)

local character_turn_end_event =  "CharacterTurnEnd"
core:add_listener(
    character_turn_end_event,
    character_turn_end_event,    
    true,
    function(context)
        local character = context:character()

        local context_log_text = compute_character_log_text(character)

        log(character_turn_end_event, context_log_text)
    end,
    true
)
