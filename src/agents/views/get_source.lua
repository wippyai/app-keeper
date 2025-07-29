local registry = require("registry")
local json = require("json")
local template_utils = require("template_utils")

local function handler(args)
    -- Validate required arguments
    if not args.id then
        return {
            success = false,
            error = "Missing required parameter: id is required"
        }
    end

    -- Get the current view
    local view = registry.get(args.id)
    if not view then
        return {
            success = false,
            error = "View not found: " .. args.id
        }
    end

    -- If no block_name is provided, return the full view source
    if not args.block_name then
        return {
            success = true,
            source = view.data.source,
            level = "view"
        }
    end

    -- Otherwise, use template_utils to get the specified block
    local block = template_utils.get_block(view.data.source, args.block_name)

    if not block then
        return {
            success = false,
            error = "Block '" .. args.block_name .. "' not found in view"
        }
    end

    -- Include parameters if requested
    local include_parameters = args.include_parameters
    if include_parameters == nil then
        include_parameters = true
    end

    -- Prepare the result
    local result = {
        success = true,
        level = "block",
        name = args.block_name,
        source = block.content
    }

    -- Include parameters if requested
    if include_parameters then
        result.parameters = block.parameters
    end

    -- Include the full block (with tags) as an option
    result.full_block = block.full_block
    
    return result
end

return {
    handler = handler
}