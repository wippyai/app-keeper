-- View Context Tool - Retrieve and format context items by UUIDs
-- @param params Table containing:
--   uuids (array): Array of context UUIDs to retrieve and view
-- @return Formatted string containing the context items

-- Imports
local json = require("json")
local ctx = require("ctx")
local context_reader = require("context_reader")

-- Constants
local CONSTANTS = {
    ERROR_MESSAGES = {
        MISSING_UUIDS = "Missing required parameter: uuids",
        INVALID_UUIDS = "Parameter 'uuids' must be an array",
        EMPTY_UUIDS = "Parameter 'uuids' cannot be empty",
        NO_DATAFLOW = "Cannot access dataflow_id - tool must be called within a dataflow context"
    }
}

-- Helper function to format context items (similar to prompt_builder)
local function format_context_items_to_string(context_items)
    if not context_items or #context_items == 0 then
        return "No context items found."
    end

    local context_parts = {}

    for i, item in ipairs(context_items) do
        local created_at = item.created_at or (item.metadata and item.metadata.created_at) or "unknown"
        local key = item.key or "unknown"
        local comment = (item.metadata and item.metadata.comment) or ""
        local item_type_attr = item.type or "unknown"
        local data_id_attr = item.data_id or "nil"

        -- Escape comment for XML attributes
        local comment_attr_str = ""
        if comment and comment ~= "" then
            comment = string.gsub(comment, "&", "&amp;")
            comment = string.gsub(comment, "<", "&lt;")
            comment = string.gsub(comment, ">", "&gt;")
            comment = string.gsub(comment, "\"", "&quot;")
            comment_attr_str = string.format(' comment="%s"', comment)
        end

        -- Add separator between items (but not before first)
        if i > 1 then
            table.insert(context_parts, "\n\n")
        end

        -- Add context opening tag
        table.insert(context_parts, string.format('<context id="%s" key="%s" created="%s"%s>',
            data_id_attr, key, created_at, comment_attr_str))
        table.insert(context_parts, "\n")

        -- Add content
        table.insert(context_parts, item.content or "")

        -- Add closing tag
        table.insert(context_parts, "\n</context>")
    end

    return table.concat(context_parts)
end

-- Main implementation
local function execute(params, tool_session_context)
    -- Validate required parameters
    if not params.uuids then
        return {
            success = false,
            error = CONSTANTS.ERROR_MESSAGES.MISSING_UUIDS
        }
    end

    if type(params.uuids) ~= "table" then
        return {
            success = false,
            error = CONSTANTS.ERROR_MESSAGES.INVALID_UUIDS
        }
    end

    if #params.uuids == 0 then
        return {
            success = false,
            error = CONSTANTS.ERROR_MESSAGES.EMPTY_UUIDS
        }
    end

    -- Get dataflow_id from context
    local dataflow_id = ctx.get("dataflow_id")
    if not dataflow_id then
        return {
            success = false,
            error = CONSTANTS.ERROR_MESSAGES.NO_DATAFLOW
        }
    end

    -- Load context items by UUIDs
    local context_items = context_reader.load_private_context_ids(dataflow_id, params.uuids)

    -- Format context items as string
    local formatted_content = format_context_items_to_string(context_items)

    -- Return the formatted content as a string (tool result)
    return formatted_content
end

return execute