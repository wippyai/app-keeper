local registry = require("registry")
local json = require("json")

-- Agent Lister Tool
-- Lists all agent.gen1 entries in the registry with basic metadata
-- Returns: Single result table with success boolean, agents array, count, and error

local function handler(params)
    -- Initialize response structure following function handler pattern
    local response = {
        success = false,
        agents = {},
        error = nil,
        count = 0
    }

    -- Query registry for agent.gen1 entries using exact matching
    -- Wildcard matching doesn't work properly in the registry system
    local entries, err = registry.find({
        [".kind"] = "registry.entry",
        ["meta.type"] = "agent.gen1"
    })

    if err then
        response.error = "Failed to query registry: " .. tostring(err)
        return response
    end

    -- Handle case where no agents are found
    if not entries or #entries == 0 then
        response.success = true
        response.agents = {}
        response.count = 0
        return response
    end

    -- Process each agent entry
    local agents = {}
    for _, entry in ipairs(entries) do
        -- Extract basic metadata with safe access
        local agent = {
            id = entry.id or "unknown",
            comment = "",
            class = nil
        }

        -- Get comment from metadata if available, handle gracefully
        if entry.meta and entry.meta.comment then
            agent.comment = tostring(entry.meta.comment)
        end

        -- Get class from metadata if available
        if entry.meta and entry.meta.class then
            if type(entry.meta.class) == "string" then
                agent.class = entry.meta.class
            elseif type(entry.meta.class) == "table" and #entry.meta.class > 0 then
                -- If class is an array, use the first class
                agent.class = entry.meta.class[1]
            end
        end

        table.insert(agents, agent)
    end

    -- Sort agents by ID for consistent ordering
    table.sort(agents, function(a, b)
        return a.id < b.id
    end)

    -- Set successful response
    response.success = true
    response.agents = agents
    response.count = #agents

    return response
end

return {
    handler = handler
}