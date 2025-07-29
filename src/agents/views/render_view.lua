local renderer = require("renderer")

local function handler(params)
    -- Validate required input
    if not params.id then
        return {
            success = false,
            error = "Missing required parameter: id"
        }
    end

    -- Parse route and query parameters
    local route_params = params.route_params or {}
    local query_params = params.query_params or {}

    -- Attempt to render the view
    local content, err = renderer.render(params.id, route_params, query_params)

    if err then
        return {
            success = false,
            error = "Failed to render view: " .. tostring(err)
        }
    end

    -- Just return the rendered content directly on success
    return content
end

return {
    handler = handler
}