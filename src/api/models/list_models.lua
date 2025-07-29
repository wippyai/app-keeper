local http = require("http")
local json = require("json")
local models = require("models")

local function handler()
    -- Get response object
    local res = http.response()
    local req = http.request()
    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Get query parameters for optional filtering
    local provider = req:query("provider") -- Optional provider filter
    local with_capabilities = req:query("capabilities") -- Optional capabilities filter

    -- Parse capabilities filter if present
    local required_capabilities = {}
    if with_capabilities and with_capabilities ~= "" then
        for capability in with_capabilities:gmatch("[^,]+") do
            table.insert(required_capabilities, capability:match("^%s*(.-)%s*$"))
        end
    end

    -- Get all models from the models library
    local all_models = models.get_all()

    -- Filter and format the models
    local formatted_models = {}
    for _, model in ipairs(all_models) do
        -- Skip embedding models unless explicitly requested
        local is_embedding = (model.type == "llm.embedding")
        if is_embedding and req:query("include_embeddings") ~= "true" then
            goto continue
        end

        -- Filter by provider if specified
        if provider and provider ~= "" then
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

            if model_provider ~= provider then
                goto continue
            end
        end

        -- Filter by capabilities if specified
        if #required_capabilities > 0 and model.capabilities then
            local has_all_capabilities = true
            for _, required_cap in ipairs(required_capabilities) do
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

        -- Format the model for UI display with all valuable information
        local formatted_model = {
            id = model.id,
            name = model.name,
            title = model.title or model.name,
            description = model.description or "",
            provider = provider,
            provider_model = model.provider_model or "",
            type = model.type or "llm.model",
            capabilities = model.capabilities or {},
            max_tokens = model.max_tokens or 0,
            output_tokens = model.output_tokens or 0,
            icon = (model.meta and model.meta.icon) or nil,
            pricing = model.pricing or {}
        }

        -- Add additional fields if they exist
        if model.knowledge_cutoff then
            formatted_model.knowledge_cutoff = model.knowledge_cutoff
        end

        if model.dimensions then
            formatted_model.dimensions = model.dimensions
        end

        if model.model_family then
            formatted_model.model_family = model.model_family
        end

        if model.mteb_performance then
            formatted_model.mteb_performance = model.mteb_performance
        end

        table.insert(formatted_models, formatted_model)

        ::continue::
    end

    -- Sort models by name
    table.sort(formatted_models, function(a, b)
        return a.name < b.name
    end)

    -- Return JSON response
    res:set_content_type(http.CONTENT.JSON)
    res:set_status(http.STATUS.OK)
    res:write_json({
        success = true,
        count = #formatted_models,
        models = formatted_models
    })
end

return {
    handler = handler
}