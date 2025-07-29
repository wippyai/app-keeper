local registry = require("registry")
local json = require("json")

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

    if params.operation ~= "add" and params.operation ~= "update" and params.operation ~= "remove" then
        return {
            success = false,
            error = "Invalid operation. Must be 'add', 'update', or 'remove'"
        }
    end

    if not params.delegation_config or type(params.delegation_config) ~= "table" then
        return {
            success = false,
            error = "Missing or invalid required parameter: delegation_config (must be object)"
        }
    end

    if not params.delegation_config.target_id or type(params.delegation_config.target_id) ~= "string" or params.delegation_config.target_id == "" then
        return {
            success = false,
            error = "Missing or invalid delegation_config.target_id"
        }
    end

    -- For add and update operations, name and rule are required
    if (params.operation == "add" or params.operation == "update") then
        if not params.delegation_config.name or type(params.delegation_config.name) ~= "string" or params.delegation_config.name == "" then
            return {
                success = false,
                error = "delegation_config.name is required for add/update operations"
            }
        end
        
        if not params.delegation_config.rule or type(params.delegation_config.rule) ~= "string" or params.delegation_config.rule == "" then
            return {
                success = false,
                error = "delegation_config.rule is required for add/update operations"
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

    -- For add and update operations, validate target agent exists and is agent.gen1
    if params.operation == "add" or params.operation == "update" then
        local target_entry, err = registry.get(params.delegation_config.target_id)
        if not target_entry then
            return {
                success = false,
                error = "Target agent not found: " .. params.delegation_config.target_id .. " (" .. (err or "unknown error") .. ")"
            }
        end
        
        if not target_entry.meta or target_entry.meta.type ~= "agent.gen1" then
            return {
                success = false,
                error = "Target entry is not a valid agent.gen1: " .. params.delegation_config.target_id
            }
        end
        
        -- Check for self-delegation
        if params.delegation_config.target_id == params.agent_id then
            return {
                success = false,
                error = "Agent cannot delegate to itself: " .. params.delegation_config.target_id
            }
        end
    end

    -- Get current delegate object
    local current_delegate = {}
    if agent_entry.data and agent_entry.data.delegate and type(agent_entry.data.delegate) == "table" then
        -- Deep copy the current delegate object
        for target_id, config in pairs(agent_entry.data.delegate) do
            current_delegate[target_id] = {
                name = config.name,
                rule = config.rule
            }
        end
    end

    -- Perform operation
    local updated_delegate = {}
    local changes_made = false

    -- Start with current delegate
    for target_id, config in pairs(current_delegate) do
        updated_delegate[target_id] = {
            name = config.name,
            rule = config.rule
        }
    end

    if params.operation == "add" then
        -- Check if target already exists
        if updated_delegate[params.delegation_config.target_id] then
            return {
                success = false,
                error = "Delegation rule already exists for target: " .. params.delegation_config.target_id .. ". Use 'update' operation to modify."
            }
        end
        
        -- Add new delegation rule
        updated_delegate[params.delegation_config.target_id] = {
            name = params.delegation_config.name,
            rule = params.delegation_config.rule
        }
        changes_made = true
        
    elseif params.operation == "update" then
        -- Check if target exists
        if not updated_delegate[params.delegation_config.target_id] then
            return {
                success = false,
                error = "Delegation rule does not exist for target: " .. params.delegation_config.target_id .. ". Use 'add' operation to create."
            }
        end
        
        -- Check if there are actual changes
        local current_config = updated_delegate[params.delegation_config.target_id]
        if current_config.name ~= params.delegation_config.name or current_config.rule ~= params.delegation_config.rule then
            updated_delegate[params.delegation_config.target_id] = {
                name = params.delegation_config.name,
                rule = params.delegation_config.rule
            }
            changes_made = true
        end
        
    elseif params.operation == "remove" then
        -- Check if target exists
        if not updated_delegate[params.delegation_config.target_id] then
            return {
                success = false,
                error = "Delegation rule does not exist for target: " .. params.delegation_config.target_id
            }
        end
        
        -- Remove delegation rule
        updated_delegate[params.delegation_config.target_id] = nil
        changes_made = true
    end

    if not changes_made then
        return {
            success = true,
            message = "No changes needed - delegation already in desired state",
            agent_id = params.agent_id,
            operation = params.operation,
            target_id = params.delegation_config.target_id
        }
    end

    -- Count remaining delegations
    local delegation_count = 0
    for _ in pairs(updated_delegate) do
        delegation_count = delegation_count + 1
    end

    -- If no delegations remain, set to nil to remove the field
    local delegate_value = delegation_count > 0 and updated_delegate or nil

    -- Update agent with new delegate object
    local update_result, err = registry.update({
        id = params.agent_id,
        data = {
            delegate = delegate_value
        },
        merge = true
    })

    if not update_result then
        return {
            success = false,
            error = "Failed to update agent delegation: " .. (err or "unknown error")
        }
    end

    return {
        success = true,
        message = "Agent delegation updated successfully",
        agent_id = params.agent_id,
        operation = params.operation,
        target_id = params.delegation_config.target_id,
        delegation_count = delegation_count,
        changes_made = changes_made
    }
end

return {
    handler = handler
}