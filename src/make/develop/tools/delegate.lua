local json = require("json")
local ctx = require("ctx")
local uuid = require("uuid")
local consts = require("consts")

local DEVELOPER_ASSISTANT_ARENA_ID = "wippy.keeper.make.develop:arena"

local function generate_fallback_title(agent_id)
    if agent_id:find("coder_assistant") then
        return "Code Task"
    elseif agent_id:find("views_assistant") then
        return "UI Task"
    elseif agent_id:find("registry_assistant") then
        return "Registry Task"
    else
        return "Dev Task"
    end
end

local function execute(params)
    if not params.agent_id or type(params.agent_id) ~= "string" or #params.agent_id == 0 then
        return { success = false, error = "Missing or invalid 'agent_id' parameter." }
    end
    if not params.task_query or type(params.task_query) ~= "string" or #params.task_query == 0 then
        return { success = false, error = "Missing or invalid 'task_query' parameter." }
    end
    if not params.expected_outcome_description or type(params.expected_outcome_description) ~= "string" or #params.expected_outcome_description == 0 then
        return { success = false, error = "Missing or invalid 'expected_outcome_description' parameter." }
    end

    local supervisor_node_id = ctx.get("node_id") or "supervisor_node_unknown"
    local supervisor_dataflow_id = ctx.get("dataflow_id") or "supervisor_dataflow_unknown"
    local delegated_task_node_id = uuid.v7()

    local task_input_content = {
        supervisor_request = params.task_query,
        supervisor_context = params.context_data,
        expected_outcome_from_supervisor = params.expected_outcome_description,
        context_uuids = params.context_uuids  -- Pass context UUIDs to the assistant
    }
    local task_input_json, err_encode_input = json.encode(task_input_content)
    if err_encode_input then
        return { success = false, error = "Failed to encode task input to JSON: " .. err_encode_input }
    end
    if not task_input_json then
        return { success = false, error = "Failed to encode task input to JSON (nil result)." }
    end

    local delegated_agent_output_key = "delegated_result_" .. params.agent_id:gsub("[^%w_]", "_") .. "_" .. delegated_task_node_id:sub(1,8)

    local short_title = params.title or generate_fallback_title(params.agent_id)

    local commands = {}

    table.insert(commands, {
        type = "CREATE_NODE",
        payload = {
            node_id = delegated_task_node_id,
            node_type = "dataflow.agent:react_node",
            parent_node_id = supervisor_node_id,
            dataflow_id = supervisor_dataflow_id,
            status = "pending",
            metadata = {
                title = short_title,
                arena_id = DEVELOPER_ASSISTANT_ARENA_ID,
                agent_id = params.agent_id,
                task_description = params.task_query,
                delegated_by_node = supervisor_node_id,
                context_uuids_provided = params.context_uuids and #params.context_uuids or 0
            }
        }
    })

    table.insert(commands, {
        type = "CREATE_DATA",
        payload = {
            data_type = consts.DATA_TYPE.NODE_INPUT,
            node_id = delegated_task_node_id,
            dataflow_id = supervisor_dataflow_id,
            key = "delegated_task_input",
            content = task_input_json,
            content_type = consts.CONTENT_TYPE.JSON,
            metadata = {
                description = "Input for delegated task to agent: " .. params.agent_id,
                source_node_id = supervisor_node_id,
                context_uuids_shared = params.context_uuids,
                data_targets = {
                    {
                        type = "react.observation",
                        node_id = supervisor_node_id,
                        key = delegated_agent_output_key,
                        format = "json",
                        discriminator = consts.CONTEXT_DISCRIMINATOR.PRIVATE
                    }
                }
            }
        }
    })

    return {
        _control = {
            commands = commands,
            yield = {
                user_context = {
                    run_node_ids = { delegated_task_node_id },
                    waiting_for_delegated_task = true,
                    delegated_agent_id = params.agent_id,
                    delegated_node_id = delegated_task_node_id,
                    delegated_output_key = delegated_agent_output_key,
                    task_description_for_wait = params.task_query:sub(1,100),
                    context_uuids_shared = params.context_uuids and #params.context_uuids or 0
                }
            }
        },
        tool_result_summary = "Delegation initiated for agent '" .. params.agent_id .. "' to perform task: '" .. params.task_query:sub(1, 100) .. "...'. " ..
                             (params.context_uuids and #params.context_uuids > 0 and ("Shared " .. #params.context_uuids .. " context items. ") or "") ..
                             "Waiting for completion. Output will be available under key: " .. delegated_agent_output_key,
        delegation_details = {
            agent_id = params.agent_id,
            delegated_node_id = delegated_task_node_id,
            output_will_be_in_context_key = delegated_agent_output_key,
            context_uuids_shared = params.context_uuids and #params.context_uuids or 0
        }
    }
end

return execute
