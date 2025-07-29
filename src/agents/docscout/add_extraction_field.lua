local registry = require("registry")
local json = require("json")
local governance = require("governance_client")

-- Helper function for deep copy
local function deep_copy(original)
    local copy
    if type(original) == "table" then
        copy = {}
        for key, value in pairs(original) do
            copy[key] = deep_copy(value)
        end
    else
        copy = original
    end
    return copy
end

local function handler(params)
    -- 1. Input Validation
    if not params.id or type(params.id) ~= "string" then
        return { success = false, error = "Missing or invalid required parameter: id (string)" }
    end
    if not params.field_name or type(params.field_name) ~= "string" or params.field_name == "" then
        return { success = false, error = "Missing or invalid required parameter: field_name (string)" }
    end
    if not params.field_config or type(params.field_config) ~= "table" then
        return { success = false, error = "Missing or invalid required parameter: field_config (table)" }
    end
    -- Validate required sub-fields in field_config
    if not params.field_config.description or type(params.field_config.description) ~= "string" then
        return { success = false, error =
        "Invalid field_config: Missing or invalid required property 'description' (string)" }
    end
    if not params.field_config.type or type(params.field_config.type) ~= "string" then
        return { success = false, error = "Invalid field_config: Missing or invalid required property 'type' (string)" }
    end
    if params.field_config.type == "enum" and (not params.field_config.enum_values or type(params.field_config.enum_values) ~= "table") then
        return { success = false, error =
        "Invalid field_config: Field type is 'enum' but 'enum_values' array is missing or invalid." }
    end

    -- 2. Registry Interaction - Get Entry
    local snapshot, err_snap = registry.snapshot()
    if not snapshot then
        return { success = false, error = "Failed to get registry snapshot: " .. (err_snap or "unknown error") }
    end

    local entry, err_get = snapshot:get(params.id)
    if not entry then
        return { success = false, error = "Extraction group entry not found: " .. params.id }
    end
    if entry.kind ~= "registry.entry" or not entry.meta or entry.meta.type ~= "docscout.extraction_group" then
        return { success = false, error = "Entry is not a valid DocScout extraction group: " .. params.id }
    end

    -- 3. Modify Data In Memory
    local updated_entry = deep_copy(entry)
    updated_entry.data = updated_entry.data or {}
    updated_entry.data.fields = updated_entry.data.fields or {}

    -- Check if field already exists
    if updated_entry.data.fields[params.field_name] then
        return { success = false, error = "Field '" .. params.field_name .. "' already exists in this extraction group." }
    end

    -- Add the new field
    updated_entry.data.fields[params.field_name] = params.field_config

    -- 4. Apply Changes
    local changes = snapshot:changes()
    changes:update({
        id = entry.id,
        kind = updated_entry.kind,
        meta = updated_entry.meta,
        data = updated_entry.data
    })

    -- Use governance client instead of direct apply
    local result, err_apply = governance.request_changes(changes)
    if not result then
        return { success = false, error = "Failed to apply registry changes: " .. (err_apply or "unknown error") }
    end

    -- 5. Fetch and Return Updated Entry
    local final_snapshot, err_final_snap = registry.snapshot(result.version)
    local final_entry_data = final_snapshot and final_snapshot:get(params.id)

    if not final_entry_data then
        return {
            success = true,
            message = "Field added successfully, but failed to fetch final state.",
            entry_id = params.id,
            version = result.version,
            details = result.details,
            warning = "Could not fetch updated entry: " .. (err_final_snap or "unknown error")
        }
    end

    return {
        success = true,
        message = "Field '" .. params.field_name .. "' added successfully.",
        entry = final_entry_data,
        version = result.version,
        details = result.details
    }
end

return { handler = handler }