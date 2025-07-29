-- file: find_relevant.lua
local registry = require("registry")
local llm = require("llm")

-- Constants
local ENTRIES_FETCH_LIMIT = 5000
local MAX_FINAL_IDS = 16 -- Default limit
local MAX_PRIMARY_IDS_PASS_1 = 15
local LLM_MODEL_FOR_ANALYSIS = "gpt-4.1-mini"
local DOC_NAMESPACE = "wippy.docs"
local BASICS_SPEC_ID = DOC_NAMESPACE .. ":basics.spec"

-- LLM Structured Output Schema (Pass 1)
local PRIMARY_RELEVANCE_SCHEMA = {
    type = "object",
    properties = {
        primary_relevant_ids = {
            type = "array",
            description =
            "List of full_id strings for registry entries *directly* relevant to the query's main subject. IDs MUST be ONLY valid 'namespace:name' strings found in the provided headers. Max " ..
            MAX_PRIMARY_IDS_PASS_1 .. " IDs, ordered by relevance.",
            items = { type = "string" }
        }
    },
    required = { "primary_relevant_ids" },
    additionalProperties = false
}

-- LLM Prompt Template (Pass 1 - Generic Examples)
local PROMPT_TEMPLATE_PASS_1 = [[
You are an expert Wippy Runtime registry analyst. Your goal is to identify registry entries **directly** related to the primary subject of the user's query, based *only* on the available headers provided below.

User Query:
%s

Available Registry Entry Headers (Format: ID # COMMENT):
%s

Instructions:
1. Identify the **primary subject** of the User Query based on its content.
2. Scan the **Available Registry Entry Headers**. Find entries where the identified primary subject is clearly mentioned or strongly implied in the ID (`namespace:name`) or the COMMENT.
3. **CRITICAL:** Only include IDs that are **explicitly present** in the "Available Registry Entry Headers" list. Do not guess or create IDs.
4. Prioritize entries like agents (`kind=registry.entry` with `meta.type=agent.gen1`), core code (`function.lua`, `library.lua`), configurations, or documentation directly related to the subject.
5. Return ONLY a prioritized list of the top %d **directly relevant** and **verifiably present** full_ids using the provided schema.
]]

-- Helper Functions
local function format_headers_for_prompt(headers)
    local lines = {}
    for _, h in ipairs(headers) do
        local comment_text = (type(h.comment) == "string" and h.comment ~= "") and h.comment or "No comment"
        table.insert(lines,
            "- " ..
            h.full_id .. " # " .. comment_text:gsub("[\n\r]+", " "):sub(1, 150) .. ", kind: " .. (h.kind or "unknown"))
    end
    if #lines == 0 then
        return "(No registry entry headers were available or extracted)"
    end
    return table.concat(lines, "\n")
end

local function combine_and_deduplicate_ids_with_comments(primary_ids, supplemental_ids, max_total, all_entries_map)
    local seen = {}
    local final_list = {}
    local count = 0

    -- Helper function to create entry object with comment
    local function create_entry_object(id)
        local entry = all_entries_map[id]
        local comment = nil
        if entry and entry.meta and type(entry.meta.comment) == "string" and entry.meta.comment ~= "" then
            comment = entry.meta.comment
        end
        return {
            id = id,
            comment = comment
        }
    end

    -- Add primary IDs first
    for _, id in ipairs(primary_ids) do
        if not seen[id] and count < max_total then
            table.insert(final_list, create_entry_object(id))
            seen[id] = true
            count = count + 1
        end
    end

    -- Add supplemental IDs
    for _, id in ipairs(supplemental_ids) do
        if not seen[id] and count < max_total then
            table.insert(final_list, create_entry_object(id))
            seen[id] = true
            count = count + 1
        end
    end

    return final_list
end

local function set_to_sorted_list(set)
    local list = {}
    for k in pairs(set) do
        table.insert(list, k)
    end
    table.sort(list)
    return list
end

-- Main Handler
local function handler(params)
    local response_data = { success = false, result = nil, error = nil }

    -- Validate Input
    if not params.query or type(params.query) ~= "string" or params.query == "" then
        response_data.error = "Missing or invalid required parameter: query (must be a non-empty string)"
        return response_data
    end

    -- Get limit parameter or use default
    local limit = MAX_FINAL_IDS
    if params.limit and type(params.limit) == "number" and params.limit > 0 then
        limit = math.floor(params.limit)
    end

    -- Check for legacy mode (return just IDs for backwards compatibility)
    local legacy_mode = params.legacy_mode or false

    -- Get Snapshot
    local snapshot, err_snap = registry.snapshot()
    if not snapshot then
        response_data.error = "Failed to get registry snapshot: " .. (err_snap or "unknown error")
        return response_data
    end

    -- Fetch Entries & Extract Headers
    local all_entries_list, err_entries = snapshot:entries({ limit = ENTRIES_FETCH_LIMIT })
    if err_entries then
        response_data.error = "Failed to get registry entries from snapshot: " .. err_entries
        return response_data
    end

    local all_entries_map = {}
    local extracted_headers = {}
    local existing_entry_ids = {}
    local basics_spec_exists = false -- Flag to track if basics.spec exists

    if all_entries_list and #all_entries_list > 0 then
        for _, entry in ipairs(all_entries_list) do
            if entry and type(entry.id) == "string" then
                all_entries_map[entry.id] = entry
                existing_entry_ids[entry.id] = true
                table.insert(extracted_headers, {
                    full_id = entry.id,
                    kind = entry.kind or "unknown",
                    comment = (entry.meta and type(entry.meta.comment) == "string") and entry.meta.comment or nil
                })
                if entry.id == BASICS_SPEC_ID then
                    basics_spec_exists = true -- Set flag if found
                end
            end
        end
    end
    local formatted_headers = format_headers_for_prompt(extracted_headers)

    -- === PASS 1: LLM Call to Identify Primary Relevant Entries ===
    local final_llm_prompt_pass1 = string.format(PROMPT_TEMPLATE_PASS_1, params.query, formatted_headers,
        MAX_PRIMARY_IDS_PASS_1)
    local llm_response_pass1 = llm.structured_output(
        PRIMARY_RELEVANCE_SCHEMA,
        final_llm_prompt_pass1,
        { model = LLM_MODEL_FOR_ANALYSIS }
    )

    local primary_relevant_ids = {}
    if not llm_response_pass1 or llm_response_pass1.error then
        response_data.error = "LLM analysis (Pass 1) failed: " ..
        (llm_response_pass1 and (llm_response_pass1.error .. ": " .. llm_response_pass1.error_message) or "Unknown LLM error")
        return response_data
    end
    if not llm_response_pass1.result or not llm_response_pass1.result.primary_relevant_ids or type(llm_response_pass1.result.primary_relevant_ids) ~= "table" then
        primary_relevant_ids = {}
    else
        primary_relevant_ids = llm_response_pass1.result.primary_relevant_ids
    end

    -- === Dependency Analysis & Doc ID Generation (Programmatic) ===
    local dependent_modules = {}
    local dependent_imports = {}
    local supplemental_doc_ids = {}
    local includes_lua_code = false -- Flag to track if any primary entry is Lua code

    for _, primary_id in ipairs(primary_relevant_ids) do
        local current_id_to_lookup = primary_id
        local entry_data = all_entries_map[current_id_to_lookup]
        if entry_data then
            local kind = entry_data.kind
            if kind == "function.lua" or kind == "library.lua" or kind == "process.lua" then
                includes_lua_code = true -- Set flag if Lua code is found
                if entry_data.data and type(entry_data.data) == "table" then
                    -- Extract system modules
                    if entry_data.data.modules and type(entry_data.data.modules) == "table" then
                        for _, module_name in ipairs(entry_data.data.modules) do
                            if type(module_name) == "string" and not dependent_modules[module_name] then
                                dependent_modules[module_name] = true
                            end
                        end
                    end
                    -- Extract imported library IDs
                    if entry_data.data.imports and type(entry_data.data.imports) == "table" then
                        for alias, import_id in pairs(entry_data.data.imports) do
                            if type(import_id) == "string" and not dependent_imports[import_id] then
                                dependent_imports[import_id] = true
                            end
                        end
                    end
                end
            end
        end
        -- No print warning here for missing IDs, as we reinforced the prompt
    end

    -- Construct and verify documentation IDs for dependent modules
    for module_name, _ in pairs(dependent_modules) do
        local doc_id = DOC_NAMESPACE .. ":" .. module_name .. ".spec"
        if existing_entry_ids[doc_id] then
            table.insert(supplemental_doc_ids, doc_id)
        end
    end

    -- Add basics.spec if relevant Lua code was found and the spec exists
    if includes_lua_code and basics_spec_exists then
        table.insert(supplemental_doc_ids, BASICS_SPEC_ID)
    end

    -- === Combine and Finalize Results ===
    if legacy_mode then
        -- Legacy mode: return just IDs (backwards compatibility)
        local function combine_and_deduplicate_ids(primary_ids, supplemental_ids, max_total)
            local seen = {}
            local final_list = {}
            local count = 0
            for _, id in ipairs(primary_ids) do
                if not seen[id] and count < max_total then
                    table.insert(final_list, id)
                    seen[id] = true
                    count = count + 1
                end
            end
            for _, id in ipairs(supplemental_ids) do
                if not seen[id] and count < max_total then
                    table.insert(final_list, id)
                    seen[id] = true
                    count = count + 1
                end
            end
            return final_list
        end

        local final_ids = combine_and_deduplicate_ids(primary_relevant_ids, supplemental_doc_ids, limit)
        response_data.success = true
        response_data.result = final_ids
    else
        -- New mode: return objects with IDs and comments
        local final_entries = combine_and_deduplicate_ids_with_comments(primary_relevant_ids, supplemental_doc_ids, limit, all_entries_map)
        response_data.success = true
        response_data.result = final_entries
    end

    response_data.error = nil
    return response_data
end

return {
    handler = handler
}