-- Context search tool that auto-detects operation mode
-- @param params Table containing:
--   query (string): specific context search query
--   title (string, optional): short title for the search
--   agent_id (string, optional): specific agent to use for search
--   context_uuids (array, optional): existing context UUIDs to include as references
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
    SEARCH_ARENA = "keeper.make.context:search_arena"
}

-- Implementation
local function execute(params, tool_session_context)
    -- Validate required parameters
    if not params.query then
        return {
            success = false,
            error = "Missing required parameter: query"
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

        -- Prepare input data with optional agent_id and context_uuids
        local input_data = {
            query = params.query,
            agent_id = params.agent_id,
            context_uuids = params.context_uuids
        }
        local content_type = consts.CONTENT_TYPE.JSON

        -- Declare where the workflow will write its final result
        local workflow_output_target = starter.declare_output(
            consts.DATA_TYPE.WORKFLOW_OUTPUT,
            {
                key = "context_result",
                format = "json",
                metadata = {
                    dataflow_id = dataflow_id,
                    search_title = params.title
                }
            }
        )

        -- Metadata consumed by react_node - routes to context search arena
        local input_metadata = {
            arena_id = CONSTANTS.SEARCH_ARENA,
            data_targets = { workflow_output_target },
            target_node_id = dataflow_id,
            session_context = {
                context_query = params.query,
                search_title = params.title or "Context Search",
                query_length = #params.query,
                explicit_agent = params.agent_id,
                provided_context_uuids = params.context_uuids
            }
        }

        -- Execute the workflow using context search arena
        local result = starter.execute(
            "dataflow.runner:node_runner",
            "dataflow.agent:react_node",
            input_data,
            {
                title = params.title or "Context Search",
                session_id = session_id,
                content_type = content_type,
                dataflow_id = dataflow_id,
                input_metadata = input_metadata
            }
        )

        -- Return starter result directly (no wrapping)
        return result
    end

    -- DATAFLOW MODE: Use commands/yields (existing pattern)
    local context_search_node_id = uuid.v7()
    local search_title = params.title or "Context Search"

    -- Prepare input data with optional agent_id and context_uuids
    local input_data = {
        query = params.query,
        agent_id = params.agent_id,
        context_uuids = params.context_uuids
    }

    -- Create commands for context search
    local commands = {
        -- Create context search child node
        {
            type = "CREATE_NODE",
            payload = {
                node_id = context_search_node_id,
                node_type = "dataflow.agent:react_node",
                parent_node_id = current_node_id,
                metadata = {
                    title = search_title,
                    arena_id = CONSTANTS.SEARCH_ARENA,
                    session_context = {
                        target_node_id = current_node_id,
                        discriminator = "group",
                        task_description = "Context search",
                        provided_context_uuids = params.context_uuids
                    }
                }
            }
        },
        -- Create input for context search node
        {
            type = "CREATE_DATA",
            payload = {
                data_type = "node.input",
                node_id = context_search_node_id,
                key = "context_search_query",
                content = input_data,
                content_type = consts.CONTENT_TYPE.JSON,
                metadata = {
                    description = "Context search query",
                    search_title = params.title,
                    source = "context_search",
                    explicit_agent = params.agent_id,
                    provided_context_uuids = params.context_uuids,
                    data_targets = {
                        {
                            type = "react.observation",
                            node_id = current_node_id,
                            key = "context_search_result",
                            format = "text"
                        }
                    }
                }
            }
        }
    }

    -- Return with control directives to yield for search execution
    return {
        success = true,
        query_started = params.query,
        title_used = search_title,
        agent_used = params.agent_id,
        context_uuids_provided = params.context_uuids,
        search_metadata = {
            query = params.query,
            title = params.title,
            agent_id = params.agent_id,
            context_uuids = params.context_uuids,
            search_node_id = context_search_node_id
        },
        _control = {
            commands = commands,
            yield = {
                user_context = {
                    run_node_ids = { context_search_node_id }
                }
            }
        }
    }
end

return execute