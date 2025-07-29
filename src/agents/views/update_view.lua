local registry = require('registry')
local security = require('security')
local governance = require('governance_client')

local function handler(params)
    -- Validate required input
    if not params.id then
        return {
            success = false,
            error = 'Missing required parameter: id'
        }
    end

    -- Get the view from registry directly
    local view, err = registry.get(params.id)
    if not view then
        return {
            success = false,
            error = 'View not found: ' .. (err or 'unknown error')
        }
    end

    -- Verify it's a view page
    if not view.meta or view.meta.type ~= 'view.page' then
        return {
            success = false,
            error = 'Invalid view type for ID: ' .. params.id
        }
    end

    -- Tracking if anything is actually being updated
    local has_updates = false

    -- Create updated meta table based on existing values
    local updated_meta = {}
    for k, v in pairs(view.meta) do
        updated_meta[k] = v
    end

    -- Create updated data table based on existing values
    local updated_data = {}
    for k, v in pairs(view.data) do
        updated_data[k] = v
    end

    -- Process metadata updates if provided
    if params.title then
        updated_meta.title = params.title
        has_updates = true
    end

    if params.description then
        updated_meta.description = params.description
        has_updates = true
    end

    if params.icon then
        updated_meta.icon = params.icon
        has_updates = true
    end

    if params.order then
        updated_meta.order = params.order
        has_updates = true
    end

    if params.secure ~= nil then -- Using ~= nil to handle boolean false
        updated_meta.secure = params.secure
        has_updates = true
    end

    if params.public ~= nil then -- Using ~= nil to handle boolean false
        updated_meta.public = params.public
        has_updates = true
    end

    if params.announced ~= nil then -- Using ~= nil to handle boolean false
        updated_meta.announced = params.announced
        has_updates = true
    end

    if params.inline ~= nil then -- Using ~= nil to handle boolean false
        updated_meta.inline = params.inline
        has_updates = true
    end

    if params.group then
        updated_meta.group = params.group
        has_updates = true
    end

    if params.group_icon then
        updated_meta.group_icon = params.group_icon
        has_updates = true
    end

    if params.group_order then
        updated_meta.group_order = params.group_order
        has_updates = true
    end

    if params.content_type then
        updated_meta.content_type = params.content_type
        has_updates = true
    end

    -- Process data updates if provided
    if params.content then
        updated_data.source = params.content
        has_updates = true
    end

    if params.template_set then
        updated_data.set = params.template_set
        has_updates = true
    end

    if params.data_func then
        -- Validate data_func exists if provided
        if params.data_func ~= '' then
            local func_entry, func_err = registry.get(params.data_func)
            if not func_entry then
                return {
                    success = false,
                    error = 'Data function \'' .. params.data_func .. '\' not found: ' .. (func_err or 'unknown error')
                }
            end

            -- Verify it's a function entry
            if func_entry.kind ~= 'function.lua' then
                return {
                    success = false,
                    error = '\'' .. params.data_func .. '\' is not a valid function'
                }
            end
        end

        updated_data.data_func = params.data_func
        has_updates = true
    end

    -- Update resources if provided
    if params.resources then
        -- Validate all resources exist
        for _, resource_id in ipairs(params.resources) do
            local resource, resource_err = registry.get(resource_id)
            if not resource then
                return {
                    success = false,
                    error = 'Resource \'' .. resource_id .. '\' not found: ' .. (resource_err or 'unknown error')
                }
            end

            -- Verify it's a resource
            if not resource.meta or resource.meta.type ~= 'view.resource' then
                return {
                    success = false,
                    error = '\'' .. resource_id .. '\' is not a valid view resource'
                }
            end
        end

        updated_data.resources = params.resources
        has_updates = true
    end

    -- Check if there are any updates to apply
    if not has_updates then
        return {
            success = false,
            error = 'No updates provided'
        }
    end

    -- Create a changeset directly
    local changes = registry.snapshot():changes()

    -- Update the view
    changes:update({
        id = view.id,
        kind = view.kind,
        meta = updated_meta,
        data = updated_data
    })

    -- Apply changes through governance client
    local result, err = governance.request_changes(changes)
    if not result then
        return {
            success = false,
            error = 'Failed to apply registry changes: ' .. (err or 'unknown error')
        }
    end

    -- Return success response with updated details
    return {
        success = true,
        message = 'View updated successfully',
        view = {
            id = view.id,
            title = updated_meta.title,
            version = result.version
        }
    }
end

return {
    handler = handler
}