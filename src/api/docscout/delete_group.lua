local http = require("http")
local json = require("json")
local registry = require("registry")
local governance = require("governance_client")

local function handler()
    -- Get response and request objects
    local res = http.response()
    local req = http.request()
    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Get group ID from query
    local group_id = req:query("id")
    if not group_id or group_id == "" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing required query parameter: id"
        })
        return
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

    -- Check if entry exists
    local entry, err = snapshot:get(group_id)
    if not entry then
        res:set_status(http.STATUS.NOT_FOUND)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "DocScout group not found: " .. group_id
        })
        return
    end

    -- Validate it's a DocScout extraction group
    if entry.meta.type ~= "docscout.extraction_group" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Entry is not a DocScout extraction group: " .. group_id
        })
        return
    end

    -- Create a changeset
    local changes = snapshot:changes()

    -- Delete the entry
    changes:delete(group_id)

    -- Apply changes using governance client
    local version, err = governance.request_changes(changes)
    if not version then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to apply registry changes: " .. (err or "unknown error")
        })
        return
    end

    -- Return success response
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = "DocScout group deleted successfully",
        id = group_id,
        version = version
    })
end

return {
    handler = handler
}