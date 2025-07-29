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

    -- Check for JSON content type
    if not req:is_content_type(http.CONTENT.JSON) then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Request must be application/json"
        })
        return
    end

    -- Parse JSON body
    local data, err = req:body_json()
    if err then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to parse JSON body: " .. err
        })
        return
    end

    -- Validate entry data
    if not data.entry then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing required field: entry"
        })
        return
    end

    local entry = data.entry

    -- Validate required DocScout extraction group fields
    if not entry.id then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing required field: entry.id"
        })
        return
    end

    if not entry.meta or not entry.meta.type or entry.meta.type ~= "docscout.extraction_group" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Invalid entry type: must be docscout.extraction_group"
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

    -- Check if entry already exists
    local existing_entry = snapshot:get(entry.id)
    if existing_entry then
        res:set_status(http.STATUS.CONFLICT)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "DocScout group already exists: " .. entry.id
        })
        return
    end

    -- Extract namespace and name from the entry ID
    local id_parts = {}
    for part in string.gmatch(entry.id, "[^:]+") do
        table.insert(id_parts, part)
    end

    if #id_parts ~= 2 then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Invalid entry ID format. Expected 'namespace:name'"
        })
        return
    end

    local namespace = id_parts[1]
    local name = id_parts[2]

    -- Create a changeset from the snapshot
    local changes = snapshot:changes()

    -- Ensure entry has kind
    entry.kind = "registry.entry"

    -- Ensure meta fields
    if not entry.meta then entry.meta = {} end
    if not entry.meta.title then entry.meta.title = name end
    if not entry.meta.name then entry.meta.name = name end
    if not entry.meta.type then entry.meta.type = "docscout.extraction_group" end

    -- Ensure data object structure exists but don't set any defaults
    if not entry.data then entry.data = {} end
    if not entry.data.fields then entry.data.fields = {} end
    if not entry.data.prefetch then entry.data.prefetch = {} end
    if not entry.data.options then entry.data.options = {} end
    if not entry.data.scouting then entry.data.scouting = {} end
    if not entry.data.extracting then entry.data.extracting = {} end

    -- Create the entry
    local registry_entry = {
        id = { ns = namespace, name = name },
        kind = entry.kind,
        meta = entry.meta,
        data = entry.data
    }

    changes:create(registry_entry)

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
    res:set_status(http.STATUS.CREATED)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = "DocScout group created successfully",
        id = entry.id,
        entry = entry,
        version = version
    })
end

return {
    handler = handler
}