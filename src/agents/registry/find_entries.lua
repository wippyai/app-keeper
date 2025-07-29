local json = require("json")
local registry = require("registry")

-- Pattern matching function with % wildcards
local function match_pattern(str, pattern)
    if not pattern or pattern == "" then
        return true
    end

    -- Replace % with Lua pattern .*
    local lua_pattern = pattern:gsub("%%", ".*")
    return string.match(str, lua_pattern) ~= nil
end

local function handler(params)
    -- Set defaults for optional parameters
    local limit = params.limit or 100
    local offset = params.offset or 0

    -- Get a snapshot of the registry
    local snapshot, err = registry.snapshot()
    if not snapshot then
        return {
            success = false,
            error = "Failed to get registry snapshot: " .. (err or "unknown error")
        }
    end

    -- Get all entries (no criteria - just get everything)
    local all_entries, err = snapshot:entries({ limit = 1000 })
    if err then
        return {
            success = false,
            error = "Failed to get registry entries: " .. err
        }
    end

    -- Filter entries based on parameters
    local filtered_entries = {}

    for _, entry in ipairs(all_entries) do
        local ns, name

        -- Extract namespace and name
        if type(entry.id) == "string" then
            ns, name = entry.id:match("([^:]+):(.+)")
        elseif type(entry.id) == "table" then
            ns, name = entry.id.ns, entry.id.name
        end

        -- Apply filters
        local matches = true

        -- Namespace filter
        if params.namespace and not match_pattern(ns or "", params.namespace) then
            matches = false
        end

        -- Name filter
        if params.name and not match_pattern(name or "", params.name) then
            matches = false
        end

        -- Kind filter with meta.type fallback
        if params.kind then
            local kind_match = match_pattern(entry.kind or "", params.kind)
            local meta_type_match = false
            -- Check meta.type if kind is registry.entry
            if entry.kind == "registry.entry" and entry.meta and entry.meta.type then
                 meta_type_match = match_pattern(entry.meta.type, params.kind)
            end

            -- If neither the direct kind nor the meta.type fallback matches, set matches to false
            if not kind_match and not meta_type_match then
                matches = false
            end
        end

        if matches then
            table.insert(filtered_entries, entry)
        end
    end

    -- Check if we got any entries
    if #filtered_entries == 0 then
        return {
            success = true,
            entries = {},
            total = 0,
            message = "No entries found matching the filters"
        }
    end

    -- Apply pagination
    local paged_entries = {}
    local total_count = #filtered_entries

    -- Validate offset
    if offset >= total_count then
        offset = math.max(0, total_count - 1)
    end

    -- Determine end index
    local end_index = math.min(offset + limit, total_count)

    -- Extract entries for the current page
    for i = offset + 1, end_index do
        local entry = filtered_entries[i]

        -- Parse ID to get namespace and name parts
        local ns, name
        if type(entry.id) == "string" then
            ns, name = entry.id:match("([^:]+):(.+)")
        elseif type(entry.id) == "table" then
            ns, name = entry.id.ns, entry.id.name
        end

        -- Create a result entry
        local result = {
            id = type(entry.id) == "string" and entry.id or (ns .. ":" .. name),
            namespace = ns or "",
            name = name or "",
            kind = entry.kind,
            meta = entry.meta or {}
        }

        table.insert(paged_entries, result)
    end

    -- Sort entries by namespace first, then name
    table.sort(paged_entries, function(a, b)
        if a.namespace == b.namespace then
            return a.name < b.name
        else
            return a.namespace < b.namespace
        end
    end)

    -- Return success response with pagination info
    return {
        success = true,
        entries = paged_entries,
        total = total_count,
        offset = offset,
        limit = limit,
        has_more = end_index < total_count,
        namespace = params.namespace,
        name = params.name,
        kind = params.kind
    }
end

return {
    handler = handler
}
