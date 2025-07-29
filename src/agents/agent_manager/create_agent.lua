local json = require("json")
local find_entries = require("find_entries")
local create_entry = require("create_entry")

local function handler(params)
    -- Validate required parameters
    if not params.agent_id then
        return {
            success = false,
            error = "Missing required parameter: agent_id"
        }
    end
    
    if not params.prompt then
        return {
            success = false,
            error = "Missing required parameter: prompt"
        }
    end
    
    if not params.comment then
        return {
            success = false,
            error = "Missing required parameter: comment"
        }
    end
    
    -- Validate agent_id format (must be namespace:name)
    local namespace, name = params.agent_id:match("^([^:]+):([^:]+)$")
    if not namespace or not name or namespace == "" or name == "" then
        return {
            success = false,
            error = "Invalid agent_id format. Must be 'namespace:name' with exactly one colon and non-empty parts"
        }
    end
    
    -- Check if agent already exists
    local existing_check = find_entries.handler({
        namespace = namespace,
        name = name
    })
    
    if not existing_check.success then
        return {
            success = false,
            error = "Failed to check for existing agent: " .. (existing_check.error or "unknown error")
        }
    end
    
    if existing_check.entries and #existing_check.entries > 0 then
        return {
            success = false,
            error = "Agent already exists with ID: " .. params.agent_id
        }
    end
    
    -- Set default values for optional parameters
    local model = params.model or "gpt-4.1"
    local max_tokens = params.max_tokens or 4096
    local temperature = params.temperature or 0.7
    local thinking_effort = params.thinking_effort or 0
    
    -- Validate numeric parameters
    if type(max_tokens) ~= "number" or max_tokens <= 0 then
        return {
            success = false,
            error = "max_tokens must be a positive number"
        }
    end
    
    if type(temperature) ~= "number" or temperature < 0 or temperature > 1 then
        return {
            success = false,
            error = "temperature must be a number between 0.0 and 1.0"
        }
    end
    
    if type(thinking_effort) ~= "number" or thinking_effort < 0 or thinking_effort > 100 then
        return {
            success = false,
            error = "thinking_effort must be a number between 0 and 100"
        }
    end
    
    -- Validate array parameters
    local function validate_array(param_name, param_value)
        if param_value ~= nil then
            if type(param_value) ~= "table" then
                return false, param_name .. " must be an array"
            end
            for i, item in ipairs(param_value) do
                if type(item) ~= "string" then
                    return false, param_name .. " must contain only strings"
                end
            end
        end
        return true
    end
    
    local valid, err = validate_array("memory", params.memory)
    if not valid then
        return { success = false, error = err }
    end
    
    valid, err = validate_array("tools", params.tools)
    if not valid then
        return { success = false, error = err }
    end
    
    valid, err = validate_array("traits", params.traits)
    if not valid then
        return { success = false, error = err }
    end
    
    valid, err = validate_array("inherit", params.inherit)
    if not valid then
        return { success = false, error = err }
    end
    
    valid, err = validate_array("tags", params.tags)
    if not valid then
        return { success = false, error = err }
    end
    
    -- Build metadata object
    local meta = {
        type = "agent.gen1",
        name = params.title or name:gsub("_", " "):gsub("-", " "),
        comment = params.comment
    }
    
    -- Add optional metadata fields
    if params.title then
        meta.title = params.title
    end
    
    if params.icon then
        meta.icon = params.icon
    end
    
    if params.tags then
        meta.tags = params.tags
    end
    
    if params.group then
        meta.group = params.group
    end
    
    if params.class then
        meta.class = params.class
    end
    
    -- Build data object
    local data = {
        prompt = params.prompt,
        model = model,
        max_tokens = max_tokens,
        temperature = temperature
    }
    
    -- Add thinking_effort if specified
    if thinking_effort > 0 then
        data.thinking_effort = thinking_effort
    end
    
    -- Add optional data fields
    if params.memory then
        data.memory = params.memory
    end
    
    if params.tools then
        data.tools = params.tools
    end
    
    if params.traits then
        data.traits = params.traits
    end
    
    if params.inherit then
        data.inherit = params.inherit
    end
    
    -- Create the registry entry
    local create_result = create_entry.handler({
        namespace = namespace,
        name = name,
        kind = "registry.entry",
        meta = meta,
        data = data
    })
    
    if not create_result.success then
        return {
            success = false,
            error = "Failed to create agent entry: " .. (create_result.error or "unknown error")
        }
    end
    
    -- Return success response
    return {
        success = true,
        message = "Agent created successfully",
        agent_id = params.agent_id,
        namespace = namespace,
        name = name,
        version = create_result.version,
        details = create_result.details
    }
end

return {
    handler = handler
}