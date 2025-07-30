-- Research investigation tool that auto-detects operation mode
-- @param params Table containing:
--   query (string): clear, specific research question with context and requirements
--   title (string): short title for the research investigation
--   focus_area (string, optional): focus area hint for research
-- @return Table with results (format depends on operation mode)

-- Imports
local json = require("json")
local ctx = require("ctx")
local uuid = require("uuid")
local starter = require("starter")
local consts = require("consts")

-- Constants
local CONSTANTS = {
    CONTENT_TYPE = "text/plain",
    RESEARCH_ARENA = "wippy.keeper.make.research:arena"
}

-- Implementation
local function execute(params)
    -- Validate required parameters
    if not params.query then
        return {
            success = false,
            error = "Missing required parameter: query"
        }
    end

    if not params.title then
        return {
            success = false,
            error = "Missing required parameter: title"
        }
    end

    local current_node_id = ctx.get("node_id")

    -- STANDALONE MODE: Use starter pattern (like make.lua)
    if not current_node_id then
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
                key = "research_result",
                format = "json",
                metadata = {
                    dataflow_id = dataflow_id,
                    research_title = params.title,
                    focus_area = params.focus_area
                }
            }
        )

        -- Metadata consumed by react_node - routes to research arena
        local input_metadata = {
            arena_id = CONSTANTS.RESEARCH_ARENA,
            data_targets = { workflow_output_target },
            target_node_id = dataflow_id,
            session_context = {
                research_query = params.query,
                research_title = params.title,
                focus_area = params.focus_area or "general",
                query_length = #params.query,
            }
        }

        -- Execute the workflow using research arena
        local result = starter.execute(
            "dataflow.runner:node_runner",
            "dataflow.agent:react_node",
            input_data,
            {
                title = params.title,
                session_id = session_id,
                content_type = content_type,
                dataflow_id = dataflow_id,
                input_metadata = input_metadata
            }
        )

        -- Return starter result directly (no wrapping)
        return result
    end

    -- DATAFLOW MODE: Use commands/yields (like search_context)
    local research_node_id = uuid.v7()
    local research_title = params.title
    local focus_area = params.focus_area or "general"

    -- Create commands for research investigation
    local commands = {
        -- Create research child node
        {
            type = "CREATE_NODE",
            payload = {
                node_id = research_node_id,
                node_type = "dataflow.agent:react_node",
                parent_node_id = current_node_id,
                metadata = {
                    title = research_title,
                    arena_id = CONSTANTS.RESEARCH_ARENA,
                    session_context = {
                        target_node_id = current_node_id,
                        discriminator = "private",
                        task_description = "Research investigation: " .. params.query
                    }
                }
            }
        },
        -- Create input for research node
        {
            type = "CREATE_DATA",
            payload = {
                data_type = "node.input",
                node_id = research_node_id,
                key = "research_query",
                content = params.query,
                content_type = CONSTANTS.CONTENT_TYPE,
                metadata = {
                    description = "Research query",
                    research_title = params.title,
                    focus_area = focus_area,
                    source = "research_investigation",
                    data_targets = {
                        {
                            type = "react.observation",
                            node_id = current_node_id,
                            key = "research_result",
                            format = "text"
                        }
                    }
                }
            }
        }
    }

    -- Return with control directives to yield for research execution
    return {
        success = true,
        research_query = params.query,
        title_used = research_title,
        focus_area = focus_area,
        research_metadata = {
            query = params.query,
            title = params.title,
            focus_area = focus_area,
            research_node_id = research_node_id
        },
        _control = {
            commands = commands,
            yield = {
                user_context = {
                    run_node_ids = { research_node_id },
                    research_in_progress = true,
                    research_focus = focus_area
                }
            }
        }
    }
end

return execute
