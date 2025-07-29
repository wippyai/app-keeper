local json = require("json")
local yaml = require("yaml")
local get_entries = require("get_entries")
local update_entry = require("update_entry")

-- Simple Agent Metadata Updater Tool
-- Updates metadata fields for a single agent with basic validation
-- Returns: Single result table with success boolean and error

local function handler(params)
    -- Validate input parameters
    if not params.agent_id or type(params.agent_id) ~= "string" or params.agent_id == "" then
        return {
            success = false,
            error = "Missing or invalid required parameter: agent_id"
        }
    end

    if not params.metadata_updates or type(params.metadata_updates) ~= "table" then
        return {
            success = false,
            error = "Missing or invalid required parameter: metadata_updates"
        }
    end

    -- Check if any updates are provided
    local has_updates = false
    for _ in pairs(params.metadata_updates) do
        has_updates = true
        break
    end
    
    if not has_updates then
        return {
            success = false,
            error = "No metadata updates provided"
        }
    end

    -- Fetch agent data to validate existence and type
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

    -- Basic validation of metadata updates
    for key, value in pairs(params.metadata_updates) do
        if type(value) == "string" and value == "" then
            return {
                success = false,
                error = "String field '" .. key .. "' cannot be empty"
            }
        end
        if key == "tags" and type(value) ~= "table" then
            return {
                success = false,
                error = "Tags must be an array"
            }
        end
    end

    -- Apply updates using update_entry with merge=true
    local update_result = update_entry.handler({
        id = params.agent_id,
        meta = params.metadata_updates,
        merge = true
    })

    if not update_result.success then
        return {
            success = false,
            error = "Failed to update agent metadata: " .. (update_result.error or "unknown error")
        }
    end

    return {
        success = true,
        message = "Agent metadata updated successfully",
        agent_id = params.agent_id
    }
end

return {
    handler = handler
}