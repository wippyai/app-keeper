local registry = require("registry")
local governance = require("governance_client")
local text = require("text")

local function handler(params)
    -- Validate required inputs
    if not params.id then
        return {
            success = false,
            error = "Missing required parameter: id"
        }
    end

    if not params.operation then
        return {
            success = false,
            error = "Missing required parameter: operation"
        }
    end

    if not params.content and params.operation ~= "diff" then
        return {
            success = false,
            error = "Missing required parameter: content"
        }
    end

    -- Validate operation is one of the allowed values
    local valid_operations = { full = true, patch = true, insert = true, diff = true }
    if not valid_operations[params.operation] then
        return {
            success = false,
            error = "Invalid operation. Must be one of: full, patch, insert, diff"
        }
    end

    -- Get the entry from registry
    local entry, err = registry.get(params.id)
    if not entry then
        return {
            success = false,
            error = "Code entry not found: " .. (err or "unknown error")
        }
    end

    -- Verify it's a code entry
    local code_kinds = {
        ["function.lua"] = true,
        ["library.lua"] = true,
        ["process.lua"] = true
    }

    if not code_kinds[entry.kind] then
        return {
            success = false,
            error = "Entry is not a code entry. Kind: " .. (entry.kind or "unknown")
        }
    end

    -- Get current source
    local current_source = ""
    if entry.source then
        current_source = entry.source
    elseif entry.data and entry.data.source then
        current_source = entry.data.source
    end

    if current_source == "" then
        return {
            success = false,
            error = "Entry does not have source code"
        }
    end

    local new_source = current_source
    local operation_details = {}

    -- Create text differ for enhanced operations
    local differ, diff_err = text.diff.new({
        match_threshold = 0.5,
        patch_margin = 3
    })
    if diff_err then
        return {
            success = false,
            error = "Failed to create text differ: " .. diff_err
        }
    end

    -- Apply the requested update operation
    if params.operation == "full" then
        -- Full replacement
        new_source = params.content
        table.insert(operation_details, {
            type = "full_replacement",
            description = "Replaced entire source code"
        })

    elseif params.operation == "diff" then
        -- New operation: provide desired end state, use text module to apply
        if not params.new_source then
            return {
                success = false,
                error = "Missing required parameter for diff operation: new_source"
            }
        end

        -- Use text module for intelligent diff application
        local patches, patch_err = differ:patch_make(current_source, params.new_source)
        if patch_err then
            return {
                success = false,
                error = "Failed to create patches: " .. patch_err
            }
        end

        local result, apply_success = differ:patch_apply(patches, current_source)
        if not apply_success then
            return {
                success = false,
                error = "Failed to apply diff patches"
            }
        end

        new_source = result
        table.insert(operation_details, {
            type = "diff_patches",
            description = "Applied " .. #patches .. " patches successfully"
        })

    elseif params.operation == "patch" then
        -- Enhanced patch operation with fuzzy matching
        if not params.target then
            return {
                success = false,
                error = "Missing required parameter for patch operation: target"
            }
        end

        -- Use text module for fuzzy matching
        local target_pos, target_end = current_source:find(params.target, 1, true)
        if not target_pos then
            return {
                success = false,
                error = "Target text not found in source code"
            }
        end

        -- Create modified version by replacing target with content
        local temp_new = current_source:sub(1, target_pos - 1) ..
                        params.content ..
                        current_source:sub(target_end + 1)

        -- Use text module to apply the change intelligently
        local patches, patch_err = differ:patch_make(current_source, temp_new)
        if patch_err then
            return {
                success = false,
                error = "Failed to create patches for patch operation: " .. patch_err
            }
        end

        local result, apply_success = differ:patch_apply(patches, current_source)
        if not apply_success then
            return {
                success = false,
                error = "Failed to apply patch"
            }
        end

        new_source = result
        table.insert(operation_details, {
            type = "patch_intelligent",
            description = "Applied patch with intelligent matching"
        })

    elseif params.operation == "insert" then
        -- Insert operation with validation
        if not params.target then
            return {
                success = false,
                error = "Missing required parameter for insert operation: target"
            }
        end

        if not params.position or (params.position ~= "before" and params.position ~= "after") then
            return {
                success = false,
                error = "Missing or invalid parameter for insert operation: position (must be 'before' or 'after')"
            }
        end

        local start_pos, end_pos = current_source:find(params.target, 1, true)
        if not start_pos then
            return {
                success = false,
                error = "Target text not found in source code"
            }
        end

        if params.position == "before" then
            new_source = current_source:sub(1, start_pos - 1) ..
                params.content ..
                current_source:sub(start_pos)
        else -- "after"
            new_source = current_source:sub(1, end_pos) ..
                params.content ..
                current_source:sub(end_pos + 1)
        end

        table.insert(operation_details, {
            type = "insert_" .. params.position,
            description = "Inserted content " .. params.position .. " target"
        })
    end

    -- Check if there are any changes
    if new_source == current_source then
        return {
            success = true,
            message = "No changes made to the source code",
            operation = params.operation,
            changed = false,
            details = {{
                type = "no_change",
                description = "Source code is identical after operation"
            }}
        }
    end

    -- Generate diff summary for response
    local diffs, diff_err = differ:compare(current_source, new_source)
    if diff_err then
        return {
            success = false,
            error = "Failed to generate diff summary: " .. diff_err
        }
    end

    local diff_summary = differ:summarize(diffs)
    local pretty_diff, pretty_err = differ:pretty_text(diffs)
    if pretty_err then
        return {
            success = false,
            error = "Failed to generate pretty diff: " .. pretty_err
        }
    end

    -- Create a changeset directly
    local changes = registry.snapshot():changes()

    -- Update the entry with new source code
    local updated_data = {}
    if entry.data then
        for k, v in pairs(entry.data) do
            updated_data[k] = v
        end
    end
    updated_data.source = new_source

    -- Update the entry
    changes:update({
        id = entry.id,
        kind = entry.kind,
        meta = entry.meta,
        data = updated_data,
        modules = entry.modules,
        imports = entry.imports,
        method = entry.method
    })

    -- Apply changes through governance client
    local result, err = governance.request_changes(changes)
    if not result then
        return {
            success = false,
            error = "Failed to update source code: " .. (err or "unknown error")
        }
    end

    -- Return success response
    return {
        success = true,
        message = "Source code updated successfully with operation: " .. params.operation,
        operation = params.operation,
        changed = true,
        entry = {
            id = params.id,
            version = result.version
        },
        details = operation_details,
        diff_summary = diff_summary
    }
end

return {
    handler = handler
}