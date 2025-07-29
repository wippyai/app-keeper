-- develop_init.lua
-- Initializes the Developer Assistant by unpacking provided context and preparing the task execution environment

local json = require("json")
local ctx = require("ctx")
local uuid = require("uuid")
local consts = require("consts")

-- Constants
local CONSTANTS = {
    CONTENT_TYPE_TEXT = "text/plain",
    DISCRIMINATOR = "private",
    CONTEXT_SEARCH_THRESHOLD = 100 -- minimum chars for meaningful context
}

-- Main implementation
local function execute(input_data, tool_session_context)
    local current_node_id = ctx.get("node_id")
    local dataflow_id = ctx.get("dataflow_id")

    -- Parse the delegated task input
    local task_input = {}
    if type(input_data) == "string" then
        local parsed, err = json.decode(input_data)
        if parsed then
            task_input = parsed
        else
            -- If not JSON, treat as direct task query
            task_input = { supervisor_request = input_data }
        end
    elseif type(input_data) == "table" then
        task_input = input_data
    end

    local commands = {}
    local context_items_loaded = 0

    -- Extract context UUIDs if provided
    local context_uuids = task_input.context_uuids or task_input.provided_context_uuids

    -- Create proper context references (without copying content)
    if context_uuids and type(context_uuids) == "table" and #context_uuids > 0 then
        for _, context_uuid in ipairs(context_uuids) do
            context_items_loaded = context_items_loaded + 1

            -- Create proper context reference using the same pattern as search_initializer.lua
            table.insert(commands, {
                type = "CREATE_DATA",
                payload = {
                    data_id = uuid.v7(),
                    data_type = consts.DATA_TYPE.CONTEXT_DATA,
                    content = "",  -- Empty content for reference
                    content_type = consts.CONTENT_TYPE.REFERENCE,
                    discriminator = CONSTANTS.DISCRIMINATOR,
                    key = context_uuid,  -- Key should be the referenced data_id
                    node_id = current_node_id,
                    metadata = {
                        comment = "Reference to provided context UUID: " .. context_uuid,
                        context_type = "referenced_context",
                        references_data_id = context_uuid,
                        is_reference = true,
                        source = "develop_init",
                        creator_node_id = current_node_id
                    }
                }
            })
        end
    end

    -- Store the original task input for the agent
    local task_context_content = ""
    if task_input.supervisor_request then
        task_context_content = task_context_content .. "TASK QUERY: " .. task_input.supervisor_request .. "\n\n"
    end
    if task_input.expected_outcome_from_supervisor then
        task_context_content = task_context_content .. "EXPECTED OUTCOME: " .. task_input.expected_outcome_from_supervisor .. "\n\n"
    end
    if task_input.supervisor_context then
        task_context_content = task_context_content .. "ADDITIONAL CONTEXT: " .. task_input.supervisor_context .. "\n\n"
    end

    table.insert(commands, {
        type = "CREATE_DATA",
        payload = {
            data_id = uuid.v7(),
            data_type = "context.data",
            content = task_context_content,
            content_type = CONSTANTS.CONTENT_TYPE_TEXT,
            discriminator = CONSTANTS.DISCRIMINATOR,
            key = "task_assignment_details",
            node_id = current_node_id,
            metadata = {
                comment = "Task assignment details from supervisor",
                context_type = "task_assignment",
                task_query = task_input.supervisor_request,
                expected_outcome = task_input.expected_outcome_from_supervisor,
                created_by = "develop_init"
            }
        }
    })

    return {
        initialization_complete = true,
        task_query = task_input.supervisor_request,
        expected_outcome = task_input.expected_outcome_from_supervisor,
        provided_context_loaded = context_items_loaded > 0,
        context_items_count = context_items_loaded,
        context_uuids_received = context_uuids and #context_uuids or 0,
        _control = { commands = commands }
    }
end

return execute