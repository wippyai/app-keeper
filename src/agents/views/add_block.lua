local registry = require("registry")
local json = require("json")
local template_utils = require("template_utils")
local governance = require("governance_client")

local function handler(args)
    -- Validate required arguments
    if not args.id or not args.block_name or not args.block_content then
        return {
            success = false,
            error = "Missing required parameters: id, block_name, and block_content are required"
        }
    end

    -- Set default position if not provided
    local position = args.position or "end"
    local parameters = args.parameters or ""

    -- Get the current view
    local view = registry.get(args.id)
    if not view then
        return {
            success = false,
            error = "View not found: " .. args.id
        }
    end

    -- Check if block already exists using template_utils
    local existing_block = template_utils.get_block(view.data.source, args.block_name)
    if existing_block then
        return {
            success = false,
            error = string.format("Block '%s' already exists in view '%s'", args.block_name, args.id)
        }
    end

    -- Create the new block using template_utils
    local block_template = template_utils.create_block(args.block_name, args.block_content, parameters)

    -- Add the block to the source at the specified position
    local updated_content = template_utils.add_block_to_source(view.data.source, block_template, position)

    -- Create a changeset for governance
    local changes = registry.snapshot():changes()

    -- Update the view through the changeset
    changes:update({
        id = args.id,
        kind = view.kind,
        meta = view.meta,
        data = {
            source = updated_content,
            set = view.data.set,
            data_func = view.data.data_func,
            resources = view.data.resources
        }
    })

    -- Apply changes through governance client
    local result, err = governance.request_changes(changes)
    if not result then
        return {
            success = false,
            error = "Failed to apply registry changes: " .. (err or "unknown error")
        }
    end

    return {
        success = true,
        message = string.format("Block '%s' added to view '%s'", args.block_name, args.id),
        version = result.version
    }
end

return {
    handler = handler
}