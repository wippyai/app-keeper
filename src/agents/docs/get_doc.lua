local registry = require("registry")

local function handler(params)
    -- Validate input
    if not params.id then
        return {
            success = false,
            error = "Missing required parameter: id (ID of documentation to retrieve)"
        }
    end

    -- Get the entry directly
    local entry, err = registry.get(params.id)
    if not entry then
        return {
            success = false,
            error = "Documentation not found: " .. params.id
        }
    end

    -- Return the documentation content
    return entry.data.source or entry.data or "No content available"
end

return {
    handler = handler
}