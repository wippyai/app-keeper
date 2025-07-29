local registry = require('registry')

-- Common constant for code kinds
local CODE_KINDS = {
    ['function.lua'] = true,
    ['library.lua'] = true,
    ['process.lua'] = true
}

-- Format an entry as source file with proper formatting
local function format_entry_as_source(entry)
    if not entry then
        return nil
    end

    -- Format modules if present
    local modules_str = ''
    if entry.data and entry.data.modules and #entry.data.modules > 0 then
        modules_str = '-- Modules:\n-- ' .. table.concat(entry.data.modules, ', ') .. '\n\n'
    end

    -- Format imports if present
    local imports_str = ''
    local imports = entry.data and entry.data.imports or {}
    if next(imports) then
        imports_str = '-- Imports:\n'
        for alias, path in pairs(imports) do
            imports_str = imports_str .. '-- ' .. alias .. ' = ' .. path .. '\n'
        end
        imports_str = imports_str .. '\n'
    end

    -- Get source code
    local source = ''
    if entry.data and entry.data.source then
        source = entry.data.source
    end

    -- Format return value
    local result = '<source_file id="' .. entry.id .. '">\n'
    result = result .. '-- Kind: ' .. entry.kind .. '\n'
    if entry.meta and entry.meta.type then
        result = result .. '-- Type: ' .. entry.meta.type .. '\n'
    end
    result = result .. modules_str
    result = result .. imports_str
    result = result .. '<source_code>\n'
    result = result .. source
    result = result .. '</source_code>\n'
    result = result .. '</source_file>'

    return result
end

-- Get an entry by ID with error handling
local function get_entry(id)
    local entry, err = registry.get(id)
    if not entry then
        return nil, 'Code entry not found: ' .. (err or id)
    end

    -- Verify it's a code entry
    if not CODE_KINDS[entry.kind] then
        return nil, 'Entry is not a code entry. Kind: ' .. (entry.kind or 'unknown')
    end

    return entry
end

-- Export functions and constants
return {
    CODE_KINDS = CODE_KINDS,
    format_entry_as_source = format_entry_as_source,
    get_entry = get_entry
}