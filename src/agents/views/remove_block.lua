local registry = require("registry")
local json = require("json")
local template_utils = require("template_utils")
local governance = require("governance_client")

local function handler(args)
    -- Validate required arguments
    if not args.id or not args.block_name then
        return {
            success = false,
            error = "Missing required parameters: id and block_name are required"
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

    -- Check if block exists
    local block = template_utils.get_block(view.data.source, args.block_name)
    if not block then
        return {
            success = false,
            error = "Block '" .. args.block_name .. "' not found in view"
        }
    end

    -- Check for references to this block in the view
    local has_references = template_utils.has_block_references(view.data.source, args.block_name)

    if has_references and not args.force then
        return {
            success = false,
            error = "Block '" .. args.block_name .. "' is referenced in the view. Use force=true to remove anyway.",
            references_found = true
        }
    end

    -- Remove the block using template_utils
    local updated_content, success = template_utils.remove_block_from_source(view.data.source, args.block_name)

    if not success then
        return {
            success = false,
            error = "Failed to remove block '" .. args.block_name .. "'"
        }
    end

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
        message = string.format("Block '%s' removed from view '%s'", args.block_name, args.id),
        references_found = has_references,
        version = result.version
    }
end

return {
    handler = handler
}
