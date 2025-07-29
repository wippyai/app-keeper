local registry = require('registry')
local governance = require('governance_client')

local function handler(params)
    -- Validate required input
    if not params.id then
        return {
            success = false,
            error = 'Missing required parameter: id'
        }
    end

    -- Check if view exists using direct registry get
    local view = registry.get(params.id)
    if not view then
        return {
            success = false,
            error = 'View not found: ' .. params.id
        }
    end

    -- Verify it's a view page
    if not view.meta or view.meta.type ~= 'view.page' then
        return {
            success = false,
            error = 'Invalid view type for ID: ' .. params.id
        }
    end

    -- Create a changeset directly
    local changes = registry.snapshot():changes()

    -- Delete the view
    changes:delete(params.id)

    -- Apply changes through governance client
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
        message = 'View deleted successfully',
        id = params.id,
        version = result.version,
        changeset = result.changeset,
        details = result.details
    }
end

return {
    handler = handler
}