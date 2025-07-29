local json = require("json")
local extractor = require("extractor")

-- Helper function for consistent logging
local function log_info(message)
    print("[INFO] " .. message)
end

local function log_error(message)
    print("[ERROR] " .. message)
end

local function log_debug(message)
    print("[DEBUG] " .. message)
end

local function log_step(step_name)
    print("\n========== " .. step_name .. " ==========")
end

-- Main handler function
local function handler(params)
    log_step("Extraction Process Started")

    -- Basic Parameter Validation
    if not params or type(params) ~= "table" then
        log_error("Invalid parameters received: not a table.")
        return { success = false, error = "Invalid parameters: must be a table." }
    end

    if not params.file_uuid or type(params.file_uuid) ~= "string" or string.len(params.file_uuid) == 0 then
        log_error("Missing or invalid required parameter: file_uuid (string)")
        return { success = false, error = "Missing or invalid required parameter: file_uuid (string)" }
    end

    if not params.entry_id or type(params.entry_id) ~= "string" or string.len(params.entry_id) == 0 then
        log_error("Missing or invalid required parameter: entry_id (string)")
        return { success = false, error = "Missing or invalid required parameter: entry_id (string)" }
    end

    -- Log parameters - but ONLY what was provided
    log_info("Parameters:")
    log_info("  File UUID: " .. params.file_uuid)
    log_info("  Entry ID: " .. params.entry_id)
    if params.validation_steps ~= nil then
        log_info("  Validation Steps: " .. params.validation_steps)
    else
        log_info("  Validation Steps: from config")
    end
    if params.scout_model ~= nil then
        log_info("  Scout Model: " .. params.scout_model)
    end
    if params.extraction_model ~= nil then
        log_info("  Extraction Model: " .. params.extraction_model)
    end

    -- Create extractor with ONLY explicitly provided options
    log_step("Creating Extractor")
    local options = {}

    -- Only include explicitly provided parameters
    if params.validation_steps ~= nil then options.validation_steps = params.validation_steps end
    if params.scout_model ~= nil then options.scout_model = params.scout_model end
    if params.extraction_model ~= nil then options.extraction_model = params.extraction_model end
    if params.min_confidence ~= nil then options.min_confidence = params.min_confidence end
    if params.max_additional_queries ~= nil then options.max_additional_queries = params.max_additional_queries end
    if params.structured_output ~= nil then options.structured_output = params.structured_output end
    if params.scout_max_tokens ~= nil then options.scout_max_tokens = params.scout_max_tokens end
    if params.extraction_max_tokens ~= nil then options.extraction_max_tokens = params.extraction_max_tokens end

    params.stream = true

    -- Set up callbacks if streaming is enabled
    if params.stream or params.callbacks then
        local callbacks = params.callbacks or {}

        -- Define default callbacks if not provided but streaming is enabled
        if params.stream and not callbacks.on_validation_result then
            callbacks.on_validation_result = function(data)
                log_step("Validation Step " .. data.step .. " Result")
                log_info("Confidence: " .. data.result.overall_confidence)
                log_info("Excluded chunks: " .. #data.result.excluded_chunks)
                log_info("Additional queries: " .. #data.result.additional_queries)

                -- Only log tokens if available
                if data.tokens then
                    log_info("Tokens used: " .. (data.tokens.total_tokens or 0))
                    if data.tokens.thinking_tokens then
                        log_info("Thinking tokens: " .. data.tokens.thinking_tokens)
                    end
                end

                if params.stream_level == "detailed" and data.result.notes then
                    log_info("Notes count: " .. #data.result.notes)
                end
            end
        end

        if params.stream and not callbacks.on_extraction_result then
            callbacks.on_extraction_result = function(data)
                log_step("Extraction Result")

                -- Log the first few lines of text results or fields of structured results
                if type(data.result) == "string" then
                    -- Get first 3 lines only
                    local lines = {}
                    local i = 1
                    for line in data.result:gmatch("[^\r\n]+") do
                        if i <= 3 then
                            table.insert(lines, line)
                            i = i + 1
                        else
                            break
                        end
                    end
                    log_info("Result (first few lines): " .. table.concat(lines, "; ") .. "...")
                elseif type(data.result) == "table" then
                    log_info("Extraction completed with structured output")
                end

                -- Only log tokens if available
                if data.tokens then
                    log_info("Tokens used: " .. (data.tokens.total_tokens or 0))
                    if data.tokens.thinking_tokens then
                        log_info("Thinking tokens: " .. data.tokens.thinking_tokens)
                    end
                end
            end
        end

        -- Add error callback for streaming mode
        if params.stream and not callbacks.on_error then
            callbacks.on_error = function(data)
                log_error("Error in " .. data.phase .. " phase: " .. tostring(data.error))
            end
        end

        options.callbacks = callbacks
    end

    local extraction, init_err = extractor.new(params.file_uuid, params.entry_id, options)

    -- Check if extractor creation succeeded
    if not extraction then
        log_error("Failed to create extractor: " .. (init_err or "Unknown error"))
        return { success = false, error = "Failed to create extractor: " .. (init_err or "Unknown error") }
    end

    -- Run extraction process
    log_step("Running Extraction Process")
    local result, err = extraction:run()

    if err then
        log_error("Extraction process failed: " .. err)
        return { success = false, error = err }
    end

    -- Get metrics
    local metrics = extraction:get_metrics()

    log_step("Extraction Metrics")
    log_info("Validation steps performed: " .. metrics.validation_steps)
    log_info("Total chunks excluded: " .. metrics.excluded_chunks)
    log_info("Total additional queries added: " .. metrics.additional_queries)

    -- Log token usage
    log_info("Token usage:")
    log_info("  Validation: " .. metrics.tokens.validation.total_tokens)
    log_info("  Extraction: " .. metrics.tokens.extraction.total_tokens)
    log_info("  Total: " .. metrics.tokens.total)

    -- Log thinking tokens if available
    if metrics.tokens.validation.thinking_tokens then
        log_info("  Validation thinking tokens: " .. metrics.tokens.validation.thinking_tokens)
    end
    if metrics.tokens.extraction.thinking_tokens then
        log_info("  Extraction thinking tokens: " .. metrics.tokens.extraction.thinking_tokens)
    end
    if metrics.tokens.thinking_tokens then
        log_info("  Total thinking tokens: " .. metrics.tokens.thinking_tokens)
    end

    -- Log confidence scores
    if metrics.confidence and #metrics.confidence > 0 then
        log_info("Confidence scores:")
        for i, confidence in ipairs(metrics.confidence) do
            log_info("  Step " .. i .. ": " .. confidence)
        end
    end

    -- Get state summary
    local state_summary = extraction:get_state_summary()

    log_step("Extraction Process Completed")

    -- Return success with extraction results
    return {
        success = true,
        file_uuid = params.file_uuid,
        entry_id = params.entry_id,
        metrics = metrics,
        extraction_result = result.result,
        raw_text = result.raw_text,
        notes = result.notes,
        validation_results = result.validation_results,
        state_summary = {
            total_queries = state_summary.total_queries_run,
            active_queries = state_summary.active_queries_count,
            total_chunks = state_summary.active_unique_chunks,
            ignored_chunks = state_summary.ignored_chunk_count,
            notes_count = state_summary.notes_count
        }
    }
end

-- Example of using the streaming feature
--[[
Usage example:

local result = handler({
    file_uuid = "abc123",
    entry_id = "app.docscout.mna:general_terms",
    stream = true,  -- Enable default streaming
    stream_level = "basic",  -- 'basic' or 'detailed'

    -- Or provide custom callbacks
    callbacks = {
        on_validation_prompt = function(data)
            -- Custom handling of validation prompt
            print("Validation step " .. data.step .. " prompt generated")
        end,

        on_validation_result = function(data)
            -- Custom handling of validation result
            print("Validation step " .. data.step .. " completed with confidence: " .. data.result.overall_confidence)
        end,

        on_extraction_result = function(data)
            -- Custom handling of extraction result
            print("Extraction completed with result type: " .. type(data.result))
        end
    }
})
--]]

return { handler = handler }