local registry = require("registry")
local yaml     = require("yaml")

-- Handler: list only meta of DocScout extraction groups, returned as YAML string
local function handler(params)
    -- Input params: namespace filter (optional), limit (optional)
    local namespace = params.namespace or ""
    local limit = params.limit and tonumber(params.limit) or 100

    -- Fetch registry snapshot
    local snap, err = registry.snapshot()
    if not snap then
        return yaml.encode({ error = "Failed to get registry snapshot: " .. (err or "unknown error") })
    end

    -- Fetch entries
    local raw_entries
    if namespace ~= "" then
        raw_entries = snap:namespace(namespace)
    else
        raw_entries = snap:entries({ limit = 1000 })
    end

    -- Gather meta information for extraction groups
    local metas = {}
    local total = 0
    for _, entry in ipairs(raw_entries) do
        if entry.meta and entry.meta.type == "docscout.extraction_group" then
            total = total + 1
            if #metas < limit then
                table.insert(metas, {
                    id      = entry.id,
                    name    = entry.meta.name or "",
                    title   = entry.meta.title or "",
                    comment = entry.meta.comment or "",
                    tags    = entry.meta.tags or {}
                })
            end
        end
    end

    -- Determine if more entries exist beyond limit
    local has_more = (total > #metas)

    -- Return YAML string with meta list
    return yaml.encode({
        groups   = metas,
        count    = #metas,
        total    = total,
        has_more = has_more
    })
end

return { handler = handler }