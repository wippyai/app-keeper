local registry = require("registry")
local json = require("json")
local governance = require("governance_client")

-- Valid HTTP methods based on wippy.docs:http.spec
local VALID_HTTP_METHODS = {
    GET = true,
    POST = true,
    PUT = true,
    DELETE = true,
    PATCH = true,
    HEAD = true,
    OPTIONS = true
}

local function handler(params)
    -- Initialize response structure
    local response = {
        success = false,
        error = nil,
        endpoint = nil
    }
    
    -- Validate required parameters
    if not params.endpoint_id then
        response.error = "Missing required parameter: endpoint_id"
        return response
    end
    
    if not params.router_id then
        response.error = "Missing required parameter: router_id"
        return response
    end
    
    if not params.path then
        response.error = "Missing required parameter: path"
        return response
    end
    
    if not params.method then
        response.error = "Missing required parameter: method"
        return response
    end
    
    if not params.function_id then
        response.error = "Missing required parameter: function_id"
        return response
    end

    if not params.comment then
        response.error = "Missing required parameter: comment"
        return response
    end

    -- Parse endpoint_id to get namespace and name
    local namespace, name = params.endpoint_id:match("([^:]+):(.+)")
    if not namespace or not name then
        response.error = "Invalid endpoint_id format. Expected 'namespace:name' format"
        return response
    end

    -- Validate function_id format
    local func_namespace, func_name = params.function_id:match("([^:]+):(.+)")
    if not func_namespace or not func_name then
        response.error = "Invalid function_id format. Expected 'namespace:name' format (e.g., 'app.api:time_handler')"
        return response
    end

    -- Validate HTTP method
    local method_upper = string.upper(params.method)
    if not VALID_HTTP_METHODS[method_upper] then
        response.error = "Invalid HTTP method: " .. params.method .. ". Valid methods are: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS"
        return response
    end

    -- Validate path format
    if not params.path:match("^/") then
        response.error = "Path must start with '/'. Got: " .. params.path
        return response
    end

    -- Basic path validation - check for valid URL characters
    if not params.path:match("^[%w%-%._~:/?#%[%]@!$&'%(%)%*%+,;=%%]+$") then
        response.error = "Path contains invalid characters. Path: " .. params.path
        return response
    end

    -- Get registry snapshot for consistent data access
    local snapshot, err = registry.snapshot()
    if not snapshot then
        response.error = "Failed to get registry snapshot: " .. (err or "unknown error")
        return response
    end

    -- Check if endpoint already exists
    local existing_endpoint = snapshot:get(params.endpoint_id)
    if existing_endpoint then
        response.error = "Endpoint already exists: " .. params.endpoint_id
        return response
    end

    -- Validate that the router exists
    local router_entry = snapshot:get(params.router_id)
    if not router_entry then
        response.error = "Router not found: " .. params.router_id
        return response
    end

    -- Validate that the router is actually an http.router
    if router_entry.kind ~= "http.router" then
        response.error = "Referenced entry is not an http.router. Found kind: " .. (router_entry.kind or "unknown")
        return response
    end

    -- Validate that the function exists
    local function_entry = snapshot:get(params.function_id)
    if not function_entry then
        response.error = "Handler function not found: " .. params.function_id
        return response
    end

    -- Validate that the function is actually a Lua function
    if function_entry.kind ~= "function.lua" then
        response.error = "Referenced entry is not a Lua function. Found kind: " .. (function_entry.kind or "unknown")
        return response
    end

    -- Check for duplicate endpoint paths on the same router
    local existing_endpoints, err = snapshot:find({[".kind"] = "http.endpoint"})
    if err then
        response.error = "Failed to search for existing endpoints: " .. err
        return response
    end

    -- Check for path conflicts on the same router
    for _, endpoint in ipairs(existing_endpoints) do
        -- Check both endpoint.router and endpoint.data.router for router association
        local endpoint_router = endpoint.router or (endpoint.data and endpoint.data.router)
        -- Check both endpoint.method and endpoint.data.method for method
        local endpoint_method = endpoint.method or (endpoint.data and endpoint.data.method)
        -- Check both endpoint.path and endpoint.data.path for path
        local endpoint_path = endpoint.path or (endpoint.data and endpoint.data.path)

        if endpoint_router == params.router_id and
           endpoint_method == method_upper and
           endpoint_path == params.path then
            local endpoint_id = type(endpoint.id) == "string" and endpoint.id or (endpoint.id.ns .. ":" .. endpoint.id.name)
            response.error = "Duplicate endpoint found. Router '" .. params.router_id .. "' already has " .. method_upper .. " " .. params.path .. " defined in endpoint: " .. endpoint_id
            return response
        end
    end

    -- Create a changeset from the snapshot
    local changes = snapshot:changes()

    -- Create the new endpoint entry with proper registry structure
    -- Ensure meta and data tables are properly structured to match YAML import format
    local entry_data = {
        id = { ns = namespace, name = name },
        kind = "http.endpoint",
        meta = {
            comment = params.comment,
            router = params.router_id
        },
        data = {
            func = params.function_id,
            kind = "http.endpoint",
            meta = {
                comment = params.comment,
                router = params.router_id
            },
            method = method_upper,
            name = name,
            path = params.path,
            router = params.router_id
        }
    }

    -- Validate that meta and data are not nil before creating
    if not entry_data.meta then
        response.error = "Internal error: meta table is nil"
        return response
    end

    if not entry_data.data then
        response.error = "Internal error: data table is nil"
        return response
    end

    changes:create(entry_data)

    -- Apply changes through governance client
    local result, err = governance.request_changes(changes)
    if not result then
        response.error = "Failed to apply registry changes: " .. (err or "unknown error")
        return response
    end

    -- Calculate full path by combining router prefix with endpoint path
    local full_path = params.path
    local prefix = (router_entry.data and router_entry.data.prefix) or ""
    
    if prefix ~= "" then
        -- Ensure prefix ends with / if it doesn't already
        if not prefix:match("/$") and prefix ~= "" then
            prefix = prefix .. "/"
        end

        local endpoint_path = params.path
        -- Remove leading / from endpoint path if prefix already has trailing /
        if endpoint_path:match("^/") and prefix:match("/$") then
            endpoint_path = endpoint_path:sub(2)
        end

        full_path = prefix .. endpoint_path
    end

    -- Success response
    response.success = true
    response.endpoint = {
        id = params.endpoint_id,
        router_id = params.router_id,
        method = method_upper,
        path = params.path,
        full_path = full_path,
        function_id = params.function_id,
        comment = params.comment
    }
    response.version = result.version
    response.message = "HTTP endpoint created successfully"
    
    return response
end

return {
    handler = handler
}