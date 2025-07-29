local http = require("http")
local security = require("security")
local sql = require("sql")
local json = require("json")
local data_reader = require("data_reader")

local DB_RESOURCE = "app:db"

-- Helper to check if a content type is likely text-based
local function is_text_content_type(content_type)
    if not content_type or content_type == "" then
        return false -- Default to not text if unknown
    end
    content_type = string.lower(content_type)
    if string.match(content_type, "^text/") or
       string.match(content_type, "json") or
       string.match(content_type, "xml") or
       string.match(content_type, "html") or
       string.match(content_type, "csv") or
       string.match(content_type, "javascript") or
       string.match(content_type, "css") then
        return true
    end
    return false
end

local function handler()
    local res = http.response()
    local req = http.request()

    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    local actor = security.actor()
    if not actor then
        res:set_status(http.STATUS.UNAUTHORIZED)
        res:write_json({
            success = false,
            error = "Authentication required"
        })
        return
    end

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

    local db, err_db = sql.get(DB_RESOURCE)
    if err_db then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            error = "Database connection error: " .. err_db
        })
        return
    end

    -- Verify the dataflow exists and belongs to the actor
    local dataflow_query = sql.builder.select("*")
        :from("dataflows")
        :where(sql.builder.and_({
            sql.builder.eq({dataflow_id = dataflow_id}),
            sql.builder.eq({actor_id = actor_id})
        }))
        :limit(1)

    local dataflow_executor = dataflow_query:run_with(db)
    local dataflow_results, err_dataflow = dataflow_executor:query()

    if err_dataflow then
        db:release()
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            error = "Failed to fetch dataflow: " .. err_dataflow
        })
        return
    end

    if not dataflow_results or #dataflow_results == 0 then
        db:release()
        res:set_status(http.STATUS.NOT_FOUND)
        res:write_json({
            success = false,
            error = "Workflow not found or access denied"
        })
        return
    end

    local dataflow = dataflow_results[1]
    if dataflow.metadata and type(dataflow.metadata) == "string" then
        local decoded, err_decode = json.decode(dataflow.metadata)
        dataflow.metadata = not err_decode and decoded or {}
    elseif dataflow.metadata == nil then
        dataflow.metadata = {}
    end

    -- Get nodes
    local nodes_query = sql.builder.select("*")
        :from("nodes")
        :where("dataflow_id = ?", dataflow_id)
        :order_by("node_id ASC")
    local nodes_executor = nodes_query:run_with(db)
    local nodes, err_nodes = nodes_executor:query()

    if err_nodes then
        db:release()
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({ success = false, error = "Failed to fetch nodes: " .. err_nodes })
        return
    end

    for i, node in ipairs(nodes or {}) do
        if node.metadata and type(node.metadata) == "string" then
            local decoded, err_decode = json.decode(node.metadata)
            nodes[i].metadata = not err_decode and decoded or {}
        else
            nodes[i].metadata = {}
        end
    end

    -- Now we can release the database connection as we'll use data_reader
    db:release()

    -- Use data_reader to fetch all data with references resolved
    local data_items = data_reader.with_dataflow(dataflow_id)
        :fetch_options({
            resolve_references = true,
            content = true,
            metadata = true
        })
        :all()

    res:set_content_type(http.CONTENT.JSON)
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        dataflow = dataflow,
        nodes = nodes or {},
        data = data_items or {}
    })
end

return {
    handler = handler
}