local http = require("http")
local json = require("json")
local security = require("security")
local commit = require("commit")
local env = require("env")

local function handler()
    local res = http.response()
    local req = http.request()

    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Security check
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

    -- Stage all changes if requested
    if body.stage_all then
        local stage_success, stage_err = commit.stage_all()
        if stage_err then
            res:set_status(http.STATUS.INTERNAL_ERROR)
            res:set_content_type(http.CONTENT.JSON)
            res:write_json({
                success = false,
                error = "Failed to stage changes: " .. stage_err
            })
            return
        end
    end

    -- Stage specific files if requested
    if body.files and type(body.files) == "table" and #body.files > 0 then
        local staged_files = {}
        for _, file in ipairs(body.files) do
            local stage_success, stage_err = commit.stage_file(file)
            if stage_err then
                res:set_status(http.STATUS.INTERNAL_ERROR)
                res:set_content_type(http.CONTENT.JSON)
                res:write_json({
                    success = false,
                    error = "Failed to stage file " .. file .. ": " .. stage_err
                })
                return
            end
            table.insert(staged_files, file)
        end
    end

    -- Return response
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = body.stage_all
            and "Successfully staged all changes"
            or "Successfully staged specified files"
    })
end

return {
    handler = handler
}