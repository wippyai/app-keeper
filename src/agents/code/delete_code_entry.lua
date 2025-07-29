local registry = require('registry')
local governance = require('governance_client')
local code_utils = require('code_utils')

local function handler(params)
    -- Validate required input
    if not params.id then
        return {
            success = false,
            error = 'Missing required parameter: id'
        }
    end

    -- Use code_utils.get_entry to fetch and validate code entry
    local entry, err = code_utils.get_entry(params.id)
    if not entry then
        return {
            success = false,
            error = err or ('Code entry not found: ' .. params.id)
        }
    end

    -- Create a changeset directly
    local changes = registry.snapshot():changes()

    -- Delete the entry
    changes:delete(params.id)

    -- Apply changes through governance client
    local result, err = governance.request_changes(changes)
    if not result then
        return {
            success = false,
            error = 'Failed to delete code entry: ' .. (err or 'unknown error')
        }
    end

    -- Return success response
    return {
        success = true,
        message = 'Code entry deleted successfully',
        id = params.id,
        version = result.version
    }
end

return {
    handler = handler
}
