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
    local tag = req:query("tag") -- Optional tag filter

    -- Get a snapshot of the registry
    local snapshot, err = registry.snapshot()
    if not snapshot then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to get registry snapshot: " .. (err or "unknown error")
        })
        return
    end

    -- Get all entries
    local all_entries = snapshot:entries()

    -- Filter for extraction groups only (registry.entry with type docscout.extraction_group)
    local extraction_groups = {}
    for _, entry in ipairs(all_entries) do
        if entry.kind == "registry.entry" and
           entry.meta and
           entry.meta.type == "docscout.extraction_group" then

            -- Apply tag filter if specified
            if not tag or (entry.meta.tags and table.concat(entry.meta.tags, " "):find(tag)) then
                table.insert(extraction_groups, entry)
            end
        end
    end

    local total_count = #extraction_groups

    -- Apply pagination
    local paged_entries = {}
    local end_index = math.min(offset + limit, total_count)

    for i = offset + 1, end_index do
        local entry = extraction_groups[i]
        if entry then -- Check if entry exists
            -- Get the model information
            local model = nil
            local scout_validation = 0
            local scout_model = nil

            -- Extract model information from extracting section
            if entry.data and entry.data.extracting and entry.data.extracting.model then
                model = entry.data.extracting.model
            end

            -- Get scout validation information if available
            if entry.data and entry.data.scouting then
                if entry.data.scouting.max_iterations then
                    scout_validation = entry.data.scouting.max_iterations
                end

                if entry.data.scouting.model then
                    scout_model = entry.data.scouting.model
                end
            end

            -- Format the output to include relevant information for extraction groups
            table.insert(paged_entries, {
                id = entry.id,
                title = entry.meta.title or "",
                name = entry.meta.name or "",
                description = entry.meta.comment or "",
                tags = entry.meta.tags or {},
                field_count = entry.data and entry.data.fields and table.getn(entry.data.fields) or 0,
                -- Include only the field names to keep the response size reasonable
                fields = entry.data and entry.data.fields and get_field_names(entry.data.fields) or {},
                -- Add model information
                model = model,
                scout_validation = scout_validation,
                scout_model = scout_model
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
        tag = tag or nil,
        has_more = end_index < total_count,
        groups = paged_entries
    })
end

-- Helper function to extract field names
function get_field_names(fields)
    if not fields then return {} end

    local names = {}
    for field_name, _ in pairs(fields) do
        table.insert(names, field_name)
    end

    -- Sort field names alphabetically
    table.sort(names)

    return names
end

return {
    handler = handler
}