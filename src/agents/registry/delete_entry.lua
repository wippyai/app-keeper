local json = require('json')
local registry = require('registry')
local governance = require('governance_client')

local function handler(params)
    -- Validate input
    if not params.id then
        return {
            success = false,
            error = 'Missing required parameter: id'
        }
    end

    -- Get a snapshot of the registry
    local snapshot, err = registry.snapshot()
    if not snapshot then
        return {
            success = false,
            error = 'Failed to get registry snapshot: ' .. (err or 'unknown error')
        }
    end

    -- Check if entry exists
    local entry, err = snapshot:get(params.id)
    if not entry then
        return {
            success = false,
            error = 'Entry not found: ' .. params.id
        }
    end

    -- Create a changeset
    local changes = snapshot:changes()

    -- Delete the entry
    changes:delete(params.id)

    -- Apply changes through governance client instead of directly
    local result, err = governance.request_changes(changes)
    if not result then
        return {
            success = false,
            error = 'Failed to apply registry changes: ' .. (err or 'unknown error')
        }
    end

    -- Return success response
    return {
        success = true,
        message = 'Entry deleted successfully',
        id = params.id,
        kind = entry.kind,
        version = result.version,
        details = result.details
    }
end

return {
    handler = handler
}