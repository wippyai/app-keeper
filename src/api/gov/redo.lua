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
            message = "Failed to get current registry version: " .. err
        })
        return
    end

    -- Parse current version ID as a number
    local current_id = tonumber(current_version:id())
    if not current_id then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            message = "Failed to parse current version ID as a number"
        })
        return
    end

    -- Find the next version ID (current + 1)
    local next_id = current_id + 1

    -- Get all versions through history object
    local history = registry.history()
    local versions, err = history:versions()
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            message = "Failed to get registry versions: " .. err
        })
        return
    end

    -- Find the version with ID = next_id
    local next_version = nil
    for _, v in ipairs(versions) do
        local version_id = tonumber(v:id())
        if version_id and version_id == next_id then
            next_version = v
            break
        end
    end

    -- Check if we found a next version
    if not next_version then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:write_json({
            success = false,
            message = "No version with ID " .. next_id .. " found (cannot redo)"
        })
        return
    end

    -- Use the governance client to request applying the next version
    local success, err = client.request_version(next_version:id(), {}, 90000) -- 90 second timeout

    if not success then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            message = "Failed to apply next version: " .. (err or "unknown error")
        })
        return
    end

    -- Success response
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        message = "Successfully advanced to newer version",
        previous_version = current_version:id(),
        current_version = next_version:id()
    })
end

return {
    handler = handler
}