local registry = require("registry")
local json = require("json")
local traits = require("traits")

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

    if not params.traits or type(params.traits) ~= "table" then
        return {
            success = false,
            error = "Missing or invalid required parameter: traits (must be array)"
        }
    end

    if #params.traits == 0 then
        return {
            success = false,
            error = "Traits array cannot be empty"
        }
    end

    -- Validate all trait identifiers are strings
    for i, trait_id in ipairs(params.traits) do
        if type(trait_id) ~= "string" or trait_id == "" then
            return {
                success = false,
                error = "Trait identifier at index " .. i .. " must be a non-empty string"
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

    -- For add operation, validate that traits exist
    if params.operation == "add" then
        for _, trait_id in ipairs(params.traits) do
            -- Try to get trait by name first, then by ID
            local trait, err = traits.get_by_name(trait_id)
            if not trait then
                trait, err = traits.get_by_id(trait_id)
            end
            
            if not trait then
                return {
                    success = false,
                    error = "Trait not found: " .. trait_id .. " (" .. (err or "unknown error") .. ")"
                }
            end
        end
    end

    -- Get current traits array
    local current_traits = {}
    if agent_entry.data and agent_entry.data.traits and type(agent_entry.data.traits) == "table" then
        for _, trait_id in ipairs(agent_entry.data.traits) do
            table.insert(current_traits, trait_id)
        end
    end

    -- Perform operation
    local updated_traits = {}
    local changes_made = false

    if params.operation == "add" then
        -- Start with current traits
        for _, trait_id in ipairs(current_traits) do
            table.insert(updated_traits, trait_id)
        end
        
        -- Add new traits (avoid duplicates)
        for _, trait_id in ipairs(params.traits) do
            local already_exists = false
            for _, existing_trait in ipairs(updated_traits) do
                if existing_trait == trait_id then
                    already_exists = true
                    break
                end
            end
            if not already_exists then
                table.insert(updated_traits, trait_id)
                changes_made = true
            end
        end
    elseif params.operation == "remove" then
        -- Keep traits that are not in the removal list
        for _, trait_id in ipairs(current_traits) do
            local should_remove = false
            for _, remove_trait in ipairs(params.traits) do
                if trait_id == remove_trait then
                    should_remove = true
                    changes_made = true
                    break
                end
            end
            if not should_remove then
                table.insert(updated_traits, trait_id)
            end
        end
    end

    if not changes_made then
        return {
            success = true,
            message = "No changes needed - traits already in desired state",
            agent_id = params.agent_id,
            operation = params.operation,
            traits_count = #updated_traits
        }
    end

    -- Update agent with new traits array
    local update_result, err = registry.update({
        id = params.agent_id,
        data = {
            traits = updated_traits
        },
        merge = true
    })

    if not update_result then
        return {
            success = false,
            error = "Failed to update agent traits: " .. (err or "unknown error")
        }
    end

    return {
        success = true,
        message = "Agent traits updated successfully",
        agent_id = params.agent_id,
        operation = params.operation,
        traits_count = #updated_traits,
        changes_made = changes_made
    }
end

return {
    handler = handler
}