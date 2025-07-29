local http = require("http")
local security = require("security")
local dataflow_repo = require("dataflow_repo")

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
        res:write_json({
            success = false,
            error = "Authentication required"
        })
        return
    end

    -- Get user ID from the authenticated actor
    local actor_id = actor:id()

    -- Get query parameters for filtering
    local filters = {}

    -- Optional filter parameters
    if req:query("status") then
        filters.status = req:query("status")
    end

    if req:query("type") then
        filters.type = req:query("type")
    end

    if req:query("parent_dataflow_id") then
        filters.parent_dataflow_id = req:query("parent_dataflow_id")
    end

    -- Pagination parameters
    local limit = tonumber(req:query("limit") or "100")
    local offset = tonumber(req:query("offset") or "0")

    filters.limit = limit
    filters.offset = offset

    -- Get dataflows for this user with the specified filters
    local dataflows, err = dataflow_repo.list_by_user(actor_id, filters)
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            error = err
        })
        return
    end

    -- Return JSON response with all dataflows
    res:set_content_type(http.CONTENT.JSON)
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        count = #dataflows,
        dataflows = dataflows
    })
end

return {
    handler = handler
}