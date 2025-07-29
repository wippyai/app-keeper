local registry = require("registry")
local json = require("json")

local function handler(params)
    -- Initialize response structure
    local response = {
        success = false,
        error = nil,
        routers = {},
        orphaned_endpoints = {},
        summary = {
            total_endpoints = 0,
            total_routers = 0,
            orphaned_count = 0
        }
    }
    
    -- Get registry snapshot for consistent data access
    local snapshot, err = registry.snapshot()
    if not snapshot then
        response.error = "Failed to get registry snapshot: " .. (err or "unknown error")
        return response
    end
    
    -- Find all HTTP endpoints
    local endpoints, err = snapshot:find({[".kind"] = "http.endpoint"})
    if err then
        response.error = "Failed to find HTTP endpoints: " .. err
        return response
    end
    
    -- Find all HTTP routers for reference
    local routers, err = snapshot:find({[".kind"] = "http.router"})
    if err then
        response.error = "Failed to find HTTP routers: " .. err
        return response
    end
    
    -- Build router lookup table
    local router_lookup = {}
    for _, router in ipairs(routers) do
        local router_id = type(router.id) == "string" and router.id or (router.id.ns .. ":" .. router.id.name)
        router_lookup[router_id] = router
    end
    
    -- Apply router filter if specified
    local filtered_routers = {}
    if params and params.router_filter then
        if router_lookup[params.router_filter] then
            filtered_routers[params.router_filter] = router_lookup[params.router_filter]
        else
            response.error = "Router not found: " .. params.router_filter
            return response
        end
    else
        filtered_routers = router_lookup
    end
    
    -- Process each endpoint
    for _, endpoint in ipairs(endpoints) do
        local endpoint_id = type(endpoint.id) == "string" and endpoint.id or (endpoint.id.ns .. ":" .. endpoint.id.name)
        
        -- Extract endpoint data
        local endpoint_data = {
            id = endpoint_id,
            method = endpoint.method or (endpoint.data and endpoint.data.method) or "UNKNOWN",
            path = endpoint.path or (endpoint.data and endpoint.data.path) or "/",
            handler = endpoint.func or (endpoint.data and endpoint.data.func) or "unknown",
            comment = (endpoint.meta and endpoint.meta.comment) or "",
            full_path = endpoint.path or (endpoint.data and endpoint.data.path) or "/"
        }
        
        -- Get router information - check both locations with priority
        local router_id = endpoint.router or (endpoint.meta and endpoint.meta.router)
        local router_config = nil
        
        if router_id and router_lookup[router_id] then
            router_config = router_lookup[router_id]
            
            -- Skip if router filter is applied and this router doesn't match
            if params and params.router_filter and router_id ~= params.router_filter then
                goto continue
            end
            
            -- Calculate full path by combining router prefix with endpoint path
            local prefix = ""
            -- Check for prefix in router.data.prefix first, then router.prefix
            if router_config.data and router_config.data.prefix then
                prefix = router_config.data.prefix
            elseif router_config.prefix then
                prefix = router_config.prefix
                -- Ensure prefix ends with / if it doesn't already
                if not prefix:match("/$") and prefix ~= "" then
                    prefix = prefix .. "/"
                end
            end
            
            local endpoint_path = endpoint.path or (endpoint.data and endpoint.data.path) or "/"
            -- Remove leading / from endpoint path if prefix already has trailing /
            if endpoint_path:match("^/") and prefix:match("/$") then
                endpoint_path = endpoint_path:sub(2)
            end
            
            endpoint_data.full_path = prefix .. endpoint_path
            
            -- Initialize router entry if not exists
            if not response.routers[router_id] then
                response.routers[router_id] = {
                    id = router_id,
                    name = router_config.name or "unknown",
                    prefix = (router_config.data and router_config.data.prefix) or router_config.prefix or "",
                    middleware = router_config.middleware or {},
                    post_middleware = router_config.post_middleware or {},
                    options = router_config.options or {},
                    endpoints = {}
                }
            end
            
            -- Add endpoint to router
            table.insert(response.routers[router_id].endpoints, endpoint_data)
        else
            -- Handle orphaned endpoints (no router or router not found)
            endpoint_data.router_id = router_id or "none"
            endpoint_data.router_status = router_id and "not_found" or "not_specified"
            table.insert(response.orphaned_endpoints, endpoint_data)
        end
        
        ::continue::
    end
    
    -- Sort endpoints within each router by method, then by path
    for router_id, router_data in pairs(response.routers) do
        table.sort(router_data.endpoints, function(a, b)
            if a.method == b.method then
                return a.path < b.path
            end
            return a.method < b.method
        end)
    end
    
    -- Sort orphaned endpoints
    table.sort(response.orphaned_endpoints, function(a, b)
        if a.method == b.method then
            return a.path < b.path
        end
        return a.method < b.method
    end)
    
    -- Calculate summary statistics
    local total_endpoints = 0
    local total_routers = 0
    
    for _, router_data in pairs(response.routers) do
        total_routers = total_routers + 1
        total_endpoints = total_endpoints + #router_data.endpoints
    end
    
    total_endpoints = total_endpoints + #response.orphaned_endpoints
    
    response.summary = {
        total_endpoints = total_endpoints,
        total_routers = total_routers,
        orphaned_count = #response.orphaned_endpoints,
        filter_applied = params and params.router_filter or nil
    }
    
    -- Success
    response.success = true
    return response
end

return {
    handler = handler
}