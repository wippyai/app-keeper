local http = require("http")
local json = require("json")
local security = require("security")
local remote = require("remote")
local env = require("env")

local function handler()
    local res = http.response()
    local req = http.request()

    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Security check - ensure user is authenticated
    local actor = security.actor()
    if not actor then
        res:set_status(http.STATUS.UNAUTHORIZED)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Authentication required"
        })
        return
    end

    -- Check request method
    if req:method() ~= http.METHOD.POST then
        res:set_status(http.STATUS.METHOD_NOT_ALLOWED)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Method not allowed"
        })
        return
    end

    -- Get parameters from request body
    local body, err = req:body_json()
    if err then
        -- If parsing fails, continue with default parameters
        body = {}
    end

    if not body then
        body = {}
    end

    -- Pull changes
    local result, err = remote.pull(body.remote, body.branch)
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to pull changes: " .. err
        })
        return
    end

    -- Return response
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = "Successfully pulled changes",
        details = result
    })
end

return {
    handler = handler
}