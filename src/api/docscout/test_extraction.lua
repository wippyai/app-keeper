local http = require("http")
local json = require("json")
local extractor = require("extractor")

local function handler()
    -- Get response and request objects
    local res = http.response()
    local req = http.request()
    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Check for JSON content type
    if not req:is_content_type(http.CONTENT.JSON) then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Request must be application/json"
        })
        return
    end

    -- Parse JSON body
    local data, err = req:body_json()
    if err then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to parse JSON body: " .. err
        })
        return
    end

    -- Validate required parameters
    if not data.file_uuid or type(data.file_uuid) ~= "string" or string.len(data.file_uuid) == 0 then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing or invalid required parameter: file_uuid (string)"
        })
        return
    end

    if not data.entry_id or type(data.entry_id) ~= "string" or string.len(data.entry_id) == 0 then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing or invalid required parameter: entry_id (string)"
        })
        return
    end

    -- Create extractor options
    local options = {}

    -- Transfer optional parameters to options
    if data.validation_steps ~= nil then options.validation_steps = data.validation_steps end
    if data.scout_model ~= nil then options.scout_model = data.scout_model end
    if data.extraction_model ~= nil then options.extraction_model = data.extraction_model end
    if data.min_confidence ~= nil then options.min_confidence = data.min_confidence end
    if data.max_additional_queries ~= nil then options.max_additional_queries = data.max_additional_queries end
    if data.structured_output ~= nil then options.structured_output = data.structured_output end
    if data.scout_max_tokens ~= nil then options.scout_max_tokens = data.scout_max_tokens end
    if data.extraction_max_tokens ~= nil then options.extraction_max_tokens = data.extraction_max_tokens end

    -- Create extractor
    local extraction, init_err = extractor.new(data.file_uuid, data.entry_id, options)

    -- Check if extractor creation succeeded
    if not extraction then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to create extractor: " .. (init_err or "Unknown error")
        })
        return
    end

    -- Run extraction process
    local result, err = extraction:run()

    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Extraction process failed: " .. err
        })
        return
    end

    -- Get metrics and state summary
    local metrics = extraction:get_metrics()
    local state_summary = extraction:get_state_summary()

    -- Return success with extraction results
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        file_uuid = data.file_uuid,
        entry_id = data.entry_id,
        metrics = metrics,
        extraction_result = result.result,
        analyzer_context = result.analyzer_context or {}, -- ✅ Include raw analyzer findings
        raw_text = result.raw_text, -- Legacy field, may be nil
        notes = result.notes,
        validation_results = result.validation_results,
        state_summary = {
            total_queries = state_summary.total_queries_run,
            active_queries = state_summary.active_queries_count,
            total_chunks = state_summary.active_unique_chunks,
            ignored_chunks = state_summary.ignored_chunk_count,
            notes_count = state_summary.notes_count
        }
    })
end

return {
    handler = handler
}