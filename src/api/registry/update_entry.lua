local http = require("http")
local json = require("json")
local registry = require("registry")
local client = require("governance_client")

local function deep_copy(original)
    local copy
    if type(original) == "table" then
        copy = {}
        for key, value in pairs(original) do
            copy[key] = deep_copy(value)
        end
    else
        copy = original
    end
    return copy
end

-- Check if a table is empty (no keys)
local function is_empty_table(t)
    if type(t) ~= "table" then
        return false
    end
    return next(t) == nil
end

-- Check if a table is a JSON array (consecutive integer keys starting from 1)
local function is_json_array(t)
    if type(t) ~= "table" then
        return false
    end

    -- Get the length using Lua's # operator
    local n = #t

    -- Empty table is not an array
    if n == 0 then
        return false
    end

    -- Check if all keys from 1 to n exist and there are no other keys
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end

    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or math.floor(k) ~= k then
            return false
        end
    end

    return true
end

-- We need to detect when a field is explicitly provided as empty
-- and handle arrays specially
local function handle_explicit_fields(target, source)
    local result = deep_copy(target)

    -- First, check for explicit empty structures in the source
    -- These should be removed (set to nil) in the result
    for key, value in pairs(source) do
        if type(value) == "table" and is_empty_table(value) then
            -- An empty table/array was explicitly provided, so remove this field
            result[key] = nil
        elseif type(value) == "table" and type(result[key]) == "table" then
            -- Check if either source or target is a JSON array
            local source_is_array = is_json_array(value)
            local target_is_array = is_json_array(result[key])

            if source_is_array or target_is_array then
                -- If either is an array, replace instead of merge
                result[key] = deep_copy(value)
            else
                -- Both are regular tables/maps, recursively merge
                result[key] = handle_explicit_fields(result[key], value)
            end
        else
            -- Normal field update
            result[key] = value
        end
    end

    return result
end

local function handler()
    local res = http.response()
    local req = http.request()
    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    local entry_id = req:query("id")
    if not entry_id or entry_id == "" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing required query parameter: id"
        })
        return
    end

    if not req:is_content_type(http.CONTENT.JSON) then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Request must be application/json"
        })
        return
    end

    local update_data, err = req:body_json()
    if err then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to parse JSON body: " .. err
        })
        return
    end

    local should_merge = update_data.merge ~= false
    local updates_made = false

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

    local entry, err = snapshot:get(entry_id)
    if not entry then
        res:set_status(http.STATUS.NOT_FOUND)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Entry not found: " .. entry_id
        })
        return
    end

    local updated_entry = {
        id = entry.id,
        kind = entry.kind,
        meta = deep_copy(entry.meta) or {},
        data = deep_copy(entry.data) or {}
    }

    if update_data.kind then
        updated_entry.kind = update_data.kind
        updates_made = true
    end

    if update_data.meta then
        if should_merge then
            -- Use our special handler for explicit empty fields
            updated_entry.meta = handle_explicit_fields(updated_entry.meta, update_data.meta)
        else
            updated_entry.meta = update_data.meta
        end
        updates_made = true
    end

    if update_data.data then
        if should_merge then
            -- Use our special handler for explicit empty fields
            updated_entry.data = handle_explicit_fields(updated_entry.data, update_data.data)
        else
            updated_entry.data = update_data.data
        end
        updates_made = true
    end

    if not updates_made then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "No updates provided (need at least one of: kind, meta, data)"
        })
        return
    end

    -- Create a changeset using the snapshot
    local changes = snapshot:changes()
    -- Apply the update to the changeset
    changes:update(updated_entry)
    -- Request changes through the governance client
    local result, err = client.request_changes(changes, {}, 30000)

    if not result then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to apply registry changes: " .. (err or "unknown error")
        })
        return
    end

    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = "Entry updated successfully",
        id = entry_id,
        kind = updated_entry.kind,
        version = result.version,
        merge = should_merge,
        updated = {
            kind = update_data.kind ~= nil,
            meta = update_data.meta ~= nil,
            data = update_data.data ~= nil
        }
    })
end

return {
    handler = handler
}