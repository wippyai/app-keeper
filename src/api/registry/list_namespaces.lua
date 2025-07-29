local http = require("http")
local json = require("json")
local registry = require("registry")

local function handler()
    -- Get response object
    local res = http.response()
    if not res then
        return nil, "Failed to get HTTP response context"
    end

    -- Get a snapshot of the registry
    local snapshot, err = registry.snapshot()
    if not snapshot then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to get registry snapshot: " .. (err or "unknown error")
        })
        return
    end

    -- Get all entries
    local entries = snapshot:entries()
    
    -- Group entries by namespace and count
    local namespaces = {}
    for _, entry in ipairs(entries) do
        local id_parts = registry.parse_id(entry.id)
        local ns = id_parts.ns
        
        if not namespaces[ns] then
            namespaces[ns] = {
                name = ns,
                count = 0
            }
        end
        
        namespaces[ns].count = namespaces[ns].count + 1
    end
    
    -- Convert namespaces map to array
    local namespaces_array = {}
    for _, ns_data in pairs(namespaces) do
        table.insert(namespaces_array, ns_data)
    end
    
    -- Sort by namespace name
    table.sort(namespaces_array, function(a, b)
        return a.name < b.name
    end)

    -- Return JSON response
    res:set_content_type(http.CONTENT.JSON)
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        count = #namespaces_array,
        namespaces = namespaces_array
    })
end

return {
    handler = handler
}