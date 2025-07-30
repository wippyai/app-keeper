local json = require("json")
local ctx = require("ctx")
local uuid = require("uuid")
local funcs = require("funcs")
local agent_registry = require("agent_registry")

-- Constants
local CONSTANTS = {
    RESEARCH_SUPERVISOR_CLASS = "research_supervisor",
    CONTEXT_SEARCH_CLASS = "context_search",
    CONTENT_TYPE_TEXT = "text/plain",
    TITLE_TRUNCATE_LENGTH = 30,
    AGENT_SELECTOR_FUNC_ID = "wippy.agent.gen1:agent_selector"
}

local function truncate_text(text, max_length)
    if not text or type(text) ~= "string" or #text <= max_length then
        return text or ""
    end
    return text:sub(1, max_length) .. "..."
end

local function load_context_search_agents()
    -- Use agent_registry to find context search agents by class
    local agents_list, err = agent_registry.list_by_class(CONSTANTS.CONTEXT_SEARCH_CLASS)

    if err or not agents_list or #agents_list == 0 then
        return "No context search agents found in class: " .. CONSTANTS.CONTEXT_SEARCH_CLASS ..
               (err and ("\nError: " .. err) or "")
    end

    local agent_info = {}
    table.insert(agent_info, "Available Specialized Context Search Agents:")
    table.insert(agent_info, "Total Found: " .. #agents_list)
    table.insert(agent_info, "")

    for _, agent_entry in ipairs(agents_list) do
        local agent_spec, spec_err = agent_registry.get_by_id(agent_entry.id)
        if agent_spec then
            local agent_title = agent_spec.title or ""
            local agent_description = agent_spec.description or
                                    (agent_spec.meta and agent_spec.meta.comment) or
                                    "No description available"
            local agent_tags = ""

            if agent_spec.meta and agent_spec.meta.tags and type(agent_spec.meta.tags) == "table" then
                agent_tags = " (Tags: " .. table.concat(agent_spec.meta.tags, ", ") .. ")"
            end

            table.insert(agent_info, string.format("**%s** (`%s`)", agent_title, agent_spec.id))
            table.insert(agent_info, string.format("  %s%s", agent_description, agent_tags))
            table.insert(agent_info, "")
        else
            table.insert(agent_info, string.format("**%s** (Error loading details: %s)", agent_entry.id, spec_err or "unknown"))
            table.insert(agent_info, "")
        end
    end

    table.insert(agent_info, "Usage: Use search_context tool with agent_id parameter to specify which specialized agent to use.")
    table.insert(agent_info, "Example: search_context({query: \"...\", title: \"...\", agent_id: \"wippy.keepermake.context.agents:api_interface_search\"})")

    return table.concat(agent_info, "\n")
end

local function execute(input_data, tool_session_context)
    local current_node_id = ctx.get("node_id")
    local dataflow_id = ctx.get("dataflow_id")
    local session_id = ctx.get("session_id")

    -- Determine Research Query
    local research_query = ""
    local research_title = "Research Investigation"
    if type(input_data) == "string" and #input_data > 0 then
        research_query = input_data
        research_title = truncate_text("Research: " .. input_data, CONSTANTS.TITLE_TRUNCATE_LENGTH + 10)
    elseif type(input_data) == "table" then
        research_query = input_data.query or input_data.question or input_data.content or ""
        if type(input_data.query) == "string" and #input_data.query > 5 then
            research_title = truncate_text("Research: " .. input_data.query, CONSTANTS.TITLE_TRUNCATE_LENGTH + 10)
        else
            research_title = input_data.title or research_title
        end
    end

    -- Select the Research Supervisor Agent
    local selected_research_agent_id = nil
    local agent_selection_error = nil

    -- Call the agent selector function
    local agent_selection_result, sel_err = funcs.new():call(CONSTANTS.AGENT_SELECTOR_FUNC_ID, {
        user_prompt = research_query,
        class_name = CONSTANTS.RESEARCH_SUPERVISOR_CLASS
    })

    if sel_err then
        agent_selection_error = "Error calling agent selector: " .. tostring(sel_err)
    elseif agent_selection_result and agent_selection_result.success and agent_selection_result.agent then
        selected_research_agent_id = agent_selection_result.agent
    elseif agent_selection_result and agent_selection_result.error then
        agent_selection_error = "Agent selector failed: " .. tostring(agent_selection_result.error)
    else
        agent_selection_error = "Agent selector did not return a suitable research agent."
    end

    if not selected_research_agent_id then
        error("Failed to select research supervisor agent: " .. (agent_selection_error or "Unknown reason"))
    end

    -- Prepare initial context data
    local commands = {}

    -- Store the research query as initial context
    table.insert(commands, {
        type = "CREATE_DATA",
        payload = {
            data_id = uuid.v7(),
            data_type = "context.data",
            node_id = current_node_id,
            key = "research_query_context",
            content = "Research Query: " .. research_query .. "\n\nThis research investigation should provide comprehensive information to answer the user's question or investigate the specified topic.",
            content_type = CONSTANTS.CONTENT_TYPE_TEXT,
            discriminator = "private",
            metadata = {
                title = "Research Query Context",
                source_type = "research_init",
                loaded_by = "research_init",
                target_research_agent_id = selected_research_agent_id,
                original_query = research_query,
                context_type = "research_query"
            }
        }
    })

    -- Load and store context search agents information
    local context_agents_info = load_context_search_agents()
    table.insert(commands, {
        type = "CREATE_DATA",
        payload = {
            data_id = uuid.v7(),
            data_type = "context.data",
            node_id = current_node_id,
            key = "available_context_search_agents",
            content = context_agents_info,
            content_type = CONSTANTS.CONTENT_TYPE_TEXT,
            discriminator = "private",
            metadata = {
                title = "Available Context Search Agents",
                source_type = "research_init",
                loaded_by = "research_init",
                context_type = "agent_capabilities",
                agent_class = CONSTANTS.CONTEXT_SEARCH_CLASS
            }
        }
    })

    -- Return Control Directives
    local control_block = {
        commands = commands,
        config = {
            agent = selected_research_agent_id
        }
    }

    return {
        initialization_summary = {
            selected_research_agent_id = selected_research_agent_id,
            agent_selection_error = agent_selection_error,
            research_query = research_query,
            research_title = research_title,
            context_agents_loaded = true
        },
        _control = control_block
    }
end

return execute
