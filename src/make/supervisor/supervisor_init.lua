local json          = require("json")
local ctx           = require("ctx")
local uuid          = require("uuid")
local funcs         = require("funcs")
local context_load  = require("context_loaders")

-- Constants
local CONSTANTS     = {
    SUPERVISOR_AGENT_CLASS        = "supervisor",
    MANAGED_AGENTS_CLASS          = "developer_assistant",
    CONTENT_TYPE_TEXT             = "text/plain",

    -- Discriminators
    CONTEXT_DISCRIMINATOR_PRIVATE = "private", -- supervisor‑only
    CONTEXT_DISCRIMINATOR_GROUP   = "group",   -- for shared inputs only

    CONTEXT_SEARCH_ARENA_ID       = "wippy.keeper.make.context:search_arena",
    TITLE_TRUNCATE_LENGTH         = 20,
    AGENT_SELECTOR_FUNC_ID        = "wippy.agent.gen1:agent_selector"
}

-- Feature flags (may be overridden from input options)
local FEATURE_FLAGS = {
    ENABLE_AUTOMATIC_CONTEXT_SEARCH = false,
    ENABLE_MESSAGE_DETAILS_LOADING  = false
}

local function truncate(text, max)
    if not text or #text <= max then return text or "" end
    return text:sub(1, max) .. "..."
end

---@param input any
local function execute(input)
    ---------------------------------------------------------------------
    -- Local helpers / ambient values
    ---------------------------------------------------------------------
    local node_id      = ctx.get("node_id")
    local dataflow_id  = ctx.get("dataflow_id")
    local session_id   = ctx.get("session_id")
    local caller_agent = ctx.get("previous_agent_name")

    -- Normalize input table
    local parsed, opts = {}, {}
    if type(input) == "string" then
        parsed.task_description = input
    elseif type(input) == "table" then
        parsed, opts = input, input.options or {}
    end

    ---------------------------------------------------------------------
    -- Effective feature flags
    ---------------------------------------------------------------------
    local enable_search     = opts.enable_context_search ~= nil and opts.enable_context_search or
        FEATURE_FLAGS.ENABLE_AUTOMATIC_CONTEXT_SEARCH
    local enable_details    = opts.enable_message_details ~= nil and opts.enable_message_details or
        FEATURE_FLAGS.ENABLE_MESSAGE_DETAILS_LOADING

    local query             = parsed.task_description or parsed.query or parsed.content or ""
    local title             = parsed.title or
        truncate("Supervising: " .. (parsed.task_description or "task"), CONSTANTS.TITLE_TRUNCATE_LENGTH + 13)

    ---------------------------------------------------------------------
    -- 1. Choose supervisor agent
    ---------------------------------------------------------------------
    local agent_id, sel_err = nil, nil
    local sel_res, err      = funcs.new():call(CONSTANTS.AGENT_SELECTOR_FUNC_ID, {
        user_prompt = query,
        class_name  = CONSTANTS.SUPERVISOR_AGENT_CLASS
    })
    if err then
        sel_err = "selector call failed: " .. err
    elseif sel_res and sel_res.success then
        agent_id = sel_res.agent
    else
        sel_err = sel_res and sel_res.error or "unexpected selector result"
    end
    if not agent_id then error("Supervisor selection failed: " .. (sel_err or "unknown")) end

    ---------------------------------------------------------------------
    -- 2. Build commands array
    ---------------------------------------------------------------------
    local commands, ctx_meta = {}, {}
    local function add_ctx(item, prefix)
        if item and item.content then
            local key = prefix .. "_" .. (item.metadata.type or "generic")
            table.insert(commands, {
                type    = "CREATE_DATA",
                payload = {
                    data_type     = "context.data",
                    node_id       = node_id,
                    dataflow_id   = dataflow_id,
                    key           = key,
                    content       = item.content,
                    content_type  = CONSTANTS.CONTENT_TYPE_TEXT,
                    discriminator = CONSTANTS.CONTEXT_DISCRIMINATOR_PRIVATE,
                    metadata      = {
                        title        = item.title,
                        source_type  = item.metadata.type,
                        loaded_by    = "supervisor_init",
                        target_agent = agent_id
                    }
                }
            })
            table.insert(ctx_meta, { key = key, title = item.title, type = item.metadata.type })
        end
    end

    if caller_agent then add_ctx(context_load.load_agent_info(caller_agent), "invoking_agent") end
    add_ctx(context_load.load_agents_by_class(CONSTANTS.MANAGED_AGENTS_CLASS), "managed_agents")
    if session_id then
        add_ctx(context_load.load_session_info(session_id), "session")
        add_ctx(context_load.load_recent_tool_usage(session_id), "session_tools")
        if enable_details then
            for _, m in ipairs(context_load.load_messages_and_error_analysis(session_id)) do
                add_ctx(m, "session_activity")
            end
        end
    end

    ---------------------------------------------------------------------
    -- 3. Optional context search child (input = group, output = private)
    ---------------------------------------------------------------------
    local search_node_id = nil
    if enable_search then
        search_node_id = uuid.v7()
        -- child node
        table.insert(commands, {
            type = "CREATE_NODE",
            payload = {
                node_id        = search_node_id,
                node_type      = "dataflow.agent:react_node",
                parent_node_id = node_id,
                dataflow_id    = dataflow_id,
                status         = "pending",
                metadata       = {
                    title             = "Context Search",
                    arena_id          = CONSTANTS.CONTEXT_SEARCH_ARENA_ID,
                    task_description  = "Initial context gathering for supervisor task: " .. query,
                    target_supervisor = agent_id
                }
            }
        })
        -- search query input (shared)
        table.insert(commands, {
            type = "CREATE_DATA",
            payload = {
                data_type    = "node.input",
                node_id      = search_node_id,
                dataflow_id  = dataflow_id,
                key          = "initial_search_query",
                content      = query,
                content_type = CONSTANTS.CONTENT_TYPE_TEXT,
                metadata     = {
                    description = "Search seed for dynamic context gathering",
                    data_targets = {
                        {
                            type          = "context.data",
                            node_id       = node_id,
                            key           = "supervisor_initial_dynamic_context",
                            format        = CONSTANTS.CONTENT_TYPE_TEXT,
                            discriminator = CONSTANTS.CONTEXT_DISCRIMINATOR_PRIVATE
                        },
                    }
                }
            }
        })
    end

    ---------------------------------------------------------------------
    -- 4. _control block
    ---------------------------------------------------------------------
    local ctrl = {
        commands = commands,
        config   = { agent = agent_id }
    }
    if search_node_id then
        ctrl.yield = { user_context = { run_node_ids = { search_node_id } } }
    end

    ---------------------------------------------------------------------
    -- 5. RETURN ORIGINAL INPUT SO AGENT CAN SEE IT
    ---------------------------------------------------------------------
    return {
        initialization_summary = {
            supervisor_agent           = agent_id,
            supervisor_selection_error = sel_err,
            dynamic_search_node        = search_node_id,
            context_parts_queued       = #ctx_meta,
            feature_flags_applied      = {
                context_search_enabled  = enable_search,
                message_details_enabled = enable_details
            }
        },
        _control = ctrl,
        input = input
    }
end

return execute
