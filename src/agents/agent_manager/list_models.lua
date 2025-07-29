local json = require("json")
local llm = require("llm")

-- LLM Model Discovery Tool
-- Lists available LLM models with optional filtering by capabilities or provider
-- Returns: Single result table with success boolean, models array, count, and error

local function handler(params)
    -- Initialize response structure following function handler pattern
    local response = {
        success = false,
        models = {},
        error = nil,
        count = 0,
        filters_applied = {}
    }

    -- Validate and set default parameters
    params = params or {}
    local capabilities_filter = params.capabilities
    local provider_filter = params.provider
    local include_pricing = params.include_pricing == true

    -- Validate capabilities parameter
    if capabilities_filter then
        if type(capabilities_filter) ~= "table" then
            response.error = "Invalid capabilities parameter: must be an array of strings"
            return response
        end
        
        -- Validate each capability
        local valid_capabilities = {
            tool_use = true,
            vision = true,
            thinking = true,
            caching = true,
            multilingual = true,
            generate = true,
            embed = true
        }
        
        for _, cap in ipairs(capabilities_filter) do
            if type(cap) ~= "string" or not valid_capabilities[cap] then
                response.error = "Invalid capability: " .. tostring(cap) .. ". Valid capabilities: tool_use, vision, thinking, caching, multilingual, generate, embed"
                return response
            end
        end
        
        response.filters_applied.capabilities = capabilities_filter
    end

    -- Validate provider parameter
    if provider_filter then
        if type(provider_filter) ~= "string" then
            response.error = "Invalid provider parameter: must be a string"
            return response
        end
        
        provider_filter = provider_filter:lower()
        response.filters_applied.provider = provider_filter
    end

    -- Get all available models using LLM library
    local all_models, err = llm.available_models()
    if err then
        response.error = "Failed to retrieve models from LLM library: " .. tostring(err)
        return response
    end

    if not all_models or #all_models == 0 then
        response.success = true
        response.models = {}
        response.count = 0
        return response
    end

    -- Helper function to extract provider from model card
    local function extract_provider(model_card)
        local provider = "unknown"
        
        -- Try to extract from handlers.generate path
        if model_card.handlers and model_card.handlers.generate then
            local provider_match = model_card.handlers.generate:match("wippy%.llm%.([^:]+):")
            if provider_match then
                provider = provider_match
            end
        end
        
        -- Try to extract from handlers.call_tools if generate not available
        if provider == "unknown" and model_card.handlers and model_card.handlers.call_tools then
            local provider_match = model_card.handlers.call_tools:match("wippy%.llm%.([^:]+):")
            if provider_match then
                provider = provider_match
            end
        end
        
        -- Try to extract from handlers.embeddings for embedding models
        if provider == "unknown" and model_card.handlers and model_card.handlers.embeddings then
            local provider_match = model_card.handlers.embeddings:match("wippy%.llm%.([^:]+):")
            if provider_match then
                provider = provider_match
            end
        end
        
        return provider
    end

    -- Helper function to check if model matches capability filter
    local function matches_capabilities(model_card, filter_caps)
        if not filter_caps or #filter_caps == 0 then
            return true
        end
        
        local model_caps = model_card.capabilities or {}
        local model_cap_set = {}
        for _, cap in ipairs(model_caps) do
            model_cap_set[cap] = true
        end
        
        -- Check if model has ALL requested capabilities
        for _, required_cap in ipairs(filter_caps) do
            if not model_cap_set[required_cap] then
                return false
            end
        end
        
        return true
    end

    -- Helper function to check if model matches provider filter
    local function matches_provider(model_card, filter_provider)
        if not filter_provider then
            return true
        end
        
        local model_provider = extract_provider(model_card):lower()
        return model_provider == filter_provider
    end

    -- Process and filter models
    local filtered_models = {}
    for _, model_card in ipairs(all_models) do
        -- Apply capability filter
        if not matches_capabilities(model_card, capabilities_filter) then
            goto continue
        end
        
        -- Apply provider filter
        if not matches_provider(model_card, provider_filter) then
            goto continue
        end
        
        -- Build model object with essential information
        local model = {
            name = model_card.name or "unknown",
            title = model_card.title or model_card.name or "Unknown Model",
            capabilities = model_card.capabilities or {},
            max_tokens = model_card.max_tokens or 0,
            output_tokens = model_card.output_tokens or 0,
            provider = extract_provider(model_card)
        }
        
        -- Include pricing if requested
        if include_pricing and model_card.pricing then
            model.pricing = model_card.pricing
        end
        
        table.insert(filtered_models, model)
        
        ::continue::
    end

    -- Sort models by provider, then by name for consistent ordering
    table.sort(filtered_models, function(a, b)
        if a.provider == b.provider then
            return a.name < b.name
        else
            return a.provider < b.provider
        end
    end)

    -- Set successful response
    response.success = true
    response.models = filtered_models
    response.count = #filtered_models

    return response
end

return {
    handler = handler
}