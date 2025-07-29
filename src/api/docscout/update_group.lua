local http = require("http")
local json = require("json")
local registry = require("registry")
local governance = require("governance_client")

local function handler()
    local res = http.response()
    local req = http.request()
    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    if not req:is_content_type(http.CONTENT.JSON) then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({ success = false, error = "Request must be application/json" })
        return
    end

    local data, err = req:body_json()
    if err then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({ success = false, error = "Failed to parse JSON body: " .. err })
        return
    end

    if not data.id then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({ success = false, error = "Missing required field in request body: id" })
        return
    end

    if not data.entry then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({ success = false, error = "Missing required field in request body: entry" })
        return
    end

    local entry_id_to_update = data.id
    local provided_entry = data.entry

    if provided_entry.id and provided_entry.id ~= entry_id_to_update then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "ID in request body ('".. entry_id_to_update .."') does not match ID in entry object ('".. provided_entry.id .."')"
        })
        return
    end

    local snapshot, err = registry.snapshot()
    if not snapshot then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({ success = false, error = "Failed to get registry snapshot: " .. (err or "unknown error") })
        return
    end

    local existing_entry = snapshot:get(entry_id_to_update)
    if not existing_entry then
        res:set_status(http.STATUS.NOT_FOUND)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({ success = false, error = "DocScout group not found: " .. entry_id_to_update })
        return
    end

    if existing_entry.meta.type ~= "docscout.extraction_group" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({ success = false, error = "Entry is not a DocScout extraction group: " .. entry_id_to_update })
        return
    end

    local changes = snapshot:changes()

    local updated_entry_payload = {
        id = existing_entry.id,
        kind = existing_entry.kind,
        meta = provided_entry.meta or {},
        data = provided_entry.data or {}
    }

    if type(updated_entry_payload.meta) ~= "table" then updated_entry_payload.meta = {} end
    updated_entry_payload.meta.type = "docscout.extraction_group"

    changes:update(updated_entry_payload)

    -- Use governance client instead of direct apply
    local new_version, apply_err = governance.request_changes(changes)
    if not new_version then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({ success = false, error = "Failed to apply registry changes: " .. (apply_err or "unknown error") })
        return
    end

    local final_snapshot, snapshot_err = registry.snapshot()
    local final_entry
    if not final_snapshot then
        -- Log error internally if possible: log.error("Failed to get final snapshot after update: " .. (snapshot_err or "unknown error"))
        final_entry = updated_entry_payload -- Use payload as fallback
    else
        final_entry = final_snapshot:get(entry_id_to_update)
        if not final_entry then
           -- Log error internally if possible: log.error("Failed to retrieve entry '"..entry_id_to_update.."' from final snapshot")
           final_entry = updated_entry_payload -- Use payload as fallback
        end
    end

    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = "DocScout group updated successfully (full replace)",
        id = entry_id_to_update,
        entry = final_entry,
        version = new_version
    })
end

return {
    handler = handler
}