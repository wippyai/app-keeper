local http = require("http")
local json = require("json")
local registry = require("registry")

local function handler()
    -- Get response and request objects
    local res = http.response()
    local req = http.request()
    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Get entry ID from query
    local entry_id = req:query("id")
    if not entry_id or entry_id == "" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing required query parameter: id"
        })
        return
    end

    -- Get the entry directly from registry (no snapshot)
    local entry, err = registry.get(entry_id)
    if not entry then
        res:set_status(http.STATUS.NOT_FOUND)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Entry not found: " .. entry_id
        })
        return
    end

    -- Build a response with detailed entry information
    local result = {
        id = entry.id,
        kind = entry.kind,
        meta = entry.meta or {},
        data = entry.data or {}
    }

    -- Get the current version (still need this for version info)
    local version, err = registry.current_version()
    local version_info = nil
    if version then
        version_info = {
            id = version:id(),
            previous = version:previous() and version:previous():id() or nil,
            string = version:string()
        }
    end

    -- Return success response with complete entry
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        entry = result,
        version = version_info
    })
end

return {
    handler = handler
}