local http = require("http")
local json = require("json")
local security = require("security")
local branch = require("branch")
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
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Invalid request body: " .. err
        })
        return
    end

    if not body or not body.branch_name then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing required parameter: branch_name"
        })
        return
    end

    -- Determine if we should switch to the new branch
    local switch_to_branch = body.switch_to_branch == true

    -- Create the branch
    local success, err
    if switch_to_branch then
        success, err = branch.create_and_switch(body.branch_name, body.start_point)
    else
        success, err = branch.create(body.branch_name, body.start_point)
    end

    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to create branch: " .. err
        })
        return
    end

    -- Return response
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = "Successfully created branch: " .. body.branch_name,
        switched = switch_to_branch
    })
end

return {
    handler = handler
}