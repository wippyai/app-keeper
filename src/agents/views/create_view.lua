local registry = require('registry')
local security = require('security')
local governance = require('governance_client')

local function handler(params)
    -- Validate required inputs
    if not params.name then
        return { success = false, error = 'Missing required parameter: name' }
    end

    if not params.namespace then
        return { success = false, error = 'Missing required parameter: namespace' }
    end

    if not params.title then
        return { success = false, error = 'Missing required parameter: title' }
    end

    if not params.content then
        return { success = false, error = 'Missing required parameter: content' }
    end

    if not params.template_set then
        return { success = false, error = 'Missing required parameter: template_set' }
    end

    -- Check if view with this name already exists using direct registry find
    local existing_views = registry.find({
        ['.kind'] = 'template.jet',
        ['meta.name'] = params.name,
        ['.ns'] = params.namespace
    })

    if existing_views and #existing_views > 0 then
        return {
            success = false,
            error = 'A view with name \'' .. params.name .. '\' already exists in namespace \'' .. params.namespace .. '\''
        }
    end

    -- Validate data_func if provided
    if params.data_func and params.data_func ~= '' then
        local func_entry = registry.get(params.data_func)
        if not func_entry then
            return { success = false, error = 'Data function \'' .. params.data_func .. '\' not found' }
        end

        if func_entry.kind ~= 'function.lua' then
            return { success = false, error = '\'' .. params.data_func .. '\' is not a valid function entry' }
        end
    end

    -- Validate resources if provided
    local resources = {}
    if params.resources and #params.resources > 0 then
        for i, resource_id in ipairs(params.resources) do
            local resource_entry = registry.get(resource_id)
            if not resource_entry then
                return { success = false, error = 'Resource \'' .. resource_id .. '\' not found' }
            end

            if not resource_entry.meta or resource_entry.meta.type ~= 'view.resource' then
                return { success = false, error = '\'' .. resource_id .. '\' is not a valid view resource' }
            end

            resources[i] = resource_id
        end
    end

    -- Create changeset directly
    local changes = registry.snapshot():changes()

    -- Create view entry
    changes:create({
        id = { ns = params.namespace, name = params.name },
        kind = 'template.jet',
        meta = {
            type = 'view.page',
            name = params.name,
            title = params.title,
            icon = params.icon,
            description = params.description or '',
            order = params.order,
            content_type = params.content_type,
            secure = params.secure,
            public = params.public,
            announced = params.announced,
        },
        data = {
            set = params.template_set,
            data_func = params.data_func or '',
            resources = resources,
            source = params.content
        }
    })

    -- Apply changes through governance client
    local result, err = governance.request_changes(changes)
    if not result then
        return { success = false, error = 'Failed to apply registry changes: ' .. (err or 'unknown error') }
    end

    -- Return success response
    return {
        success = true,
        message = 'View created successfully',
        view = {
            id = params.namespace .. ':' .. params.name,
            name = params.name,
            title = params.title,
            namespace = params.namespace,
            version = result.version
        }
    }
end

return {
    handler = handler
}