local registry = require("registry")
local json = require("json")
local agent_registry = require("agent_registry")

-- Function to check for circular inheritance
local function check_circular_inheritance(agent_id, parent_id, visited)
    visited = visited or {}
    
    -- If we've already visited this agent, we have a cycle
    if visited[agent_id] then
        return true
    end
    
    -- If we reach the parent we're trying to add, we have a cycle
    if agent_id == parent_id then
        return true
    end
    
    -- Mark this agent as visited
    visited[agent_id] = true
    
    -- Get the agent's current inheritance
    local agent_entry, err = registry.get(agent_id)
    if not agent_entry or not agent_entry.data or not agent_entry.data.inherit then
        return false
    end
    
    -- Check all current parents recursively
    for _, current_parent in ipairs(agent_entry.data.inherit) do
        if check_circular_inheritance(current_parent, parent_id, visited) then
            return true
        end
    end
    
    return false
end

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

    if not params.parents or type(params.parents) ~= "table" then
        return {
            success = false,
            error = "Missing or invalid required parameter: parents (must be array)"
        }
    end

    if #params.parents == 0 then
        return {
            success = false,
            error = "Parents array cannot be empty"
        }
    end

    -- Validate all parent IDs are strings
    for i, parent_id in ipairs(params.parents) do
        if type(parent_id) ~= "string" or parent_id == "" then
            return {
                success = false,
                error = "Parent ID at index " .. i .. " must be a non-empty string"
            }
        end
    end

    -- Get agent entry to validate existence and type
    local agent_entry, err = registry.get(params.agent_id)
    if not agent_entry then
        return {
            success = false,
            error = "Agent not found: " .. params.agent_id .. " (" .. (err or "unknown error") .. ")"
        }
    end

    if not agent_entry.meta or agent_entry.meta.type ~= "agent.gen1" then
        return {
            success = false,
            error = "Entry is not a valid agent.gen1: " .. params.agent_id
        }
    end

    -- For add operation, validate parent agents and check for circular inheritance
    if params.operation == "add" then
        for _, parent_id in ipairs(params.parents) do
            -- Check if parent agent exists and is agent.gen1
            local parent_entry, err = registry.get(parent_id)
            if not parent_entry then
                return {
                    success = false,
                    error = "Parent agent not found: " .. parent_id .. " (" .. (err or "unknown error") .. ")"
                }
            end
            
            if not parent_entry.meta or parent_entry.meta.type ~= "agent.gen1" then
                return {
                    success = false,
                    error = "Parent entry is not a valid agent.gen1: " .. parent_id
                }
            end
            
            -- Check for self-inheritance
            if parent_id == params.agent_id then
                return {
                    success = false,
                    error = "Agent cannot inherit from itself: " .. parent_id
                }
            end
            
            -- Check for circular inheritance
            if check_circular_inheritance(parent_id, params.agent_id) then
                return {
                    success = false,
                    error = "Adding parent " .. parent_id .. " would create circular inheritance"
                }
            end
        end
    end

    -- Get current inherit array
    local current_parents = {}
    if agent_entry.data and agent_entry.data.inherit and type(agent_entry.data.inherit) == "table" then
        for _, parent_id in ipairs(agent_entry.data.inherit) do
            table.insert(current_parents, parent_id)
        end
    end

    -- Perform operation
    local updated_parents = {}
    local changes_made = false

    if params.operation == "add" then
        -- Start with current parents
        for _, parent_id in ipairs(current_parents) do
            table.insert(updated_parents, parent_id)
        end
        
        -- Add new parents (avoid duplicates)
        for _, parent_id in ipairs(params.parents) do
            local already_exists = false
            for _, existing_parent in ipairs(updated_parents) do
                if existing_parent == parent_id then
                    already_exists = true
                    break
                end
            end
            if not already_exists then
                table.insert(updated_parents, parent_id)
                changes_made = true
            end
        end
    elseif params.operation == "remove" then
        -- Keep parents that are not in the removal list
        for _, parent_id in ipairs(current_parents) do
            local should_remove = false
            for _, remove_parent in ipairs(params.parents) do
                if parent_id == remove_parent then
                    should_remove = true
                    changes_made = true
                    break
                end
            end
            if not should_remove then
                table.insert(updated_parents, parent_id)
            end
        end
    end

    if not changes_made then
        return {
            success = true,
            message = "No changes needed - inheritance already in desired state",
            agent_id = params.agent_id,
            operation = params.operation,
            parents_count = #updated_parents
        }
    end

    -- Update agent with new inherit array
    local update_result, err = registry.update({
        id = params.agent_id,
        data = {
            inherit = updated_parents
        },
        merge = true
    })

    if not update_result then
        return {
            success = false,
            error = "Failed to update agent inheritance: " .. (err or "unknown error")
        }
    end

    return {
        success = true,
        message = "Agent inheritance updated successfully",
        agent_id = params.agent_id,
        operation = params.operation,
        parents_count = #updated_parents,
        changes_made = changes_made
    }
end

return {
    handler = handler
}