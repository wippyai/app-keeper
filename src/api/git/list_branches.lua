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

    -- Get parameter to include remote branches
    local include_remote = req:query("include_remote")
    include_remote = include_remote == "true" or include_remote == "1"

    -- Get branch list
    local branches, err = branch.list(include_remote)
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to list branches: " .. err
        })
        return
    end

    -- Return response
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        branches = branches
    })
end

return {
    handler = handler
}