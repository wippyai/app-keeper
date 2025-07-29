local registry = require('registry')
local governance = require('governance_client')

-- Allowed code kinds
local CODE_KINDS = {
    ['function.lua'] = true,
    ['library.lua'] = true,
    ['process.lua'] = true
}

-- Helper function to merge two tables (shallow merge)
local function table_merge(t1, t2)
    local result = {}
    -- Copy t1 first
    for k, v in pairs(t1) do
        result[k] = v
    end
    -- Then overwrite/add from t2
    for k, v in pairs(t2) do
        result[k] = v
    end
    return result
end

local function handler(params)
    -- --- Input Validation ---
    if not params.id or type(params.id) ~= 'string' then
        return { success = false, error = 'Missing or invalid required parameter: id (string)' }
    end
    if not params.metadata or type(params.metadata) ~= 'table' then
        return { success = false, error = 'Missing or invalid required parameter: metadata (table)' }
    end
    -- overwrite is optional, defaults to false
    local overwrite = params.overwrite or false
    if type(overwrite) ~= 'boolean' then
        return { success = false, error = 'Invalid optional parameter type: overwrite (must be boolean)' }
    end

    -- --- Get Existing Entry directly ---
    local entry = registry.get(params.id)
    if not entry then
        return { success = false, error = 'Code entry not found: ' .. params.id }
    end

    -- Verify it's a code entry
    if not CODE_KINDS[entry.kind] then
        return { success = false, error = 'Entry is not a code entry. Kind: ' ..
        (entry.kind or 'unknown') .. '. Cannot update metadata.' }
    end

    -- --- Calculate New Metadata ---
    local existing_meta = entry.meta or {}
    local new_meta

    if overwrite then
        new_meta = params.metadata                             -- Replace entirely
    else
        new_meta = table_merge(existing_meta, params.metadata) -- Merge
    end

    -- --- Prepare Updated Entry ---
    -- Only update the meta field, keep everything else the same
    local updated_entry_data = {
        id = entry.id,
        kind = entry.kind,       -- Must match existing kind
        meta = new_meta,         -- The updated metadata
        source = entry.source,   -- Keep original source
        modules = entry.modules, -- Keep original modules
        imports = entry.imports, -- Keep original imports
        method = entry.method,   -- Keep original method
        data = entry.data        -- Keep original data (if any)
    }

    -- --- Create Changeset and Apply ---
    local changes = registry.snapshot():changes()
    changes:update(updated_entry_data)

    local result, err_apply = governance.request_changes(changes)
    if not result then
        return { success = false, error = 'Failed to update code entry metadata: ' .. (err_apply or 'unknown error') }
    end

    -- --- Return Success ---
    return {
        success = true,
        message = 'Code entry metadata updated successfully',
        id = params.id,
        update_mode = overwrite and 'overwrite' or 'merge',
        version = result.version
    }
end

return {
    handler = handler
}