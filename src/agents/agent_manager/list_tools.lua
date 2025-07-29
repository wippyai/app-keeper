local registry = require("registry")
local json = require("json")
local llm = require("llm")

-- Tool discovery and semantic search functionality
-- Provides comprehensive listing of all available tools with optional semantic search
local function handler(params)
    -- Fallback text search function for when LLM semantic search fails
    local function fallback_text_search(tools, query, limit, response)
        local filtered_tools = {}
        local query_lower = query:lower()
        
        -- Simple text matching on tool descriptions and names
        for _, tool in ipairs(tools) do
            local matches = false
            
            -- Check if query matches tool name or description
            if tool.name and tool.name:lower():find(query_lower, 1, true) then
                matches = true
            elseif tool.description and tool.description:lower():find(query_lower, 1, true) then
                matches = true
            elseif tool.id and tool.id:lower():find(query_lower, 1, true) then
                matches = true
            end
            
            if matches then
                -- Add a simple relevance score based on match position
                tool.relevance_score = 0.5  -- Default fallback score
                tool.relevance_reasoning = "Text match fallback (LLM unavailable)"
                table.insert(filtered_tools, tool)
            end
        end
        
        -- Sort by name since we don't have sophisticated relevance scoring
        table.sort(filtered_tools, function(a, b)
            return a.name < b.name
        end)
        
        -- Apply limit
        if limit and limit < #filtered_tools then
            local limited_tools = {}
            for i = 1, limit do
                table.insert(limited_tools, filtered_tools[i])
            end
            filtered_tools = limited_tools
        end
        
        response.success = true
        response.tools = filtered_tools
        response.semantic_search = false  -- Mark as fallback
        response.fallback_used = true
        return response
    end

    -- Initialize response structure
    local response = {
        success = false,
        tools = {},
        error = nil,
        total_count = 0,
        query_used = nil,
        semantic_search = false
    }

    -- Validate and set default parameters
    params = params or {}
    local query = params.query
    local limit = params.limit
    local include_schemas = params.include_schemas == true

    -- Set default limit based on whether query is provided
    if not limit then
        if query and type(query) == "string" and query ~= "" then
            limit = 50  -- Default limit for semantic search
        else
            limit = nil  -- No limit for full listing
        end
    end

    -- Validate limit parameter
    if limit and (type(limit) ~= "number" or limit < 1) then
        response.error = "Invalid limit parameter: must be a positive integer"
        return response
    end

    -- Validate query parameter
    if query and type(query) ~= "string" then
        response.error = "Invalid query parameter: must be a string"
        return response
    end

    -- Clean up query
    if query then
        query = query:gsub("^%s+", ""):gsub("%s+$", "")  -- Trim whitespace
        if query == "" then
            query = nil
        end
    end

    -- Query registry for all tool entries
    local tool_entries, err = registry.find({
        [".kind"] = "function.lua",
        ["meta.type"] = "tool"
    })

    if err then
        response.error = "Failed to query registry for tools: " .. tostring(err)
        return response
    end

    if not tool_entries or #tool_entries == 0 then
        response.success = true
        response.tools = {}
        response.total_count = 0
        response.query_used = query
        return response
    end

    -- Extract tool information from registry entries
    local tools = {}
    for _, entry in ipairs(tool_entries) do
        -- Extract namespace and name from ID
        local namespace, name
        if type(entry.id) == "string" then
            namespace, name = entry.id:match("([^:]+):(.+)")
        end

        -- Build tool object
        local tool = {
            id = entry.id,
            name = name or "unknown",
            namespace = namespace or "unknown",
            description = "",
            kind = entry.kind
        }

        -- Extract description from metadata
        if entry.meta then
            if entry.meta.llm_description then
                tool.description = entry.meta.llm_description
            elseif entry.meta.description then
                tool.description = entry.meta.description
            elseif entry.meta.comment then
                tool.description = entry.meta.comment
            end
        end

        -- Include schema if requested
        if include_schemas and entry.meta and entry.meta.input_schema then
            if type(entry.meta.input_schema) == "string" then
                local schema, decode_err = json.decode(entry.meta.input_schema)
                if not decode_err then
                    tool.input_schema = schema
                else
                    tool.input_schema_raw = entry.meta.input_schema
                end
            else
                tool.input_schema = entry.meta.input_schema
            end
        end

        table.insert(tools, tool)
    end

    response.total_count = #tools

    -- If no query provided, return all tools (with optional limit)
    if not query then
        -- Sort tools by namespace, then by name for consistent ordering
        table.sort(tools, function(a, b)
            if a.namespace == b.namespace then
                return a.name < b.name
            else
                return a.namespace < b.namespace
            end
        end)

        -- Apply limit if specified
        if limit and limit < #tools then
            local limited_tools = {}
            for i = 1, limit do
                table.insert(limited_tools, tools[i])
            end
            tools = limited_tools
        end

        response.success = true
        response.tools = tools
        response.query_used = nil
        response.semantic_search = false
        return response
    end

    -- Perform semantic search using LLM
    response.query_used = query
    response.semantic_search = true

    -- Create LLM prompt for relevance scoring
    local tool_descriptions = {}
    for i, tool in ipairs(tools) do
        table.insert(tool_descriptions, string.format(
            "%d. %s - %s (namespace: %s)",
            i, tool.id, tool.description or "No description", tool.namespace
        ))
    end

    local tools_text = table.concat(tool_descriptions, "\n")

    local relevance_schema = {
        type = "object",
        properties = {
            relevant_tools = {
                type = "array",
                description = "Array of tool relevance scores ordered by relevance (highest first)",
                items = {
                    type = "object",
                    properties = {
                        tool_index = {
                            type = "integer",
                            description = "1-based index of the tool in the provided list"
                        },
                        relevance_score = {
                            type = "number",
                            description = "Relevance score from 0.0 to 1.0 (1.0 = highly relevant, 0.0 = not relevant)"
                        },
                        reasoning = {
                            type = "string",
                            description = "Brief explanation of why this tool is relevant to the query"
                        }
                    },
                    required = {"tool_index", "relevance_score", "reasoning"},
                    additionalProperties = false
                }
            }
        },
        required = {"relevant_tools"},
        additionalProperties = false
    }

    local llm_prompt = string.format([[
You are analyzing tools to find the most relevant ones for a user query.

User Query: %s

Available Tools:
%s

Instructions:
1. Analyze each tool's ID, description, and namespace against the user query
2. Score each tool's relevance from 0.0 to 1.0 based on how well it matches the query intent
3. Only include tools with relevance score >= 0.1
4. Order results by relevance score (highest first)
5. Limit to top %d most relevant tools
6. Provide brief reasoning for each tool's relevance

Focus on:
- Functional similarity to the query
- Keyword matches in description
- Namespace relevance
- Tool purpose alignment with query intent
]], query, tools_text, limit or 50)

    -- Attempt LLM semantic search with proper error handling
    local llm_response, llm_err = llm.structured_output(
        relevance_schema,
        llm_prompt,
        { model = "gpt-4o-mini", temperature = 0.1 }
    )

    -- Enhanced error handling for LLM failures
    if llm_err then
        -- Direct error from LLM library (second return value)
        response.error = "LLM semantic analysis failed: " .. tostring(llm_err)
        -- Fallback to simple text search
        return fallback_text_search(tools, query, limit, response)
    end

    if not llm_response then
        response.error = "LLM semantic analysis failed: No response received from LLM"
        -- Fallback to simple text search
        return fallback_text_search(tools, query, limit, response)
    end

    if llm_response.error then
        -- Extract detailed error information
        local error_msg = "LLM semantic analysis failed"
        if llm_response.error_message then
            error_msg = error_msg .. ": " .. llm_response.error_message
        elseif llm_response.error then
            error_msg = error_msg .. ": " .. tostring(llm_response.error)
        end
        
        -- Add additional debugging info if available
        if llm_response.finish_reason then
            error_msg = error_msg .. " (finish_reason: " .. llm_response.finish_reason .. ")"
        end
        
        response.error = error_msg
        -- Fallback to simple text search
        return fallback_text_search(tools, query, limit, response)
    end

    if not llm_response.result or not llm_response.result.relevant_tools then
        response.error = "Invalid LLM response: missing relevant_tools"
        -- Fallback to simple text search
        return fallback_text_search(tools, query, limit, response)
    end

    -- Process LLM results and build final tool list
    local relevant_tools = {}
    for _, llm_tool in ipairs(llm_response.result.relevant_tools) do
        local tool_index = llm_tool.tool_index
        local relevance_score = llm_tool.relevance_score
        local reasoning = llm_tool.reasoning

        -- Validate tool index
        if tool_index and tool_index >= 1 and tool_index <= #tools then
            local tool = tools[tool_index]
            
            -- Add relevance information
            tool.relevance_score = relevance_score
            tool.relevance_reasoning = reasoning

            table.insert(relevant_tools, tool)
        end
    end

    -- Sort by relevance score (highest first)
    table.sort(relevant_tools, function(a, b)
        return (a.relevance_score or 0) > (b.relevance_score or 0)
    end)

    response.success = true
    response.tools = relevant_tools
    return response
end

return {
    handler = handler
}