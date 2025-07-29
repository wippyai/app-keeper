local http = require("http")
local time = require("time")
local gov_client = require("gov_client")

-- Handler function for HTTP endpoint
local function handler()
    local res = http.response()
    local req = http.request()

    -- Set JSON content type
    res:set_content_type(http.CONTENT.JSON)

    -- Use the client library to request an upload
    local stats, err = gov_client.request_upload({}, 90000)  -- 90 second timeout

    if not stats then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            message = err or "Unknown error during upload operation"
        })
        return
    end

    -- Success response
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        message = "Filesystem changes successfully uploaded to registry",
        stats = stats
    })
end

return {
    handler = handler
}