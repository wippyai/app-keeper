local registry = require("registry")

local function handler(params)
    -- Get a snapshot of the registry
    local snapshot, err = registry.snapshot()
    if not snapshot then
        return {
            success = false,
            error = "Failed to get registry snapshot: " .. (err or "unknown error")
        }
    end

    -- Find all view resources
    local entries, err = snapshot:find({
        [".kind"] = "registry.entry",
        ["meta.type"] = "view.resource"
    })

    if err then
        return {
            success = false,
            error = "Failed to find resources: " .. err
        }
    end

    -- Create comprehensive list of resources with all metadata
    local resources = {}
    local grouped_by_type = {}
    local grouped_by_set = {}

    for _, entry in ipairs(entries) do
        if entry.meta then
            local parsed_id = registry.parse_id(entry.id)

            -- Create detailed resource object with all metadata
            local resource = {
                id = parsed_id.name,
                full_id = entry.id,
                namespace = parsed_id.ns,
                name = entry.meta.name or "",
                resource_type = entry.meta.resource_type or "other",
                order = entry.meta.order or 9999,
                global = entry.meta.global or false,
                template_set = entry.meta.template_set or "",
                url = entry.meta.url or "",
                inline = entry.meta.inline or false,
                integrity = entry.meta.integrity or "",
                crossorigin = entry.meta.crossorigin or entry.meta.cross_origin or "",
                media = entry.meta.media or "",
                defer = entry.meta.defer or false,
                async = entry.meta.async or false,
                description = entry.meta.comment or entry.meta.description or "",
            }

            -- Add to main list
            table.insert(resources, resource)

            -- Group by resource type
            local res_type = resource.resource_type
            if not grouped_by_type[res_type] then
                grouped_by_type[res_type] = {}
            end
            table.insert(grouped_by_type[res_type], resource)

            -- Group by template set
            if resource.template_set and resource.template_set ~= "" then
                if not grouped_by_set[resource.template_set] then
                    grouped_by_set[resource.template_set] = {}
                end
                table.insert(grouped_by_set[resource.template_set], resource)
            end
        end
    end

    -- Sort each group by order
    for _, group in pairs(grouped_by_type) do
        table.sort(group, function(a, b) return a.order < b.order end)
    end

    for _, group in pairs(grouped_by_set) do
        table.sort(group, function(a, b) return a.order < b.order end)
    end

    -- Sort main list by resource type and order
    table.sort(resources, function(a, b)
        if a.resource_type == b.resource_type then
            return a.order < b.order
        end
        return a.resource_type < b.resource_type
    end)

    -- Return results with both flat list and groupings
    return {
        success = true,
        count = #resources,
        resources = resources,
        by_type = grouped_by_type,
        by_template_set = grouped_by_set
    }
end

return {
    handler = handler
}