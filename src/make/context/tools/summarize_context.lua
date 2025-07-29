-- Summarize Context Tool - LLM-powered summarization of context items by UUIDs
-- @param params Table containing:
--   uuids (array): Array of context UUIDs to retrieve and summarize
--   query (string, optional): Specific question or focus for the summary
--   max_tokens (number, optional): Maximum tokens for summary (default: 500)
-- @return Summarized text

-- Imports
local json = require("json")
local ctx = require("ctx")
local context_reader = require("context_reader")
local llm = require("llm")
local prompt = require("prompt")

-- Constants
local CONSTANTS = {
    DEFAULT_MODEL = "gpt-4.1-mini",
    DEFAULT_MAX_TOKENS = 500,
    DEFAULT_TEMPERATURE = 0.3,
    ERROR_MESSAGES = {
        MISSING_UUIDS = "Missing required parameter: uuids",
        INVALID_UUIDS = "Parameter 'uuids' must be an array",
        EMPTY_UUIDS = "Parameter 'uuids' cannot be empty",
        NO_DATAFLOW = "Cannot access dataflow_id - tool must be called within a dataflow context",
        NO_CONTENT = "No context content found for the provided UUIDs",
        LLM_ERROR = "Failed to generate summary"
    }
}

-- Helper function to format context items for LLM processing
local function format_context_for_llm(context_items)
    if not context_items or #context_items == 0 then
        return ""
    end

    local context_parts = {}

    for i, item in ipairs(context_items) do
        local key = item.key or "unknown"
        local comment = (item.metadata and item.metadata.comment) or ""
        local data_id = item.data_id or "unknown"

        -- Create a clear section header
        table.insert(context_parts, "=== Context Block " .. i .. " ===")
        table.insert(context_parts, "ID: " .. data_id)
        table.insert(context_parts, "Key: " .. key)
        if comment and comment ~= "" then
            table.insert(context_parts, "Description: " .. comment)
        end
        table.insert(context_parts, "")
        table.insert(context_parts, item.content or "")
        table.insert(context_parts, "")
    end

    return table.concat(context_parts, "\n")
end

-- Build summarization prompt
local function build_summarization_prompt(context_content, query, context_count)
    local builder = prompt.new()

    -- System prompt
    local system_prompt = "You are an expert at analyzing and summarizing technical documentation and context information. " ..
                         "Your goal is to create clear, concise, and accurate summaries that capture the essential information."

    if query and query ~= "" then
        system_prompt = system_prompt .. " Pay special attention to information relevant to the user's specific question or focus area."
    end

    builder:add_system(system_prompt)

    -- User prompt with context
    local user_prompt = "Please summarize the following " .. context_count .. " context block(s):\n\n" .. context_content

    if query and query ~= "" then
        user_prompt = user_prompt .. "\n\n**Specific Focus/Question:** " .. query ..
                     "\n\nPlease provide a summary that particularly addresses this question while also covering other key information."
    else
        user_prompt = user_prompt .. "\n\nPlease provide a comprehensive summary of the key information, main concepts, and important details."
    end

    builder:add_user(user_prompt)

    return builder
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

    if not context_items or #context_items == 0 then
        return {
            success = false,
            error = CONSTANTS.ERROR_MESSAGES.NO_CONTENT
        }
    end

    -- Format context for LLM processing
    local context_content = format_context_for_llm(context_items)

    -- Build summarization prompt
    local summarization_prompt = build_summarization_prompt(
        context_content,
        params.query,
        #context_items
    )

    -- Call LLM for summarization
    local max_tokens = params.max_tokens or CONSTANTS.DEFAULT_MAX_TOKENS
    local llm_response = llm.generate(summarization_prompt, {
        model = CONSTANTS.DEFAULT_MODEL,
        temperature = CONSTANTS.DEFAULT_TEMPERATURE,
        max_tokens = max_tokens
    })

    -- Handle LLM errors
    if llm_response.error then
        return {
            success = false,
            error = CONSTANTS.ERROR_MESSAGES.LLM_ERROR .. ": " .. (llm_response.error_message or llm_response.error)
        }
    end

    -- Return the summary with metadata
    local summary_result = {
        summary = llm_response.result,
        metadata = {
            context_blocks_processed = #context_items,
            query_provided = params.query ~= nil and params.query ~= "",
            tokens_used = llm_response.tokens and llm_response.tokens.total_tokens or 0,
            model_used = CONSTANTS.DEFAULT_MODEL
        }
    }

    -- If query was provided, include it in metadata
    if params.query and params.query ~= "" then
        summary_result.metadata.query = params.query
    end

    return summary_result
end

return execute