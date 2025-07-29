local json = require("json")
local registry = require("registry")
local governance = require("governance_client")

local function handler(params)
    -- Validate required inputs
    if not params.namespace then
        return {
            success = false,
            error = "Missing required parameter: namespace"
        }
    end

    if not params.name then
        return {
            success = false,
            error = "Missing required parameter: name"
        }
    end

    if not params.kind then
        return {
            success = false,
            error = "Missing required parameter: kind"
        }
    end

    -- Prepare metadata and data objects
    local meta = params.meta or {}
    local data = params.data or {}

    -- Get the current snapshot
    local snapshot, err = registry.snapshot()
    if not snapshot then
        return {
            success = false,
            error = "Failed to get registry snapshot: " .. (err or "unknown error")
        }
    end

    -- Check if entry already exists
    local entry_id = params.namespace .. ":" .. params.name
    local existing_entry = snapshot:get(entry_id)
    if existing_entry then
        return {
            success = false,
            error = "Entry already exists: " .. entry_id
        }
    end

    -- Create a changeset from the snapshot
    local changes = snapshot:changes()

    -- Create the new entry in the registry
    changes:create({
        id = { ns = params.namespace, name = params.name },
        kind = params.kind,
        meta = meta,
        data = data
    })

    -- Apply changes through governance client instead of directly
    local result, err = governance.request_changes(changes)
    if not result then
        return {
            success = false,
            error = "Failed to apply registry changes: " .. (err or "unknown error")
        }
    end

    -- Return success response with entry details and the complete result
    return {
        success = true,
        message = "Entry created successfully",
        entry = {
            id = entry_id,
            namespace = params.namespace,
            name = params.name,
            kind = params.kind
        },
        version = result.version,
        details = result.details
    }
end

return {
    handler = handler
}