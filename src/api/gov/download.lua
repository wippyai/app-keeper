local http = require("http")
local time = require("time")
local gov_client = require("gov_client")

-- Handler function for HTTP endpoint
local function handler()
    local res = http.response()
    local req = http.request()

    if not req or not res then
        return nil, "Failed to get HTTP context"
    end

    -- Set JSON content type
    res:set_content_type(http.CONTENT.JSON)

    -- Use the client library to request a download
    local stats, err = gov_client.request_download({}, 90000)  -- 90 second timeout

    if not stats then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            message = err or "Unknown error during download operation"
        })
        return
    end

    -- Success response
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        message = "Registry successfully downloaded to filesystem",
        stats = stats
    })
end

return {
    handler = handler
}