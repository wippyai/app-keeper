local registry = require("registry")
local json = require("json")
local governance = require("governance_client")

local function handler(params)
    -- Initialize response structure
    local response = {
        success = false,
        error = nil,
        deleted_endpoint = nil,
        router_info = nil,
        warnings = {}
    }
    
    -- Validate required parameters
    if not params.endpoint_id then
        response.error = "Missing required parameter: endpoint_id"
        return response
    end
    
    -- Parse endpoint_id to get namespace and name
    local namespace, name = params.endpoint_id:match("([^:]+):(.+)")
    if not namespace or not name then
        response.error = "Invalid endpoint_id format. Expected 'namespace:name' format"
        return response
    end
    
    -- Get registry snapshot for consistent data access
    local snapshot, err = registry.snapshot()
    if not snapshot then
        response.error = "Failed to get registry snapshot: " .. (err or "unknown error")
        return response
    end
    
    -- Check if endpoint exists
    local existing_endpoint, err = snapshot:get(params.endpoint_id)
    if not existing_endpoint then
        response.error = "Endpoint not found: " .. params.endpoint_id
        return response
    end
    
    -- Validate that the entry is actually an http.endpoint
    if existing_endpoint.kind ~= "http.endpoint" then
        response.error = "Entry is not an HTTP endpoint. Found kind: " .. (existing_endpoint.kind or "unknown") .. ". Expected: http.endpoint"
        return response
    end
    
    -- Extract endpoint information for response
    local endpoint_info = {
        id = params.endpoint_id,
        namespace = namespace,
        name = name,
        method = existing_endpoint.method or (existing_endpoint.data and existing_endpoint.data.method) or "UNKNOWN",
        path = existing_endpoint.path or (existing_endpoint.data and existing_endpoint.data.path) or "/",
        handler_function = existing_endpoint.func or (existing_endpoint.data and existing_endpoint.data.func) or "unknown",
        comment = (existing_endpoint.meta and existing_endpoint.meta.comment) or ""
    }
    
    -- Check router associations
    local router_id = existing_endpoint.router or (existing_endpoint.meta and existing_endpoint.meta.router)
    local router_info = nil
    local router_warnings = {}
    
    if router_id then
        -- Get router information
        local router_entry, err = snapshot:get(router_id)
        if router_entry then
            -- Calculate full path if router has prefix
            local full_path = endpoint_info.path
            local prefix = ""
            if router_entry.data and router_entry.data.prefix then
                prefix = router_entry.data.prefix
            elseif router_entry.prefix then
                prefix = router_entry.prefix
            end
            
            if prefix and prefix ~= "" then
                -- Ensure prefix ends with / if it doesn't already
                if not prefix:match("/$") and prefix ~= "" then
                    prefix = prefix .. "/"
                end
                
                local endpoint_path = endpoint_info.path
                -- Remove leading / from endpoint path if prefix already has trailing /
                if endpoint_path:match("^/") and prefix:match("/$") then
                    endpoint_path = endpoint_path:sub(2)
                end
                
                full_path = prefix .. endpoint_path
            end
            
            router_info = {
                id = router_id,
                name = router_entry.name or "unknown",
                prefix = prefix,
                full_path = full_path,
                exists = true
            }
            
            table.insert(router_warnings, "Endpoint was associated with router '" .. router_id .. "' (full path: " .. full_path .. ")")
        else
            router_info = {
                id = router_id,
                exists = false
            }
            table.insert(router_warnings, "Endpoint was associated with router '" .. router_id .. "' but router was not found in registry")
        end
    else
        table.insert(router_warnings, "Endpoint was not associated with any router")
    end
    
    -- Check if there are other endpoints on the same router with similar paths
    if router_id then
        local related_endpoints, err = snapshot:find({[".kind"] = "http.endpoint"})
        if related_endpoints then
            local same_router_count = 0
            for _, endpoint in ipairs(related_endpoints) do
                local ep_router = endpoint.router or (endpoint.meta and endpoint.meta.router)
                local ep_id = type(endpoint.id) == "string" and endpoint.id or (endpoint.id.ns .. ":" .. endpoint.id.name)
                
                if ep_router == router_id and ep_id ~= params.endpoint_id then
                    same_router_count = same_router_count + 1
                end
            end
            
            if same_router_count > 0 then
                table.insert(router_warnings, "Router '" .. router_id .. "' still has " .. same_router_count .. " other endpoint(s) after this deletion")
            else
                table.insert(router_warnings, "Router '" .. router_id .. "' will have no endpoints after this deletion")
            end
        end
    end
    
    -- Create a changeset from the snapshot
    local changes = snapshot:changes()
    
    -- Delete the endpoint
    changes:delete(params.endpoint_id)
    
    -- Apply changes through governance client
    local result, err = governance.request_changes(changes)
    if not result then
        response.error = "Failed to apply registry changes: " .. (err or "unknown error")
        return response
    end
    
    -- Success response
    response.success = true
    response.deleted_endpoint = endpoint_info
    response.router_info = router_info
    response.warnings = router_warnings
    response.version = result.version
    response.message = "HTTP endpoint deleted successfully"
    
    return response
end

return {
    handler = handler
}