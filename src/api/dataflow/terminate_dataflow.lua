local http = require("http")
local security = require("security")
local dataflow_client = require("dataflow_client")

local function handler()
    -- Get HTTP context
    local res = http.response()
    local req = http.request()

    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Check authentication
    local actor = security.actor()
    if not actor then
        res:set_status(http.STATUS.UNAUTHORIZED)
        res:write_json({
            success = false,
            error = "Authentication required"
        })
        return
    end

    -- Get dataflow ID from URL path
    local dataflow_id = req:param("id")
    if not dataflow_id or dataflow_id == "" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:write_json({
            success = false,
            error = "Workflow ID is required"
        })
        return
    end

    -- Get authenticated user ID
    local actor_id = actor:id()

    -- Terminate the dataflow
    local success, error_msg, info = dataflow_client.terminate_dataflow(dataflow_id, actor_id)

    if not success then
        -- Determine appropriate HTTP status code
        local status_code = http.STATUS.INTERNAL_ERROR

        if error_msg and string.find(error_msg, "not found") then
            status_code = http.STATUS.NOT_FOUND
        elseif error_msg and string.find(error_msg, "access denied") then
            status_code = http.STATUS.NOT_FOUND
        elseif error_msg and string.find(error_msg, "already finished") then
            status_code = http.STATUS.BAD_REQUEST
        end

        res:set_status(status_code)
        res:write_json({
            success = false,
            error = error_msg
        })
        return
    end

    -- Return success response
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = "Workflow terminated successfully",
        dataflow_id = dataflow_id,
        process_terminated = info.process_terminated or false,
        status_updated = info.status_updated or false
    })
end

return {
    handler = handler
}