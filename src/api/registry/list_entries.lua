local http = require("http")
local json = require("json")
local registry = require("registry")

local function handler()
    -- Get response object
    local res = http.response()
    local req = http.request()
    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Get query parameters for pagination and filtering
    local limit = tonumber(req:query("limit")) or 100
    local offset = tonumber(req:query("offset")) or 0
    local kind = req:query("kind") -- Optional kind filter
    local namespace = req:query("namespace") -- Optional namespace filter
    local meta_type = req:query("meta.type") -- Optional meta.type filter

    local entries
    local err

    -- Get entries based on namespace filter
    if namespace and namespace ~= "" then
        -- Find entries directly using registry.find() with namespace filter
        local criteria = {
            [".ns"] = namespace
        }

        -- Add kind filter if specified
        if kind and kind ~= "" then
            criteria[".kind"] = kind
        end

        -- Add meta.type filter if specified
        if meta_type and meta_type ~= "" then
            criteria["meta.type"] = meta_type
        end

        entries, err = registry.find(criteria)
    else
        -- Get all entries with or without kind filter
        local criteria = {}

        if kind and kind ~= "" then
            criteria[".kind"] = kind
        end

        -- Add meta.type filter if specified
        if meta_type and meta_type ~= "" then
            criteria["meta.type"] = meta_type
        end

        -- If we have any criteria, use find() otherwise get all entries
        if next(criteria) then
            entries, err = registry.find(criteria)
        else
            entries, err = registry.snapshot():entries()
        end
    end

    if not entries then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to get entries: " .. (err or "unknown error")
        })
        return
    end

    local total_count = #entries

    -- Apply pagination
    local paged_entries = {}
    local end_index = math.min(offset + limit, total_count)

    for i = offset + 1, end_index do
        local entry = entries[i]
        if entry then -- Check if entry exists
            table.insert(paged_entries, {
                id = entry.id,
                kind = entry.kind,
                meta = entry.meta or {}
            })
        end
    end

    -- Return JSON response
    res:set_content_type(http.CONTENT.JSON)
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        count = #paged_entries,
        total = total_count,
        offset = offset,
        limit = limit,
        namespace = namespace or nil,
        kind = kind or nil,
        meta_type = meta_type or nil,
        has_more = end_index < total_count,
        entries = paged_entries
    })
end

return {
    handler = handler
}