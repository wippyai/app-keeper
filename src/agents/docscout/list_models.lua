local models = require("models")

local function handler(args)
    -- Parse arguments
    args = args or {}
    local filter_capabilities = args.capabilities or {}
    local filter_provider = args.provider
    local include_embeddings = args.include_embeddings or false
    
    -- Get all available models
    local all_models = models.get_all()
    
    -- Filter and format the models
    local filtered_models = {}
    for _, model in ipairs(all_models) do
        -- Skip embedding models unless explicitly requested
        local is_embedding = (model.type == "llm.embedding")
        if is_embedding and not include_embeddings then
            goto continue
        end
        
        -- Filter by provider if specified
        if filter_provider and filter_provider ~= "" then
            local model_provider = "unknown"
            if model.handlers and model.handlers.generate then
                local provider_match = model.handlers.generate:match("wippy%.llm%.([^:]+):")
                if provider_match then
                    model_provider = provider_match
                end
            elseif model.handlers and model.handlers.embeddings then
                local provider_match = model.handlers.embeddings:match("wippy%.llm%.([^:]+):")
                if provider_match then
                    model_provider = provider_match
                end
            end
            
            if model_provider ~= filter_provider then
                goto continue
            end
        end
        
        -- Filter by capabilities if specified
        if #filter_capabilities > 0 and model.capabilities then
            local has_all_capabilities = true
            for _, required_cap in ipairs(filter_capabilities) do
                local has_capability = false
                for _, cap in ipairs(model.capabilities) do
                    if cap == required_cap then
                        has_capability = true
                        break
                    end
                end
                
                if not has_capability then
                    has_all_capabilities = false
                    break
                end
            end
            
            if not has_all_capabilities then
                goto continue
            end
        end
        
        -- Determine provider from handler path
        local provider = "unknown"
        if model.handlers and model.handlers.generate then
            -- Extract provider from handler path (e.g., "wippy.llm.openai:text_generation" -> "openai")
            local provider_match = model.handlers.generate:match("wippy%.llm%.([^:]+):")
            if provider_match then
                provider = provider_match
            end
        elseif model.handlers and model.handlers.embeddings then
            local provider_match = model.handlers.embeddings:match("wippy%.llm%.([^:]+):")
            if provider_match then
                provider = provider_match
            end
        end
        
        -- Format the model for display
        local formatted_model = {
            name = model.name,
            title = model.title or model.name,
            description = model.description or "",
            provider = provider,
            provider_model = model.provider_model or "",
            type = model.type or "llm.model",
            capabilities = model.capabilities or {},
            max_tokens = model.max_tokens or 0,
            output_tokens = model.output_tokens or 0,
            pricing = model.pricing or {}
        }
        
        table.insert(filtered_models, formatted_model)
        
        ::continue::
    end
    
    -- Sort models by name
    table.sort(filtered_models, function(a, b)
        return a.name < b.name
    end)
    
    -- Return the filtered models
    return {
        success = true,
        count = #filtered_models,
        models = filtered_models
    }
end

return {
    handler = handler
}