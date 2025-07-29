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

-- Helper function for deep merge (updates target with source)
local function deep_merge(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            deep_merge(target[key], value)
        elseif value ~= nil then -- Only merge non-nil values from source
            target[key] = value
        end
    end
    return target
end

local function handler(params)
    -- 1. Input Validation
    if not params.id or type(params.id) ~= "string" then
        return { success = false, error = "Missing or invalid required parameter: id (string)" }
    end
    if not params.extracting_updates or type(params.extracting_updates) ~= "table" or next(params.extracting_updates) == nil then
        return { success = false, error = "Missing or invalid required parameter: extracting_updates (non-empty table)" }
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
    updated_entry.data.extracting = updated_entry.data.extracting or {}

    -- Merge the updates
    deep_merge(updated_entry.data.extracting, params.extracting_updates)

    -- Validation after merge: Ensure model is present if extracting section exists
    if next(updated_entry.data.extracting) ~= nil and (not updated_entry.data.extracting.model or updated_entry.data.extracting.model == "") then
        return {
            success = false,
            error =
            "Invalid extracting config after update: 'model' cannot be empty or removed if the extracting section exists."
        }
    end

    -- 4. Apply Changes
    local changes = snapshot:changes()
    -- Use the full structure for update, including the ID object
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
            message = "Extracting config updated successfully, but failed to fetch final state.",
            entry_id = params.id,
            version = result.version,
            changeset = result.changeset,
            details = result.details,
            warning = "Could not fetch updated entry: " .. (err_final_snap or "unknown error")
        }
    end

    return {
        success = true,
        message = "Extracting config updated successfully.",
        entry = final_entry_data, -- Return the full entry fetched after update
        version = result.version,
        details = result.details
    }
end

return { handler = handler }
