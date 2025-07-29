-- Function to generate a start token for a specific agent
local http = require("http")
local json = require("json")
local registry = require("registry")
local security = require("security")
local start_tokens = require("start_tokens")

local function handler()
    local res = http.response()
    local req = http.request()
    if not res or not req then
        -- This error is internal and shouldn't typically reach the user
        return nil, "Failed to get HTTP context"
    end

    -- Security check: Ensure user is authenticated
    local actor = security.actor()
    if not actor then
        res:set_status(http.STATUS.UNAUTHORIZED)
        res:write_json({ success = false, error = "Authentication required" })
        return
    end

    -- Get agent name/ID from path parameter 'id' or query parameter 'agent'
    local agent_name = req:param("id") or req:query("agent")
    if not agent_name or agent_name == "" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:write_json({ success = false, error = "Agent name/ID is required (use path param 'id' or query param 'agent')" })
        return
    end

    -- Find the agent entry in the registry by its meta.name
    -- This searches across namespaces for agent definitions
    local agent_entries, find_err = registry.find({
        [".kind"] = "registry.entry",
        ["meta.type"] = "agent.gen1",
        ["meta.name"] = agent_name
    })

    if find_err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({ success = false, error = "Error searching for agent: " .. find_err })
        return
    end

    if not agent_entries or #agent_entries == 0 then
        res:set_status(http.STATUS.NOT_FOUND)
        res:write_json({ success = false, error = "Agent not found: " .. agent_name })
        return
    end

    -- Use the first found agent entry (names should ideally be unique)
    local entry = agent_entries[1]
    if not entry.meta then
         res:set_status(http.STATUS.INTERNAL_ERROR)
         res:write_json({ success = false, error = "Agent entry is missing metadata: " .. agent_name })
         return
    end

    -- Determine model and kind: Use query params > agent meta > defaults
    local model = req:query("model") or entry.meta.model or entry.data.model or "gpt-4o"
    local kind = req:query("kind") or entry.meta.session_kind or "default"

    -- Prepare parameters for the start token
    local token_params = {
        agent = agent_name, -- Use the requested name
        model = model,
        kind = kind
        -- Add other parameters if needed in the future (e.g., start_func)
    }

    -- Generate the start token
    local token, token_err = start_tokens.pack(token_params)
    if not token then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({ success = false, error = "Failed to generate start token: " .. (token_err or "unknown error") })
        return
    end

    -- Return the start token successfully
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({ success = true, start_token = token })
end

return {
    handler = handler
}