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

    -- Use template_utils to get all blocks in the template
    local blocks = template_utils.get_blocks(view.data.source)

    -- Format the results for consistent output
    local result_blocks = {}
    for _, block in ipairs(blocks) do
        table.insert(result_blocks, {
            name = block.name,
            parameters = block.parameters
        })
    end

    -- Sort blocks by their position in the file (already done by template_utils)

    return {
        success = true,
        blocks = result_blocks,
        count = #result_blocks
    }
end

return {
    handler = handler
}