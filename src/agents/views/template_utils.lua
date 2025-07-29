local M = {}

-- Pattern constants
M.PATTERNS = {
    BLOCK_START = "{{%s*block%s+([%w_]+)%s*(%b())%s*}}",
    BLOCK_END = "{{%s*end%s*}}",
    YIELD = "{{%s*yield%s+([%w_]+)%s*(%b())%s*}}",
    YIELD_WITH_CONTENT = "{{%s*yield%s+([%w_]+)%s*(%b())%s*content%s*}}",
    EXTENDS = "{{%s*extends%s+\"([^\"]+)\"%s*}}",
    IMPORT = "{{%s*import%s+\"([^\"]+)\"%s*}}"
}

-- Get all blocks defined in a template
-- @param source string: The template source code
-- @return table: Array of block objects with name, parameters, content, etc.
function M.get_blocks(source)
    if not source then return {} end

    local blocks = {}
    local pos = 1

    while true do
        -- Find block start
        local block_start, block_end, block_name, block_params = string.find(source, M.PATTERNS.BLOCK_START, pos)
        if not block_start then break end

        -- Find matching end tag
        local content_start = block_end + 1
        local content_end, end_pos = M.find_matching_end(source, content_start)

        if not content_end then
            -- Malformed template
            break
        end

        -- Clean up parameters (remove parentheses)
        block_params = string.sub(block_params, 2, -2)

        -- Extract content
        local content = string.sub(source, content_start, content_end)

        -- Add to blocks table
        table.insert(blocks, {
            name = block_name,
            parameters = block_params,
            content = content,
            start_pos = block_start,
            end_pos = end_pos,
            full_block = string.sub(source, block_start, end_pos)
        })

        -- Move position forward
        pos = end_pos + 1
    end

    return blocks
end

-- Find a specific block by name
-- @param source string: The template source code
-- @param block_name string: The name of the block to find
-- @return table|nil: Block object or nil if not found
function M.get_block(source, block_name)
    local blocks = M.get_blocks(source)

    for _, block in ipairs(blocks) do
        if block.name == block_name then
            return block
        end
    end

    return nil
end

-- Find all yield statements in a template
-- @param source string: The template source code
-- @return table: Array of yield objects with name, parameters, etc.
function M.get_yields(source)
    if not source then return {} end

    local yields = {}
    local pos = 1

    -- Standard yields
    while true do
        local yield_start, yield_end, yield_name, yield_params =
            string.find(source, M.PATTERNS.YIELD, pos)

        if not yield_start then break end

        -- Check if this is a yield with content
        local with_content = string.find(source, "content%s*}}", yield_end - 10, yield_end)

        if not with_content then
            -- Clean up parameters (remove parentheses)
            yield_params = string.sub(yield_params, 2, -2)

            table.insert(yields, {
                name = yield_name,
                parameters = yield_params,
                start_pos = yield_start,
                end_pos = yield_end,
                has_content = false
            })
        end

        -- Move position forward
        pos = yield_end + 1
    end

    -- Yields with content blocks
    pos = 1
    while true do
        local yield_start, yield_end, yield_name, yield_params =
            string.find(source, M.PATTERNS.YIELD_WITH_CONTENT, pos)

        if not yield_start then break end

        -- Find matching end tag
        local content_start = yield_end + 1
        local content_end, end_pos = M.find_matching_end(source, content_start)

        if content_end then
            -- Clean up parameters (remove parentheses)
            yield_params = string.sub(yield_params, 2, -2)

            -- Extract content
            local content = string.sub(source, content_start, content_end)

            table.insert(yields, {
                name = yield_name,
                parameters = yield_params,
                content = content,
                start_pos = yield_start,
                end_pos = end_pos,
                has_content = true
            })

            -- Move position forward
            pos = end_pos + 1
        else
            -- Malformed yield with content, skip it
            pos = yield_end + 1
        end
    end

    return yields
end

-- Find yields for a specific block
-- @param source string: The template source code
-- @param block_name string: The name of the block to find yields for
-- @return table: Array of yield objects for the specified block
function M.get_block_yields(source, block_name)
    local yields = M.get_yields(source)
    local results = {}

    for _, yield in ipairs(yields) do
        if yield.name == block_name then
            table.insert(results, yield)
        end
    end

    return results
end

-- Find the matching end tag for blocks, yields with content, etc.
-- @param source string: The template source code
-- @param start_pos number: Position to start searching from
-- @return number, number: Content end position and end tag end position
function M.find_matching_end(source, start_pos)
    local nesting_level = 1
    local pos = start_pos
    local content_end, end_pos

    while nesting_level > 0 and pos < #source do
        -- Find next block/yield start or end
        local next_start = string.find(source, "{{%s*block", pos)
        if not next_start then
            next_start = string.find(source, "{{%s*yield%s+[%w_]+%s*%b()%s*content", pos)
        end

        local next_end = string.find(source, M.PATTERNS.BLOCK_END, pos)

        if not next_end then
            -- No matching end found
            return nil, nil
        end

        if next_start and next_start < next_end then
            -- Found a nested block/yield with content
            nesting_level = nesting_level + 1
            -- FIX: Advance position beyond the start tag, not just to it
            -- Find the end of this block start tag to avoid re-matching it
            local _, block_tag_end = string.find(source, "{{%s*block%s+[%w_]+%s*%b()%s*}}", next_start)
            if not block_tag_end then
                -- If we can't find the complete block tag, advance at least past "{{block"
                pos = next_start + 7
            else
                pos = block_tag_end + 1
            end
        else
            -- Found an end tag
            nesting_level = nesting_level - 1
            if nesting_level == 0 then
                content_end = next_end - 1
                local _, end_tag_end = string.find(source, M.PATTERNS.BLOCK_END, next_end)
                end_pos = end_tag_end
            end
            pos = next_end + 1
        end
    end

    return content_end, end_pos
end

-- Parse block parameters into a structured format
-- @param params_str string: The parameters string from a block/yield
-- @return table: Structured parameters with names and default values
function M.parse_parameters(params_str)
    if not params_str or params_str == "" then
        return {}
    end

    local params = {}
    local param_pattern = "([%w_]+)%s*=%s*([^,]+)"
    local simple_param_pattern = "([%w_]+)"

    -- Split parameters by commas, handling quoted strings properly
    local parts = {}
    local current_part = ""
    local in_quotes = false
    local quote_char = nil

    for i = 1, #params_str do
        local char = string.sub(params_str, i, i)

        if (char == '"' or char == "'") and (i == 1 or string.sub(params_str, i-1, i-1) ~= "\\") then
            if not in_quotes then
                in_quotes = true
                quote_char = char
            elseif char == quote_char then
                in_quotes = false
                quote_char = nil
            end
        end

        if char == "," and not in_quotes then
            table.insert(parts, current_part)
            current_part = ""
        else
            current_part = current_part .. char
        end
    end

    if current_part ~= "" then
        table.insert(parts, current_part)
    end

    -- Process each parameter
    for _, part in ipairs(parts) do
        part = string.gsub(part, "^%s*(.-)%s*$", "%1") -- Trim

        local name, value = string.match(part, param_pattern)
        if name and value then
            params[name] = value
        else
            local simple_name = string.match(part, simple_param_pattern)
            if simple_name then
                params[simple_name] = true
            end
        end
    end

    return params
end

-- Format parameters table back to string format
-- @param params table: Parameter name/value pairs
-- @return string: Formatted parameters string
function M.format_parameters(params)
    if not params or next(params) == nil then
        return ""
    end

    local parts = {}

    for name, value in pairs(params) do
        if value == true then
            table.insert(parts, name)
        else
            table.insert(parts, name .. "=" .. tostring(value))
        end
    end

    return table.concat(parts, ", ")
end

-- Check if a template extends another template
-- @param source string: The template source code
-- @return string|nil: Name of the extended template or nil
function M.get_extends(source)
    if not source then return nil end

    local _, _, extends_name = string.find(source, M.PATTERNS.EXTENDS)
    return extends_name
end

-- Get all imported templates
-- @param source string: The template source code
-- @return table: Array of imported template names
function M.get_imports(source)
    if not source then return {} end

    local imports = {}
    local pos = 1

    while true do
        local _, _, import_name = string.find(source, M.PATTERNS.IMPORT, pos)
        if not import_name then break end

        table.insert(imports, import_name)
        pos = pos + 1
    end

    return imports
end

-- Create a new block with content
-- @param name string: Block name
-- @param content string: Block content
-- @param params string|table: Parameters as string or table
-- @return string: Formatted block code
function M.create_block(name, content, params)
    if type(params) == "table" then
        params = M.format_parameters(params)
    elseif not params then
        params = ""
    end

    return string.format("{{ block %s(%s) }}\n%s\n{{ end }}", name, params, content)
end

-- Create a yield statement for a block
-- @param name string: Block name to yield
-- @param params string|table: Parameters as string or table
-- @return string: Formatted yield code
function M.create_yield(name, params)
    if type(params) == "table" then
        params = M.format_parameters(params)
    elseif not params then
        params = ""
    end

    return string.format("{{ yield %s(%s) }}", name, params)
end

-- Add a block to a template at the specified position
-- @param source string: The template source code
-- @param block string: The block code to add
-- @param position string: "start", "end", or "after_extends"
-- @return string: Updated template source
function M.add_block_to_source(source, block, position)
    if position == "start" then
        return block .. "\n\n" .. source
    elseif position == "after_extends" then
        local extends_pattern = M.PATTERNS.EXTENDS
        local start_pos, end_pos = string.find(source, extends_pattern)

        if start_pos then
            return string.sub(source, 1, end_pos) ..
                  "\n\n" .. block ..
                  string.sub(source, end_pos + 1)
        else
            -- If no extends statement, add to the beginning
            return block .. "\n\n" .. source
        end
    else
        -- Add at the end of the file (default)
        return source .. "\n\n" .. block
    end
end

-- Remove a block from template source
-- @param source string: The template source code
-- @param block_name string: Name of the block to remove
-- @return string, boolean: Updated source and success status
function M.remove_block_from_source(source, block_name)
    local block = M.get_block(source, block_name)

    if not block then
        return source, false
    end

    -- Remove the block
    local updated_source =
        string.sub(source, 1, block.start_pos - 1) ..
        string.sub(source, block.end_pos + 1)

    -- Clean up any double newlines that might be left
    updated_source = string.gsub(updated_source, "\n\n\n+", "\n\n")

    return updated_source, true
end

-- Update a block in template source
-- @param source string: The template source code
-- @param block_name string: Name of the block to update
-- @param new_content string: New content for the block
-- @param new_params string|table: Optional new parameters for the block
-- @return string, boolean: Updated source and success status
function M.update_block_in_source(source, block_name, new_content, new_params)
    local block = M.get_block(source, block_name)

    if not block then
        return source, false
    end

    -- Use current parameters if new ones not provided
    local params = block.parameters
    if new_params then
        if type(new_params) == "table" then
            params = M.format_parameters(new_params)
        else
            params = new_params
        end
    end

    -- Create the updated block
    local new_block = M.create_block(block_name, new_content, params)

    -- Replace the old block with the new one
    local updated_source =
        string.sub(source, 1, block.start_pos - 1) ..
        new_block ..
        string.sub(source, block.end_pos + 1)

    return updated_source, true
end

-- Check if a block has references (yields)
-- @param source string: The template source code
-- @param block_name string: Name of the block to check
-- @return boolean: True if references exist, false otherwise
function M.has_block_references(source, block_name)
    local yields = M.get_block_yields(source, block_name)
    return #yields > 0
end

-- Utility to escape Lua pattern special characters
-- @param str string: String to escape
-- @return string: Escaped string safe for pattern matching
function M.escape_pattern(str)
    local matches = {
        ["^"] = "%^", ["$"] = "%$", ["("] = "%(", [")"] = "%)",
        ["%"] = "%%", ["."] = "%.", ["["] = "%[", ["]"] = "%]",
        ["*"] = "%*", ["+"] = "%+", ["-"] = "%-", ["?"] = "%?"
    }

    return string.gsub(str, ".", matches)
end

return M