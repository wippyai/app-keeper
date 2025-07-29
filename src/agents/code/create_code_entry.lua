local registry = require('registry')
local governance = require('governance_client')
local code_utils = require('code_utils')

local function handler(params)
    -- --- Input Validation ---
    if not params.namespace or type(params.namespace) ~= 'string' or params.namespace == '' then
        return { success = false, error = 'Missing or invalid required parameter: namespace (string)' }
    end
    if not params.name or type(params.name) ~= 'string' or params.name == '' then
        return { success = false, error = 'Missing or invalid required parameter: name (string)' }
    end
    if not params.kind or not code_utils.CODE_KINDS[params.kind] then
        return {
            success = false,
            error =
            'Missing or invalid required parameter: kind (must be \'function.lua\', \'library.lua\', or \'process.lua\')'
        }
    end
    if not params.source or type(params.source) ~= 'string' then
        -- Allow empty source, but it must be provided as a string
        if params.source == nil then
            return { success = false, error = 'Missing required parameter: source (string)' }
        else
            return { success = false, error = 'Invalid parameter type: source (must be a string)' }
        end
    end
    if params.meta and type(params.meta) ~= 'table' then
        return { success = false, error = 'Invalid optional parameter type: meta (must be a table)' }
    end
    if params.modules and type(params.modules) ~= 'table' then
        return { success = false, error = 'Invalid optional parameter type: modules (must be an array of strings)' }
    end
    if params.imports and type(params.imports) ~= 'table' then
        return { success = false, error = 'Invalid optional parameter type: imports (must be a table map)' }
    end
    if params.method and type(params.method) ~= 'string' then
        return { success = false, error = 'Invalid optional parameter type: method (must be a string)' }
    end

    local entry_id = params.namespace .. ':' .. params.name

    -- --- Check Existence directly using registry.get ---
    local existing_entry = registry.get(entry_id)
    if existing_entry then
        return { success = false, error = 'Entry already exists: ' .. entry_id .. '. Use update tools to modify.' }
    end

    -- --- Prepare Entry Data ---
    local new_entry = {
        id = entry_id,
        kind = params.kind,
        meta = params.meta or {
            comment = entry_id
        },
        data = {
            source = params.source,
            modules = params.modules or nil,
            imports = params.imports or nil,
            method = params.method or nil
        }
    }

    -- --- Create Changeset and Apply ---
    local changes = registry.snapshot():changes()

    changes:create(new_entry)

    local result, err = governance.request_changes(changes)
    if not result then
        return { success = false, error = 'Failed to create code entry: ' .. (err or 'unknown error') }
    end

    -- Calculate source statistics
    local source_length = string.len(params.source)
    local line_count = 1
    for _ in string.gmatch(params.source, '\n') do
        line_count = line_count + 1
    end

    -- --- Return Success ---
    return {
        success = true,
        message = 'Code entry created successfully',
        id = entry_id,
        kind = params.kind,
        version = result.version,
        source_stats = {
            character_count = source_length,
            line_count = line_count
        }
    }
end

return {
    handler = handler
}