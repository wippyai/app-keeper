local registry = require("registry")

-- Code kinds constant
local CODE_KINDS = {
    ["function.lua"] = true,
    ["library.lua"] = true,
    ["process.lua"] = true
}

local function handler(params)
    -- Validate required parameters
    if not params.id then
        return "Error: Missing required parameter: id"
    end

    if not params.line or type(params.line) ~= "number" then
        return "Error: Missing or invalid required parameter: line (must be a number)"
    end

    -- Set default context if not provided
    local context = params.context or 3
    if type(context) ~= "number" or context < 0 then
        context = 3
    end

    -- Get the entry from registry
    local entry, err = registry.get(params.id)
    if not entry then
        return "Error: Code entry not found: " .. (err or params.id)
    end

    -- Check if this is a code-related entry
    if not CODE_KINDS[entry.kind] then
        return "Error: Entry is not a code entry. Kind: " .. (entry.kind or "unknown")
    end

    -- Get source code
    local source = ""
    if entry.source then
        source = entry.source
    elseif entry.data and entry.data.source then
        source = entry.data.source
    else
        return "Error: Entry does not have source code"
    end

    -- Split source into lines
    local lines = {}
    for line in source:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    -- Calculate start and end line numbers with bounds checking
    local start_line = math.max(1, params.line - context)
    local end_line = math.min(#lines, params.line + context)

    -- Build output string with line numbers and target marker
    local result_lines = {}
    for i = start_line, end_line do
        local line_content = lines[i] or ""
        local prefix = ""
        
        if i == params.line then
            prefix = ">>> "
        end
        
        table.insert(result_lines, i .. ": " .. prefix .. line_content)
    end

    -- Join all lines with newlines
    return table.concat(result_lines, "\n")
end

return {
    handler = handler
}