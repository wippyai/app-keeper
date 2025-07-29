local http = require("http")
local security = require("security")
local dataflow_client = require("dataflow_client")

local function handler()
    local res = http.response()
    local req = http.request()

    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Authentication check
    local actor = security.actor()
    if not actor then
        res:set_status(http.STATUS.UNAUTHORIZED)
        res:write_json({
            success = false,
            error = "Authentication required"
        })
        return
    end

    -- Get dataflow ID from path parameter
    local dataflow_id = req:param("id")
    if not dataflow_id or dataflow_id == "" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:write_json({
            success = false,
            error = "Workflow ID is required"
        })
        return
    end

    local actor_id = actor:id()

    -- Cancel the workflow using the client
    local success, error_msg, info = dataflow_client.cancel_dataflow(dataflow_id, actor_id, "30s")

    if not success then
        local status_code = http.STATUS.INTERNAL_ERROR

        -- Map error types to appropriate HTTP status codes
        if string.find(error_msg, "not found") or string.find(error_msg, "access denied") then
            status_code = http.STATUS.NOT_FOUND
        elseif string.find(error_msg, "cannot be cancelled") or string.find(error_msg, "current state") then
            status_code = http.STATUS.BAD_REQUEST
        elseif string.find(error_msg, "process not found") then
            status_code = http.STATUS.NOT_FOUND
        end

        res:set_status(status_code)
        res:write_json({
            success = false,
            error = error_msg
        })
        return
    end

    -- Success response
    res:set_content_type(http.CONTENT.JSON)
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        message = info.message,
        dataflow_id = info.dataflow_id,
        process_pid = info.process_pid,
        timeout = info.timeout
    })
end

return {
    handler = handler
}