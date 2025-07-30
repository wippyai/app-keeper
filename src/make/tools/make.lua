-- Generic tool to ask Wippy for help with any task or question
-- @param params Table containing:
--   query (string): clear, specific question or request with context and requirements
--   title (string, optional): short descriptive title for this task (3-5 words)
-- @return Table with:
--   success (boolean)
--   message (string)
--   dataflow_id (string)
--   content (string | table)

-- Imports
local json = require("json")
local ctx = require("ctx")
local uuid = require("uuid")
local starter = require("starter")
local consts = require("consts")

-- Implementation
local function execute(params)
    -- Validate required parameters
    if not params.query then
        return {
            success = false,
            error = "Missing required parameter: query"
        }
    end

    -- Validate query quality
    if type(params.query) ~= "string" or #params.query < 5 then
        return {
            success = false,
            error = "Query must be a clear, specific string with at least 5 characters"
        }
    end

    -- Get context information
    local session_id = ctx.get("session_id") or "unknown"
    local dataflow_id = uuid.v7()
    local input_data = params.query
    local content_type = type(input_data) == "table"
        and consts.CONTENT_TYPE.JSON
        or consts.CONTENT_TYPE.TEXT

    -- Declare where the workflow will write its final result
    local workflow_output_target = starter.declare_output(
        consts.DATA_TYPE.WORKFLOW_OUTPUT,
        {
            key = "final_result",
            format = "json",
            metadata = {
                dataflow_id = dataflow_id
            }
        }
    )

    -- Metadata consumed by react_node - routes to supervisor arena
    local input_metadata = {
        arena_id = "wippy.keeper.make.supervisor:arena",
        data_targets = { workflow_output_target },
        target_node_id = dataflow_id,
        session_context = {
            user_query = params.query,
            query_length = #params.query,
        }
    }

    -- Use provided title or default to "Wippy Assistant"
    local workflow_title = params.title or "Wippy Assistant"

    -- Execute the workflow using supervisor arena
    local result = starter.execute(
        "dataflow.runner:node_runner",
        "dataflow.agent:react_node",
        input_data,
        {
            title = workflow_title,
            session_id = session_id,

            content_type = content_type,
            dataflow_id = dataflow_id,
            input_metadata = input_metadata
        }
    )

    -- Return formatted response
    return {
        success = result.success,
        message = result.success
            and "Wippy assistance completed successfully"
            or (result.error or "Wippy assistance failed"),
        dataflow_id = dataflow_id,
        session_id = session_id,
        content = result.output,
        assistance_completed = result.success,
        request_type = "generic_help",
        query_processed = params.query
    }
end

return execute
