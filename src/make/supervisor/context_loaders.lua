local json = require("json")
local agent_registry = require("agent_registry")
local session_repo = require("session_repo")
local message_repo = require("message_repo")

local loaders = {}

-- Constants
local CONSTANTS = {
    MESSAGE_PREVIEW_LENGTH = 150,
    TOOL_RESULT_PREVIEW_LENGTH = 100,
    RECENT_ITEMS_LIMIT = 10
}

-- Helper: Truncate text
local function truncate_text(text, max_length)
    if not text or type(text) ~= "string" or #text <= max_length then
        return text or ""
    end
    return text:sub(1, max_length) .. "..."
end

--- Loads information about a specific agent by its name (typically the calling agent).
-- @param agent_name The name (meta.name) of the agent to load.
-- @return A table with title, content, and metadata, or nil.
function loaders.load_agent_info(agent_name)
    if not agent_name then return nil end

    -- REMOVED: Skip loading supervisor agent info - we want ALL calling agent info
    -- Load the complete agent specification BY NAME (not ID)
    local agent_spec, agent_err = agent_registry.get_by_name(agent_name)
    if not agent_spec then
        return {
            title = "Calling Agent Error",
            content = "Failed to load calling agent information for name: " .. agent_name ..
                      "\nError: " .. (agent_err or "unknown error"),
            metadata = { type = "calling_agent_error", agent_name = agent_name, error = agent_err }
        }
    end

    -- Build comprehensive agent context including all details
    local content = "Calling Agent Details:\n\n" ..
                   "ID: " .. agent_spec.id .. "\n" ..
                   "Name: " .. (agent_spec.name or "No name specified") .. "\n" ..
                   "Description: " .. (agent_spec.description or "No description provided") .. "\n"

    -- Add comment if available
    if agent_spec.comment and #agent_spec.comment > 0 then
        content = content .. "Comment: " .. agent_spec.comment .. "\n"
    end

    -- Add model information
    if agent_spec.model and #agent_spec.model > 0 then
        content = content .. "Model: " .. agent_spec.model .. "\n"
    end

    content = content .. "\nThis agent invoked the current supervisor task."

    return {
        title = "Calling Agent: " .. (agent_spec.name or agent_id),
        content = content,
        metadata = {
            type = "calling_agent_info",
            agent_id = agent_spec.id,
            name = agent_spec.name,
            description = agent_spec.description,
            comment = agent_spec.comment,
            model = agent_spec.model,
            tools_count = tools_count,
            memory_count = #(agent_spec.memory or {}),
            delegates_count = #(agent_spec.delegates or {}),
            has_complete_spec = true
        }
    }
end

--- Loads agents by class and creates a context summary.
-- @param class_name The class of agents to load.
-- @return A table with title, content, and metadata, or nil.
function loaders.load_agents_by_class(class_name)
    if not class_name or #class_name == 0 then return nil end

    local agents_list, err = agent_registry.list_by_class(class_name)
    if err or not agents_list or #agents_list == 0 then
        return {
            title = "No Agents Available",
            content = "No agents found in class: " .. class_name .. (err and ("\nError: " .. err) or ""),
            metadata = { type = "agents_by_class_error", class_name = class_name, agent_count = 0, error = err }
        }
    end

    local agents_summary_content = "Available Agents in Class: **" .. class_name .. "**\n"
    agents_summary_content = agents_summary_content .. "Total Found: " .. #agents_list .. "\n\n"
    local successfully_loaded_count = 0

    for _, agent_entry in ipairs(agents_list) do
        local agent_spec, spec_err = agent_registry.get_by_id(agent_entry.id)
        if agent_spec then
            -- Only show ID and description
            agents_summary_content = agents_summary_content .. "**" .. agent_spec.id .. "**\n"
            if agent_spec.description and #agent_spec.description > 0 then
                agents_summary_content = agents_summary_content .. "  " .. agent_spec.description .. "\n"
            end
            agents_summary_content = agents_summary_content .. "\n"
            successfully_loaded_count = successfully_loaded_count + 1
        else
            agents_summary_content = agents_summary_content .. "**" .. agent_entry.id .. "** (Error loading details: " .. (spec_err or "unknown") .. ")\n\n"
        end
    end

    return {
        title = "Managed Agents (" .. class_name .. ")",
        content = agents_summary_content,
        metadata = {
            type = "agents_by_class",
            class_name = class_name,
            agent_count = #agents_list,
            successfully_loaded_details = successfully_loaded_count
        }
    }
end

--- Loads current session information.
-- @param session_id The ID of the session.
-- @return A table with title, content, and metadata, or nil.
function loaders.load_session_info(session_id)
    -- Skip session info loading
    return nil
end

--- Loads recent tool usage from messages.
-- @param session_id The ID of the session.
-- @return A table with title, content, and metadata, or nil.
function loaders.load_recent_tool_usage(session_id)
    if not session_id or not message_repo then return nil end

    local function_messages, func_err = message_repo.list_by_type(session_id, "function", CONSTANTS.RECENT_ITEMS_LIMIT, 0)
    if func_err or not function_messages or #function_messages == 0 then
        return nil
    end

    -- Remove the last tool call (current supervisor_init call)
    if #function_messages > 0 then
        table.remove(function_messages, #function_messages)
    end

    if #function_messages == 0 then
        return nil
    end

    local recent_tools_data = {}
    local tools_summary_content = "Recent tool calls in this session:\n\n"

    for i, msg in ipairs(function_messages) do
        if msg.metadata then
            local result_preview_text
            if msg.metadata.result then
                if type(msg.metadata.result) == "string" then
                    result_preview_text = truncate_text(msg.metadata.result, CONSTANTS.TOOL_RESULT_PREVIEW_LENGTH)
                else
                    local encoded_res, enc_err = json.encode(msg.metadata.result)
                    if encoded_res then
                        result_preview_text = truncate_text(encoded_res, CONSTANTS.TOOL_RESULT_PREVIEW_LENGTH)
                    else
                        result_preview_text = "Complex result (encoding failed: " .. (enc_err or "unknown") .. ")"
                    end
                end
            else
                result_preview_text = "No result recorded."
            end

            local tool_call = {
                function_id = msg.metadata.registry_id or msg.metadata.function_name or "Unknown ID",
                function_name = msg.metadata.function_name or "Unknown Name",
                status = msg.metadata.status or "N/A",
                arguments_preview = truncate_text(type(msg.data) == "string" and msg.data or json.encode(msg.data) or "", 100),
                result_preview = result_preview_text
            }
            table.insert(recent_tools_data, tool_call)

            tools_summary_content = tools_summary_content ..
                i .. ". Function: " .. tool_call.function_id .. "\n" ..
                "   Status: " .. tool_call.status .. "\n" ..
                "   Result Preview: " .. tool_call.result_preview .. "\n\n"
        end
    end

    if #recent_tools_data == 0 then return nil end

    return {
        title = "Recent Tool Usage",
        content = tools_summary_content,
        metadata = {
            type = "recent_tool_usage",
            tools_called = recent_tools_data
        }
    }
end

--- Loads recent messages and analyzes for errors.
-- @param session_id The ID of the session.
-- @return An array of context part tables (one for messages, one for errors if any).
function loaders.load_messages_and_error_analysis(session_id)
    if not session_id or not message_repo then return {} end

    local recent_messages_data, msg_err = message_repo.list_by_session(session_id, CONSTANTS.RECENT_ITEMS_LIMIT)
    if msg_err or not recent_messages_data or not recent_messages_data.messages or #recent_messages_data.messages == 0 then
        return {}
    end

    local messages_summary_content = "Recent conversation context:\n\n"
    local errors_summary_content = "Potential errors detected in recent activity:\n\n"
    local error_count = 0
    local detected_errors_data = {}

    for i, msg in ipairs(recent_messages_data.messages) do
        local content_preview = truncate_text(type(msg.data) == "string" and msg.data or json.encode(msg.data) or "", CONSTANTS.MESSAGE_PREVIEW_LENGTH)
        messages_summary_content = messages_summary_content .. i .. ". [" .. msg.type .. "] " .. content_preview .. "\n\n"

        -- Basic Error Detection (can be expanded)
        if msg.type == "function" and msg.metadata then
            local function_name = msg.metadata.registry_id or msg.metadata.function_name or "unknown_function"
            local error_details = nil

            if msg.metadata.status == "error" then
                error_details = type(msg.metadata.result) == "string" and msg.metadata.result or json.encode(msg.metadata.result) or "Unknown error in function result."
            elseif type(msg.metadata.result) == "table" and msg.metadata.result.error then
                error_details = type(msg.metadata.result.error) == "string" and msg.metadata.result.error or json.encode(msg.metadata.result.error)
            elseif type(msg.metadata.result) == "string" and (msg.metadata.result:lower():match("error") or msg.metadata.result:lower():match("failed") or msg.metadata.result:match("FATAL CRASH")) then
                 error_details = msg.metadata.result
            end

            if error_details then
                error_count = error_count + 1
                local error_entry = {
                    source_message_id = msg.message_id,
                    function_name = function_name,
                    details = truncate_text(error_details, 200)
                }
                table.insert(detected_errors_data, error_entry)
                errors_summary_content = errors_summary_content ..
                    error_count .. ". Function: " .. error_entry.function_name .. "\n" ..
                    "   Error: " .. error_entry.details .. "\n\n"
            end
        end
    end

    local context_parts_to_return = {}
    table.insert(context_parts_to_return, {
        title = "Recent Conversation (" .. #recent_messages_data.messages .. " messages)",
        content = messages_summary_content,
        metadata = { type = "recent_messages", message_count = #recent_messages_data.messages }
    })

    if error_count > 0 then
        table.insert(context_parts_to_return, {
            title = "Error Analysis (" .. error_count .. " potential issues found)",
            content = errors_summary_content,
            metadata = { type = "error_analysis", error_count = error_count, errors = detected_errors_data }
        })
    end

    return context_parts_to_return
end

loaders.truncate_text = truncate_text

return loaders