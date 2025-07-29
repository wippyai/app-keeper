local registry = require("registry")
local yaml     = require("yaml")

-- Handler: read full extraction group entries for specified IDs, returns YAML string
local function handler(params)
    -- Validate input
    if not params or type(params) ~= "table" then
        return yaml.encode({ error = "Invalid parameters: expected an object." })
    end
    if not params.ids or type(params.ids) ~= "table" or #params.ids == 0 then
        return yaml.encode({ error = "Missing or invalid required parameter: ids (non-empty array of strings)" })
    end

    -- Fetch registry snapshot
    local snap, err = registry.snapshot()
    if not snap then
        return yaml.encode({ error = "Failed to get registry snapshot: " .. (err or "unknown error") })
    end

    -- Collect full entry info for each specified ID
    local entries = {}
    for _, entry_id in ipairs(params.ids) do
        if type(entry_id) ~= "string" or entry_id == "" then
            table.insert(entries, { id = entry_id, error = "Invalid entry ID; expected non-empty string." })
        else
            local entry, err_get = snap:get(entry_id)
            if not entry then
                table.insert(entries, { id = entry_id, error = "Entry not found." })
            elseif entry.kind ~= "registry.entry" or not entry.meta or entry.meta.type ~= "docscout.extraction_group" then
                table.insert(entries, { id = entry_id, error = "Not a DocScout extraction group." })
            else
                -- Insert the full entry: id, kind, meta, data
                table.insert(entries, {
                    id   = entry.id,
                    kind = entry.kind,
                    meta = entry.meta,
                    data = entry.data
                })
            end
        end
    end

    -- Return YAML string containing an array of full entry objects
    return yaml.encode({ groups = entries })
end

return { handler = handler }