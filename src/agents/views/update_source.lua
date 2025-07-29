local registry = require("registry")
local json = require("json")
local template_utils = require("template_utils")
local governance = require("governance_client")

local function handler(args)
    -- Validate required arguments
    if not args.id or not args.source then
        return {
            success = false,
            error = "Missing required parameters: id and source are required"
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

    -- Set default operation if not provided
    local operation = args.operation or "replace"
    local updated_content

    -- If no block_name is provided, update the full view source
    if not args.block_name then
        if operation == "replace" then
            -- Replace the entire source
            updated_content = args.source
        elseif operation == "patch" then
            -- Replace specific text
            if not args.target then
                return {
                    success = false,
                    error = "Target text is required for patch operation"
                }
            end

            updated_content = string.gsub(view.data.source, args.target, args.source)

            -- Check if any replacements were made
            if updated_content == view.data.source then
                return {
                    success = false,
                    error = "Target text not found in view source"
                }
            end
        elseif operation == "insert" then
            -- Insert before or after target text
            if not args.target then
                return {
                    success = false,
                    error = "Target text is required for insert operation"
                }
            end

            if not args.position then
                return {
                    success = false,
                    error = "Position (before/after) is required for insert operation"
                }
            end

            local start_pos, end_pos = string.find(view.data.source, args.target, 1, true)
            if not start_pos then
                return {
                    success = false,
                    error = "Target text not found in view source"
                }
            end

            if args.position == "before" then
                updated_content = string.sub(view.data.source, 1, start_pos - 1) ..
                                  args.source ..
                                  string.sub(view.data.source, start_pos)
            else -- "after"
                updated_content = string.sub(view.data.source, 1, end_pos) ..
                                  args.source ..
                                  string.sub(view.data.source, end_pos + 1)
            end
        else
            return {
                success = false,
                error = "Invalid operation: " .. operation
            }
        end
    else
        -- Update a specific block using template_utils
        updated_content, success = template_utils.update_block_in_source(
            view.data.source,
            args.block_name,
            args.source,
            args.parameters
        )

        if not success then
            return {
                success = false,
                error = "Block '" .. args.block_name .. "' not found in view"
            }
        end
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

    if args.block_name then
        return {
            success = true,
            message = string.format("Block '%s' updated in view '%s'", args.block_name, args.id),
            level = "block",
            version = result.version
        }
    else
        return {
            success = true,
            message = "View source updated successfully",
            level = "view",
            version = result.version
        }
    end
end

return {
    handler = handler
}