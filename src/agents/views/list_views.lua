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

    -- Find all virtual page entries
    local entries, err = snapshot:find({
        [".kind"] = "template.jet",
        ["meta.type"] = "view.page"
    })

    if err then
        return {
            success = false,
            error = "Failed to find views: " .. err
        }
    end

    -- Create comprehensive list of views with all metadata
    local views = {}
    for _, entry in ipairs(entries) do
        if entry.meta then
            local parsed_id = registry.parse_id(entry.id)

            -- Create detailed page object with all metadata
            local page = {
                id = parsed_id.name,
                full_id = entry.id,
                namespace = parsed_id.ns,
                name = entry.meta.name or "",
                title = entry.meta.title or "",
                icon = entry.meta.icon or "",
                order = entry.meta.order or 9999,
                group = entry.meta.group or "",
                group_icon = entry.meta.group_icon or "",
                group_order = entry.meta.group_order or 9999,
                description = entry.meta.comment or entry.meta.description or "",
                content_type = entry.meta.content_type or "text/html",
                template_set = entry.data and entry.data.set or "",
                secure = entry.meta.secure or false,
                public = entry.meta.public or false,
                announced = entry.meta.announced or false,
                inline = entry.meta.inline or false,
                space = entry.meta.space or ""
            }

            -- Add resources if available
            if entry.data and entry.data.resources and #entry.data.resources > 0 then
                page.resources = entry.data.resources
            end

            table.insert(views, page)
        end
    end

    -- Sort by order then title for consistent display
    table.sort(views, function(a, b)
        if a.order == b.order then
            return a.title < b.title
        end
        return a.order < b.order
    end)

    -- Return results
    return {
        success = true,
        count = #views,
        views = views
    }
end

return {
    handler = handler
}