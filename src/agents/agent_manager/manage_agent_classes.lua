local json = require("json")
local yaml = require("yaml")
local get_entries = require("get_entries")
local update_entry = require("update_entry")

local function handler(params)
    -- Validate input parameters
    if not params.agent_id or type(params.agent_id) ~= "string" or params.agent_id == "" then
        return {
            success = false,
            error = "Missing or invalid required parameter: agent_id"
        }
    end

    if not params.operation or type(params.operation) ~= "string" then
        return {
            success = false,
            error = "Missing or invalid required parameter: operation"
        }
    end

    if params.operation ~= "add" and params.operation ~= "remove" and params.operation ~= "set" then
        return {
            success = false,
            error = "Invalid operation. Must be 'add', 'remove', or 'set'"
        }
    end

    if not params.classes or type(params.classes) ~= "table" then
        return {
            success = false,
            error = "Missing or invalid required parameter: classes (must be array)"
        }
    end

    if #params.classes == 0 then
        return {
            success = false,
            error = "Classes array cannot be empty"
        }
    end

    -- Validate all class names are strings
    for i, class_name in ipairs(params.classes) do
        if type(class_name) ~= "string" or class_name == "" then
            return {
                success = false,
                error = "Class name at index " .. i .. " must be a non-empty string"
            }
        end
    end

    -- Get agent entry to validate existence and type
    local get_result_yaml = get_entries.handler({
        ids = {params.agent_id}
    })
    
    -- Decode YAML response to Lua table
    local get_result, decode_err = yaml.decode(get_result_yaml)
    if not get_result then
        return {
            success = false,
            error = "Failed to decode get_entries response: " .. (decode_err or "unknown error")
        }
    end
    
    if not get_result.success then
        return {
            success = false,
            error = "Failed to fetch agent: " .. (get_result.error or "unknown error")
        }
    end
    
    if not get_result.result or #get_result.result == 0 then
        return {
            success = false,
            error = "Agent not found: " .. params.agent_id
        }
    end
    
    local agent_entry = get_result.result[1]
    if not agent_entry.meta or agent_entry.meta.type ~= "agent.gen1" then
        return {
            success = false,
            error = "Entry is not a valid agent.gen1: " .. params.agent_id
        }
    end

    -- Get current classes (handle both string and array formats)
    local current_classes = {}
    if agent_entry.meta and agent_entry.meta.class then
        if type(agent_entry.meta.class) == "string" then
            table.insert(current_classes, agent_entry.meta.class)
        elseif type(agent_entry.meta.class) == "table" then
            for _, class_name in ipairs(agent_entry.meta.class) do
                table.insert(current_classes, class_name)
            end
        end
    end

    -- Perform operation
    local updated_classes = {}
    local changes_made = false

    if params.operation == "set" then
        -- Set operation: replace all classes with new ones
        for _, class_name in ipairs(params.classes) do
            local already_exists = false
            for _, existing_class in ipairs(updated_classes) do
                if existing_class == class_name then
                    already_exists = true
                    break
                end
            end
            if not already_exists then
                table.insert(updated_classes, class_name)
            end
        end
        
        -- Check if there are actual changes
        if #updated_classes ~= #current_classes then
            changes_made = true
        else
            for _, new_class in ipairs(updated_classes) do
                local found = false
                for _, current_class in ipairs(current_classes) do
                    if current_class == new_class then
                        found = true
                        break
                    end
                end
                if not found then
                    changes_made = true
                    break
                end
            end
        end
    elseif params.operation == "add" then
        -- Start with current classes
        for _, class_name in ipairs(current_classes) do
            table.insert(updated_classes, class_name)
        end
        
        -- Add new classes (avoid duplicates)
        for _, class_name in ipairs(params.classes) do
            local already_exists = false
            for _, existing_class in ipairs(updated_classes) do
                if existing_class == class_name then
                    already_exists = true
                    break
                end
            end
            if not already_exists then
                table.insert(updated_classes, class_name)
                changes_made = true
            end
        end
    elseif params.operation == "remove" then
        -- Keep classes that are not in the removal list
        for _, class_name in ipairs(current_classes) do
            local should_remove = false
            for _, remove_class in ipairs(params.classes) do
                if class_name == remove_class then
                    should_remove = true
                    changes_made = true
                    break
                end
            end
            if not should_remove then
                table.insert(updated_classes, class_name)
            end
        end
    end

    if not changes_made then
        return {
            success = true,
            message = "No changes needed - classes already in desired state",
            agent_id = params.agent_id,
            operation = params.operation,
            classes_count = #updated_classes
        }
    end

    -- Determine the format for the class field
    local class_value
    if #updated_classes == 0 then
        class_value = nil -- Remove the class field entirely
    elseif #updated_classes == 1 then
        class_value = updated_classes[1] -- Single string
    else
        class_value = updated_classes -- Array
    end

    -- Update agent with new classes
    local update_result = update_entry.handler({
        id = params.agent_id,
        meta = {
            class = class_value
        },
        merge = true
    })

    if not update_result.success then
        return {
            success = false,
            error = "Failed to update agent classes: " .. (update_result.error or "unknown error")
        }
    end

    return {
        success = true,
        message = "Agent classes updated successfully",
        agent_id = params.agent_id,
        operation = params.operation,
        classes_count = #updated_classes,
        changes_made = changes_made
    }
end

return {
    handler = handler
}