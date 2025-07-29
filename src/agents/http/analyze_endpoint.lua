local registry = require("registry")
local json = require("json")

-- HTTP Endpoint Analyzer Tool
-- Provides comprehensive analysis of HTTP endpoints including router, handler, and security configuration

local function handler(params)
    local response = {
        success = false,
        endpoint_id = params.endpoint_id,
        analysis = {},
        error = nil
    }

    -- Validate input
    if not params.endpoint_id or type(params.endpoint_id) ~= "string" or params.endpoint_id == "" then
        response.error = "Missing or invalid required parameter: endpoint_id (must be a non-empty string)"
        return response
    end

    -- Fetch the target endpoint using direct registry.get
    local endpoint_entry, err = registry.get(params.endpoint_id)
    if not endpoint_entry then
        response.error = "Endpoint not found: " .. params.endpoint_id .. " (" .. (err or "unknown error") .. ")"
        return response
    end

    -- Validate it's an HTTP endpoint
    if endpoint_entry.kind ~= "http.endpoint" then
        response.error = "Entry is not a valid HTTP endpoint: " .. params.endpoint_id .. " (kind: " .. (endpoint_entry.kind or "unknown") .. ")"
        return response
    end

    -- Initialize analysis structure
    local analysis = {
        endpoint_info = {},
        router_info = {},
        handler_info = {},
        security_info = {},
        url_resolution = {},
        validation = {},
        warnings = {},
        recommendations = {}
    }

    -- Helper function to safely get nested values
    local function safe_get(table, ...)
        local current = table
        for _, key in ipairs({...}) do
            if type(current) ~= "table" or current[key] == nil then
                return nil
            end
            current = current[key]
        end
        return current
    end

    -- Analyze endpoint information
    analysis.endpoint_info = {
        id = endpoint_entry.id,
        kind = endpoint_entry.kind,
        method = safe_get(endpoint_entry, "data", "method") or endpoint_entry.method or "unknown",
        path = safe_get(endpoint_entry, "data", "path") or endpoint_entry.path or "unknown",
        handler = safe_get(endpoint_entry, "data", "func") or safe_get(endpoint_entry, "data", "handler") or endpoint_entry.func or nil,
        router = safe_get(endpoint_entry, "meta", "router") or safe_get(endpoint_entry, "data", "router") or endpoint_entry.router or nil,
        comment = safe_get(endpoint_entry, "meta", "comment") or "",
        tags = safe_get(endpoint_entry, "meta", "tags") or {},
        middleware = safe_get(endpoint_entry, "data", "middleware") or {},
        timeout = safe_get(endpoint_entry, "data", "timeout") or nil,
        rate_limit = safe_get(endpoint_entry, "data", "rate_limit") or nil,
        auth_required = safe_get(endpoint_entry, "data", "auth_required") or nil
    }

    -- Analyze router information
    local router_entry = nil
    if analysis.endpoint_info.router then
        router_entry, err = registry.get(analysis.endpoint_info.router)
        if router_entry then
            if router_entry.kind == "http.router" then
                analysis.router_info = {
                    id = router_entry.id,
                    kind = router_entry.kind,
                    exists = true,
                    is_valid = true,
                    prefix = safe_get(router_entry, "data", "prefix") or router_entry.prefix or "",
                    comment = safe_get(router_entry, "meta", "comment") or "",
                    middleware = safe_get(router_entry, "data", "middleware") or router_entry.middleware or {},
                    post_middleware = safe_get(router_entry, "data", "post_middleware") or router_entry.post_middleware or {},
                    options = safe_get(router_entry, "data", "options") or router_entry.options or {},
                    security_level = safe_get(router_entry, "meta", "security_level") or "unknown",
                    cors_enabled = false,
                    auth_enabled = false,
                    websocket_enabled = false
                }
                
                -- Analyze router middleware
                local router_middleware = analysis.router_info.middleware
                if type(router_middleware) == "table" then
                    for _, middleware in ipairs(router_middleware) do
                        if middleware == "cors" then
                            analysis.router_info.cors_enabled = true
                        elseif middleware == "token_auth" or middleware == "auth" then
                            analysis.router_info.auth_enabled = true
                        elseif middleware == "websocket_relay" then
                            analysis.router_info.websocket_enabled = true
                        end
                    end
                end
            else
                analysis.router_info = {
                    id = analysis.endpoint_info.router,
                    exists = true,
                    is_valid = false,
                    error = "Referenced entry is not an HTTP router (kind: " .. (router_entry.kind or "unknown") .. ")"
                }
                table.insert(analysis.warnings, "Router reference points to non-router entry: " .. analysis.endpoint_info.router)
            end
        else
            analysis.router_info = {
                id = analysis.endpoint_info.router,
                exists = false,
                is_valid = false,
                error = err or "Router not found"
            }
            table.insert(analysis.warnings, "Router not found: " .. analysis.endpoint_info.router)
        end
    else
        analysis.router_info = {
            exists = false,
            is_valid = false,
            error = "No router specified for endpoint"
        }
        table.insert(analysis.warnings, "Endpoint has no router assignment")
    end

    -- Analyze handler function information
    local handler_entry = nil
    local handler_id = analysis.endpoint_info.handler
    
    -- If handler is just a function name, construct the full ID using endpoint namespace
    if handler_id and not handler_id:find(":") then
        local endpoint_ns = params.endpoint_id:match("^([^:]+):")
        if endpoint_ns then
            handler_id = endpoint_ns .. ":" .. handler_id
        end
    end
    
    if handler_id then
        handler_entry, err = registry.get(handler_id)
        if handler_entry then
            if handler_entry.kind == "function.lua" then
                analysis.handler_info = {
                    id = handler_entry.id,
                    kind = handler_entry.kind,
                    exists = true,
                    is_valid = true,
                    comment = safe_get(handler_entry, "meta", "comment") or "",
                    method = safe_get(handler_entry, "data", "method") or "handler",
                    modules = safe_get(handler_entry, "data", "modules") or {},
                    imports = safe_get(handler_entry, "data", "imports") or {},
                    source_length = 0,
                    has_source = false,
                    uses_http_module = false,
                    uses_registry_module = false
                }
                
                -- Analyze handler source
                local source = safe_get(handler_entry, "data", "source")
                if source and type(source) == "string" then
                    analysis.handler_info.has_source = true
                    analysis.handler_info.source_length = #source
                    analysis.handler_info.source_code = source
                    
                    -- Check for common module usage
                    if source:find('require%s*%(%s*["\']http["\']%s*%)') then
                        analysis.handler_info.uses_http_module = true
                    end
                    if source:find('require%s*%(%s*["\']registry["\']%s*%)') then
                        analysis.handler_info.uses_registry_module = true
                    end
                end
                
                -- Check declared modules
                local modules = analysis.handler_info.modules
                if type(modules) == "table" then
                    for _, module in ipairs(modules) do
                        if module == "http" then
                            analysis.handler_info.uses_http_module = true
                        elseif module == "registry" then
                            analysis.handler_info.uses_registry_module = true
                        end
                    end
                end
            else
                analysis.handler_info = {
                    id = handler_id,
                    exists = true,
                    is_valid = false,
                    error = "Referenced entry is not a Lua function (kind: " .. (handler_entry.kind or "unknown") .. ")"
                }
                table.insert(analysis.warnings, "Handler reference points to non-function entry: " .. handler_id)
            end
        else
            analysis.handler_info = {
                id = handler_id,
                exists = false,
                is_valid = false,
                error = err or "Handler function not found"
            }
            table.insert(analysis.warnings, "Handler function not found: " .. handler_id)
        end
    else
        analysis.handler_info = {
            exists = false,
            is_valid = false,
            error = "No handler function specified for endpoint"
        }
        table.insert(analysis.warnings, "Endpoint has no handler function assignment")
    end

    -- Analyze security configuration
    analysis.security_info = {
        router_auth_enabled = analysis.router_info.auth_enabled or false,
        router_cors_enabled = analysis.router_info.cors_enabled or false,
        router_websocket_enabled = analysis.router_info.websocket_enabled or false,
        endpoint_auth_required = analysis.endpoint_info.auth_required,
        endpoint_middleware = analysis.endpoint_info.middleware,
        security_level = analysis.router_info.security_level or "unknown",
        is_public = false,
        is_protected = false
    }
    
    -- Determine security classification
    if analysis.router_info.is_valid then
        local router_id = analysis.router_info.id or ""
        if router_id:find("public") then
            analysis.security_info.is_public = true
        elseif analysis.security_info.router_auth_enabled then
            analysis.security_info.is_protected = true
        end
    end

    -- Resolve full URL path
    analysis.url_resolution = {
        router_prefix = "",
        endpoint_path = analysis.endpoint_info.path,
        full_path = "",
        is_resolvable = false
    }
    
    if analysis.router_info.is_valid and analysis.router_info.prefix then
        analysis.url_resolution.router_prefix = analysis.router_info.prefix
        analysis.url_resolution.is_resolvable = true
        
        -- Combine router prefix and endpoint path
        local prefix = analysis.url_resolution.router_prefix
        local path = analysis.url_resolution.endpoint_path
        
        -- Ensure proper path joining
        if prefix == "" then
            analysis.url_resolution.full_path = path
        elseif prefix:sub(-1) == "/" and path:sub(1, 1) == "/" then
            analysis.url_resolution.full_path = prefix .. path:sub(2)
        elseif prefix:sub(-1) ~= "/" and path:sub(1, 1) ~= "/" then
            analysis.url_resolution.full_path = prefix .. "/" .. path
        else
            analysis.url_resolution.full_path = prefix .. path
        end
    else
        analysis.url_resolution.full_path = analysis.endpoint_info.path
    end

    -- Validation checks
    analysis.validation = {
        endpoint_valid = true,
        router_valid = analysis.router_info.is_valid or false,
        handler_valid = analysis.handler_info.is_valid or false,
        has_complete_config = false,
        method_valid = false,
        path_valid = false
    }
    
    -- Validate HTTP method
    local valid_methods = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"}
    for _, method in ipairs(valid_methods) do
        if analysis.endpoint_info.method == method then
            analysis.validation.method_valid = true
            break
        end
    end
    
    -- Validate path format
    local path = analysis.endpoint_info.path
    if path and path ~= "unknown" and path:sub(1, 1) == "/" then
        analysis.validation.path_valid = true
    end
    
    -- Check for complete configuration
    analysis.validation.has_complete_config = (
        analysis.validation.router_valid and
        analysis.validation.handler_valid and
        analysis.validation.method_valid and
        analysis.validation.path_valid
    )

    -- Generate additional warnings
    if not analysis.validation.method_valid then
        table.insert(analysis.warnings, "Invalid or missing HTTP method: " .. analysis.endpoint_info.method)
    end
    
    if not analysis.validation.path_valid then
        table.insert(analysis.warnings, "Invalid or missing endpoint path: " .. analysis.endpoint_info.path)
    end
    
    if analysis.handler_info.is_valid and not analysis.handler_info.uses_http_module then
        table.insert(analysis.warnings, "Handler function does not use 'http' module - may not be able to process HTTP requests")
    end
    
    if analysis.endpoint_info.comment == "" then
        table.insert(analysis.warnings, "Endpoint has no description/comment")
    end

    -- Generate recommendations
    if not analysis.validation.has_complete_config then
        table.insert(analysis.recommendations, "Fix missing or invalid router/handler references for complete endpoint configuration")
    end
    
    if analysis.endpoint_info.comment == "" then
        table.insert(analysis.recommendations, "Add a description (meta.comment) to explain the endpoint's purpose")
    end
    
    if not analysis.security_info.is_protected and not analysis.security_info.is_public then
        table.insert(analysis.recommendations, "Consider adding authentication middleware or moving to a public router if appropriate")
    end
    
    if analysis.handler_info.is_valid and not analysis.handler_info.has_source then
        table.insert(analysis.recommendations, "Handler function has no source code - verify implementation")
    end
    
    if #analysis.endpoint_info.tags == 0 then
        table.insert(analysis.recommendations, "Consider adding tags for better endpoint categorization")
    end

    response.success = true
    response.analysis = analysis
    return response
end

return {
    handler = handler
}