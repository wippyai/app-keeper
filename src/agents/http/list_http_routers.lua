local registry = require("registry")
local json = require("json")

local function handler(params)
    -- Initialize response structure
    local response = {
        success = false,
        error = nil,
        routers = {},
        summary = {
            total_routers = 0,
            total_endpoints = 0,
            routers_with_endpoints = 0,
            routers_without_endpoints = 0
        }
    }
    
    -- Default parameters
    local include_endpoints = true
    local router_filter = nil
    
    if params then
        if params.include_endpoints ~= nil then
            include_endpoints = params.include_endpoints
        end
        router_filter = params.router_filter
    end
    
    -- Get registry snapshot for consistent data access
    local snapshot, err = registry.snapshot()
    if not snapshot then
        response.error = "Failed to get registry snapshot: " .. (err or "unknown error")
        return response
    end
    
    -- Find all HTTP routers
    local routers, err = snapshot:find({[".kind"] = "http.router"})
    if err then
        response.error = "Failed to find HTTP routers: " .. err
        return response
    end
    
    -- Find all HTTP endpoints if we need endpoint information
    local endpoints = {}
    if include_endpoints then
        local endpoint_results, err = snapshot:find({[".kind"] = "http.endpoint"})
        if err then
            response.error = "Failed to find HTTP endpoints: " .. err
            return response
        end
        endpoints = endpoint_results
    end
    
    -- Build endpoint lookup by router if needed
    local endpoints_by_router = {}
    if include_endpoints then
        for _, endpoint in ipairs(endpoints) do
            -- Check both endpoint.router and endpoint.meta.router for router association
            local router_id = endpoint.router or (endpoint.meta and endpoint.meta.router)
            if router_id then
                if not endpoints_by_router[router_id] then
                    endpoints_by_router[router_id] = {}
                end
                
                local endpoint_id = type(endpoint.id) == "string" and endpoint.id or (endpoint.id.ns .. ":" .. endpoint.id.name)
                local endpoint_data = {
                    id = endpoint_id,
                    method = endpoint.method or (endpoint.data and endpoint.data.method) or "UNKNOWN",
                    path = endpoint.path or (endpoint.data and endpoint.data.path) or "/",
                    handler = endpoint.func or (endpoint.data and endpoint.data.func) or "unknown",
                    comment = (endpoint.meta and endpoint.meta.comment) or ""
                }
                
                table.insert(endpoints_by_router[router_id], endpoint_data)
            end
        end
        
        -- Sort endpoints within each router by method, then by path
        for router_id, router_endpoints in pairs(endpoints_by_router) do
            table.sort(router_endpoints, function(a, b)
                if a.method == b.method then
                    return a.path < b.path
                end
                return a.method < b.method
            end)
        end
    end
    
    -- Process each router
    for _, router in ipairs(routers) do
        local router_id = type(router.id) == "string" and router.id or (router.id.ns .. ":" .. router.id.name)
        
        -- Apply router filter if specified
        if router_filter and router_id ~= router_filter then
            goto continue
        end
        
        -- Extract router configuration
        local router_data = {
            id = router_id,
            name = (router.data and router.data.name) or router.name or "unknown",
            prefix = (router.data and router.data.prefix) or router.prefix or "",
            middleware = (router.data and router.data.middleware) or router.middleware or {},
            post_middleware = (router.data and router.data.post_middleware) or router.post_middleware or {},
            options = (router.data and router.data.options) or router.options or {},
            server = (router.data and router.data.server) or router.server or nil,
            comment = (router.meta and router.meta.comment) or "",
            endpoint_count = 0,
            endpoints = {}
        }
        
        -- Add endpoint information if requested
        if include_endpoints then
            local router_endpoints = endpoints_by_router[router_id] or {}
            router_data.endpoint_count = #router_endpoints
            router_data.endpoints = router_endpoints
        else
            -- Just count endpoints without detailed info
            local router_endpoints = endpoints_by_router[router_id] or {}
            router_data.endpoint_count = #router_endpoints
        end
        
        -- Add router to response
        response.routers[router_id] = router_data
        
        ::continue::
    end
    
    -- Calculate summary statistics
    local total_routers = 0
    local total_endpoints = 0
    local routers_with_endpoints = 0
    local routers_without_endpoints = 0
    
    for _, router_data in pairs(response.routers) do
        total_routers = total_routers + 1
        total_endpoints = total_endpoints + router_data.endpoint_count
        
        if router_data.endpoint_count > 0 then
            routers_with_endpoints = routers_with_endpoints + 1
        else
            routers_without_endpoints = routers_without_endpoints + 1
        end
    end
    
    response.summary = {
        total_routers = total_routers,
        total_endpoints = total_endpoints,
        routers_with_endpoints = routers_with_endpoints,
        routers_without_endpoints = routers_without_endpoints,
        filter_applied = router_filter or nil,
        endpoints_included = include_endpoints
    }
    
    -- Success
    response.success = true
    return response
end

return {
    handler = handler
}