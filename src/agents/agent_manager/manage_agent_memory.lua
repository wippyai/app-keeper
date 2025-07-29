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

    if params.operation ~= "add" and params.operation ~= "remove" then
        return {
            success = false,
            error = "Invalid operation. Must be 'add' or 'remove'"
        }
    end

    if not params.memory_items or type(params.memory_items) ~= "table" then
        return {
            success = false,
            error = "Missing or invalid required parameter: memory_items (must be array)"
        }
    end

    if #params.memory_items == 0 then
        return {
            success = false,
            error = "Memory items array cannot be empty"
        }
    end

    -- Validate all memory items are strings
    for i, memory_item in ipairs(params.memory_items) do
        if type(memory_item) ~= "string" or memory_item == "" then
            return {
                success = false,
                error = "Memory item at index " .. i .. " must be a non-empty string"
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

    -- Get current memory array
    local current_memory = {}
    if agent_entry.data and agent_entry.data.memory and type(agent_entry.data.memory) == "table" then
        for _, memory_item in ipairs(agent_entry.data.memory) do
            table.insert(current_memory, memory_item)
        end
    end

    -- Perform operation
    local updated_memory = {}
    local changes_made = false

    if params.operation == "add" then
        -- Start with current memory
        for _, memory_item in ipairs(current_memory) do
            table.insert(updated_memory, memory_item)
        end
        
        -- Add new memory items (avoid duplicates)
        for _, memory_item in ipairs(params.memory_items) do
            local already_exists = false
            for _, existing_memory in ipairs(updated_memory) do
                if existing_memory == memory_item then
                    already_exists = true
                    break
                end
            end
            if not already_exists then
                table.insert(updated_memory, memory_item)
                changes_made = true
            end
        end
    elseif params.operation == "remove" then
        -- Keep memory items that are not in the removal list
        for _, memory_item in ipairs(current_memory) do
            local should_remove = false
            for _, remove_memory in ipairs(params.memory_items) do
                if memory_item == remove_memory then
                    should_remove = true
                    changes_made = true
                    break
                end
            end
            if not should_remove then
                table.insert(updated_memory, memory_item)
            end
        end
    end

    if not changes_made then
        return {
            success = true,
            message = "No changes needed - memory already in desired state",
            agent_id = params.agent_id,
            operation = params.operation,
            memory_count = #updated_memory
        }
    end

    -- Update agent with new memory array
    local update_result = update_entry.handler({
        id = params.agent_id,
        data = {
            memory = updated_memory
        },
        merge = true
    })

    if not update_result.success then
        return {
            success = false,
            error = "Failed to update agent memory: " .. (update_result.error or "unknown error")
        }
    end

    return {
        success = true,
        message = "Agent memory updated successfully",
        agent_id = params.agent_id,
        operation = params.operation,
        memory_count = #updated_memory,
        changes_made = changes_made
    }
end

return {
    handler = handler
}