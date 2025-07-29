local http = require("http")
local security = require("security")
local dataflow_repo = require("dataflow_repo")
local json = require("json")

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

    -- Get user ID from the authenticated actor
    local actor_id = actor:id()

    -- Get dataflow and verify ownership in one call
    local dataflow, err_dataflow = dataflow_repo.get_by_user(dataflow_id, actor_id)
    if err_dataflow then
        local status = http.STATUS.INTERNAL_ERROR
        if string.find(err_dataflow, "not found") then
            status = http.STATUS.NOT_FOUND
        end

    local dataflow, err_dataflow = dataflow_repo.get(dataflow_id)
print(json.encode(dataflow))


        res:set_status(status)
        res:write_json({
            success = false,
            error = err_dataflow
        })
        return
    end

    -- Get nodes for this dataflow using the repository
    local nodes, err_nodes = dataflow_repo.get_nodes_for_dataflow(dataflow_id)
    if err_nodes then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            error = err_nodes
        })
        return
    end

    -- Return the dataflow and nodes
    res:set_content_type(http.CONTENT.JSON)
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        dataflow = dataflow,
        nodes = nodes or {}
    })
end

return {
    handler = handler
}
