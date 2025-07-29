local http = require("http")
local security = require("security")
local session_repo = require("session_repo")
local message_repo = require("message_repo")
local artifact_repo = require("artifact_repo")
local session_contexts_repo = require("session_contexts_repo")
local context_repo = require("context_repo")

local function handler()
    local res = http.response()
    local req = http.request()

    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Security check - ensure user is authenticated
    local actor = security.actor()
    if not actor then
        res:set_status(http.STATUS.UNAUTHORIZED)
        res:write_json({
            success = false,
            error = "Authentication required"
        })
        return
    end

    -- Get session ID from path parameter
    local session_id = req:param("id")
    if not session_id or session_id == "" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:write_json({
            success = false,
            error = "Session ID is required"
        })
        return
    end

    -- Get user ID from the authenticated actor
    local user_id = actor:id()

    -- Retrieve the session
    local session, err = session_repo.get(session_id)
    if err then
        res:set_status(http.STATUS.NOT_FOUND)
        res:write_json({
            success = false,
            error = err
        })
        return
    end

    -- Verify the session belongs to this user (even admins can only see their own sessions)
    if session.user_id ~= user_id then
        res:set_status(http.STATUS.FORBIDDEN)
        res:write_json({
            success = false,
            error = "Access denied: You can only view your own sessions"
        })
        return
    end

    -- Fetch primary context data
    local primary_context = nil
    if session.primary_context_id then
        primary_context, _ = context_repo.get(session.primary_context_id)
    end

    -- Get all messages for the session (no pagination for complete data)
    local messages_result, messages_err = message_repo.list_by_session(session_id)
    if messages_err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            error = "Failed to retrieve session messages: " .. messages_err
        })
        return
    end

    -- Extract messages from result (handle both return formats)
    local messages = messages_result.messages or messages_result

    -- Get all artifacts for the session
    local artifacts_meta, artifacts_err = artifact_repo.list_by_session(session_id)
    if artifacts_err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            error = "Failed to retrieve session artifacts: " .. artifacts_err
        })
        return
    end

    -- Get complete artifact data including content
    local artifacts = {}
    for _, artifact in ipairs(artifacts_meta) do
        -- Get the full artifact with content
        local complete_artifact, _ = artifact_repo.get(artifact.artifact_id)
        if complete_artifact then
            table.insert(artifacts, complete_artifact)
        else
            -- Fallback to metadata-only if full artifact can't be retrieved
            table.insert(artifacts, artifact)
        end
    end

    -- Get all session contexts
    local contexts, contexts_err = session_contexts_repo.list_by_session(session_id)
    if contexts_err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            error = "Failed to retrieve session contexts: " .. contexts_err
        })
        return
    end

    -- Prepare the complete response
    local response = {
        success = true,
        session = session,
        primary_context = primary_context,
        messages = messages,
        artifacts = artifacts,
        contexts = contexts
    }

    -- Calculate accurate statistics
    local stats = {
        message_count = #messages,
        message_counts_by_type = {},
        artifact_count = #artifacts,
        -- Count contexts including primary context if present
        context_count = #contexts + (primary_context and 1 or 0),
        -- Token usage tracking
        token_usage = {
            prompt_tokens = 0,
            completion_tokens = 0,
            thinking_tokens = 0,
            cache_read_tokens = 0,
            cache_write_tokens = 0,
            total_tokens = 0
        }
    }

    -- Count message types and token usage
    for _, message in ipairs(messages) do
        -- Count message types
        local msg_type = message.type or "unknown"
        stats.message_counts_by_type[msg_type] = (stats.message_counts_by_type[msg_type] or 0) + 1

        -- Sum up token usage from assistant messages
        if message.metadata and message.metadata.tokens then
            local tokens = message.metadata.tokens

            if tokens.prompt_tokens then
                stats.token_usage.prompt_tokens = stats.token_usage.prompt_tokens + tokens.prompt_tokens
            end

            if tokens.completion_tokens then
                stats.token_usage.completion_tokens = stats.token_usage.completion_tokens + tokens.completion_tokens
            end

            if tokens.thinking_tokens then
                stats.token_usage.thinking_tokens = stats.token_usage.thinking_tokens + tokens.thinking_tokens
            end

            if tokens.cache_read_tokens then
                stats.token_usage.cache_read_tokens = stats.token_usage.cache_read_tokens + tokens.cache_read_tokens
            end

            if tokens.cache_write_tokens then
                stats.token_usage.cache_write_tokens = stats.token_usage.cache_write_tokens + tokens.cache_write_tokens
            end

            if tokens.total_tokens then
                stats.token_usage.total_tokens = stats.token_usage.total_tokens + tokens.total_tokens
            end
        end
    end

    response.stats = stats

    -- Return JSON response
    res:set_content_type(http.CONTENT.JSON)
    res:set_status(http.STATUS.OK)
    res:write_json(response)
end

return {
    handler = handler
}