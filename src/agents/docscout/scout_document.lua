local embeddings = require("embeddings")
local security = require("security")
local json = require("json")

local function execute(params)
    -- Validate required parameters
    if not params.query or params.query == "" then
        return {
            success = false,
            error = "Missing required parameter: query is required"
        }
    end

    -- Get current user ID from security context
    local actor = security.actor()
    if not actor then
        return {
            success = false,
            error = "No authenticated user found"
        }
    end

    local user_id = actor:id()

    -- Check permissions
    local can_view_all = security.can("view_all", "uploads")

    -- Set default parameters
    local search_options = {
        limit = params.limit or 10,
        content_type = "chunk/document"  -- Assuming chunks are stored with this content type
    }

    -- If searching within a specific document, verify access and set origin_id
    if params.upload_id and params.upload_id ~= "" then
        -- Check if user has access to this specific document
        local upload_repo = require("upload_repo")
        local upload, err = upload_repo.get(params.upload_id)

        if err then
            return {
                success = false,
                error = "Failed to verify document access: " .. err
            }
        end

        -- Verify ownership or permissions
        if upload.user_id ~= user_id and not can_view_all then
            return {
                success = false,
                error = "Not authorized to search this document"
            }
        end

        -- Set origin_id to search only within this document
        search_options.origin_id = params.upload_id
    end

    local min_similarity = params.min_similarity or 0.3

    -- Perform the search
    local results, err = embeddings.search(params.query, search_options)

    if err then
        return {
            success = false,
            error = "Failed to search documents: " .. err
        }
    end

    -- Normalize and format results
    local formatted_results = {}
    for _, result in ipairs(results) do
        -- Normalize similarity score from [-1,1] to [0,1] range
        local normalized_similarity = (result.similarity + 1) / 2

        -- Only include results above minimum similarity threshold
        if normalized_similarity >= min_similarity then
            local formatted_result = {
                origin_id = result.origin_id,  -- The upload_id
                context_id = result.context_id,
                content = result.content,
                similarity = math.floor(normalized_similarity * 100) / 100, -- Round to 2 decimal places
                metadata = result.meta or {}
            }

            table.insert(formatted_results, formatted_result)
        end
    end

    -- Return success with results
    return {
        success = true,
        message = string.format("Found %d document chunks matching the query", #formatted_results),
        query = params.query,
        results = formatted_results,
        count = #formatted_results
    }
end

return { execute = execute }