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

    -- Find all template.jet entries (layouts, components, etc.)
    local entries, err = snapshot:find({
        [".kind"] = "template.jet"
    })

    if err then
        return {
            success = false,
            error = "Failed to find templates: " .. err
        }
    end

    -- Create comprehensive list of templates
    local templates = {}
    local by_set = {}
    local by_type = {
        layout = {},
        component = {},
        partial = {},
        other = {}
    }

    for _, entry in ipairs(entries) do
        -- Skip if it has meta.type="view.page" (those are views, not templates)
        if not (entry.meta and entry.meta.type == "view.page") then
            local parsed_id = registry.parse_id(entry.id)
            local template_set = entry.set or ""

            -- Assume all templates are "other" type by default
            local template_type = "other"

            -- Create detailed template object
            local template = {
                id = parsed_id.name,
                full_id = entry.id,
                namespace = parsed_id.ns,
                name = entry.meta and entry.meta.name or "",
                description = entry.meta and entry.meta.description or entry.meta and entry.meta.comment or "",
                template_type = template_type,
                template_set = template_set,
                data_func = entry.data and entry.data.data_func or ""
            }

            -- Add to main list
            table.insert(templates, template)

            -- Group by template set
            if template_set and template_set ~= "" then
                if not by_set[template_set] then
                    by_set[template_set] = {}
                end
                table.insert(by_set[template_set], template)
            end

            -- Group by template type
            table.insert(by_type[template_type], template)
        end
    end

    -- Sort templates by name
    table.sort(templates, function(a, b) return a.name < b.name end)

    -- Sort each group
    for _, group in pairs(by_set) do
        table.sort(group, function(a, b) return a.name < b.name end)
    end

    for _, group in pairs(by_type) do
        table.sort(group, function(a, b) return a.name < b.name end)
    end

    -- Return results with both flat list and groupings
    return {
        success = true,
        count = #templates,
        templates = templates,
        by_set = by_set,
        by_type = by_type
    }
end

return {
    handler = handler
}