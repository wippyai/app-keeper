local http = require("http")
local json = require("json")
local registry = require("registry")
local time = require("time")
local client = require("gov_client")

-- Handler function for HTTP endpoint
local function handler()
    local res = http.response()
    local req = http.request()

    if not req or not res then
        return nil, "Failed to get HTTP context"
    end

    -- Set JSON content type
    res:set_content_type(http.CONTENT.JSON)

    -- Get current registry version
    local current_version, err = registry.current_version()
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            message =  "Failed to get current registry version: " .. err
        })
        return
    end

    -- Get previous version
    local prev_version = current_version:previous()
    if not prev_version then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:write_json({
            success = false,
            message =  "No previous version available to undo to"
        })
        return
    end

    -- Use the governance client to request applying the previous version
    -- This uses the correct central process architecture
    local success, err = client.request_version(prev_version:id(), {}, 90000) -- 90 second timeout

    if not success then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            message =  "Failed to apply previous version: " .. (err or "unknown error")
        })
        return
    end

    -- Success response
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        message = "Successfully reverted to previous version",
        previous_version = current_version:id(),
        current_version = prev_version:id()
    })
end

return {
    handler = handler
}