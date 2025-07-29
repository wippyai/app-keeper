local registry = require("registry")
local json     = require("json")
local governance = require("governance_client")

-- Helper for deep‐copy
local function deep_copy(orig)
    if type(orig) ~= "table" then return orig end
    local c = {}
    for k,v in pairs(orig) do c[k] = deep_copy(v) end
    return c
end

local function handler(params)
    -- 1. Validate inputs
    if type(params.id) ~= "string" or params.id == "" then
        return { success = false, error = "Missing or invalid required parameter: id (string)" }
    end
    if type(params.field_name) ~= "string" or params.field_name == "" then
        return { success = false, error = "Missing or invalid required parameter: field_name (string)" }
    end

    -- 2. Load registry snapshot and entry
    local snap, err_snap = registry.snapshot()
    if not snap then
        return { success = false, error = "Failed to get registry snapshot: " .. tostring(err_snap) }
    end

    local entry = snap:get(params.id)
    if not entry then
        return { success = false, error = "Extraction group entry not found: " .. params.id }
    end
    if entry.kind ~= "registry.entry"
       or not entry.meta
       or entry.meta.type ~= "docscout.extraction_group" then
        return { success = false, error = "Entry is not a valid DocScout extraction group: " .. params.id }
    end

    -- 3. Remove the field in-memory
    local updated = deep_copy(entry)
    updated.data = updated.data or {}
    updated.data.fields = updated.data.fields or {}

    if not updated.data.fields[params.field_name] then
        return { success = false, error = "Field '" .. params.field_name .. "' not found in this extraction group." }
    end

    updated.data.fields[params.field_name] = nil

    -- 4. Apply changes to registry
    local changes = snap:changes()
    changes:update({
        id   = { ns = registry.parse_id(params.id).ns, name = registry.parse_id(params.id).name },
        kind = entry.kind,
        meta = entry.meta,
        data = updated.data
    })

    -- Use governance client instead of direct apply
    local result, err_apply = governance.request_changes(changes)
    if not result then
        return { success = false, error = "Failed to apply registry changes: " .. tostring(err_apply) }
    end

    -- 5. Return the updated entry
    local final_snap, err_final = registry.snapshot(result.version)
    local final_entry = final_snap and final_snap:get(params.id)

    if not final_entry then
        return {
            success  = true,
            message  = "Field removed, but failed to fetch updated entry.",
            entry_id = params.id,
            version  = result.version,
            changeset = result.changeset,
            details = result.details,
            warning  = "Could not fetch updated entry: " .. tostring(err_final)
        }
    end

    return {
        success = true,
        message = "Field '" .. params.field_name .. "' removed successfully.",
        entry   = final_entry,
        version = result.version,
        details = result.details
    }
end

return { handler = handler }