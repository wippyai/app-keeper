local http = require("http")
local json = require("json")
local security = require("security")
local status = require("status")
local env = require("env")
local start_tokens = require("start_tokens")

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
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Authentication required"
        })
        return
    end

    -- Get repository status
    local repo_status, err = status.get_full_status()
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to get repository status: " .. err
        })
        return
    end

    -- Get change counts
    local change_counts, err = status.count_changes()
    if err then
        -- Continue with partial data
        change_counts = {
            staged = 0,
            unstaged = 0,
            untracked = 0,
            is_clean = true
        }
    end

    -- Generate start token for Git agent
    local token_params = {
        agent = "wippy.git", -- Git agent name
        model = "gpt-4o",  -- Default model
        kind = "default"   -- Default session kind
    }

    local git_agent_token, token_err = start_tokens.pack(token_params)
    if not git_agent_token then
        -- Log error but continue without token
        print("Failed to generate start token for Git agent: " .. (token_err or "unknown error"))
        git_agent_token = nil
    end

    -- Return response
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        status = repo_status,
        counts = change_counts,
        git_agent_token = git_agent_token -- Add Git agent token to response
    })
end

return {
    handler = handler
}