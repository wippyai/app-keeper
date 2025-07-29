local json = require("json")
local yaml = require("yaml")
local get_entries = require("get_entries")
local update_entry = require("update_entry")

-- Constants
local VALID_OPERATIONS = {
    add = true,
    remove = true,
    set = true
}

-- Helper function to detect wildcard tool patterns
local function is_wildcard_tool(tool_id)
    -- Wildcard tools end with ":*" pattern (e.g., "namespace:*")
    return type(tool_id) == "string" and tool_id:match(":*$") ~= nil
end

-- Helper function to deduplicate tool array while preserving order
local function deduplicate_tools(tools)
    if not tools or type(tools) ~= "table" then
        return {}
    end
    
    local seen = {}
    local result = {}
    
    for _, tool_id in ipairs(tools) do
        if type(tool_id) == "string" and tool_id ~= "" and not seen[tool_id] then
            seen[tool_id] = true
            table.insert(result, tool_id)
        end
    end
    
    return result
end

-- Helper function to remove all instances of tools from array
local function remove_tools_from_array(current_tools, tools_to_remove)
    local remove_set = {}
    for _, tool_id in ipairs(tools_to_remove) do
        remove_set[tool_id] = true
    end
    
    local result = {}
    for _, tool_id in ipairs(current_tools) do
        if not remove_set[tool_id] then
            table.insert(result, tool_id)
        end
    end
    
    return result
end

-- Helper function to add tools to array (avoiding duplicates)
local function add_tools_to_array(current_tools, tools_to_add)
    local existing_set = {}
    for _, tool_id in ipairs(current_tools) do
        existing_set[tool_id] = true
    end
    
    local result = {}
    -- Add existing tools first
    for _, tool_id in ipairs(current_tools) do
        table.insert(result, tool_id)
    end
    
    -- Add new tools if they don't already exist
    for _, tool_id in ipairs(tools_to_add) do
        if not existing_set[tool_id] then
            table.insert(result, tool_id)
        end
    end
    
    return result
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

    if not VALID_OPERATIONS[params.operation] then
        return {
            success = false,
            error = "Invalid operation. Must be 'add', 'remove', or 'set'"
        }
    end

    if not params.tools or type(params.tools) ~= "table" then
        return {
            success = false,
            error = "Missing or invalid required parameter: tools (must be array)"
        }
    end

    if #params.tools == 0 then
        return {
            success = false,
            error = "Tools array cannot be empty"
        }
    end

    -- Validate all tool IDs are strings
    for i, tool_id in ipairs(params.tools) do
        if type(tool_id) ~= "string" or tool_id == "" then
            return {
                success = false,
                error = "Tool ID at index " .. i .. " must be a non-empty string"
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

    -- For add and set operations, validate tools (but skip wildcards)
    if params.operation == "add" or params.operation == "set" then
        -- Separate explicit tool IDs from wildcards
        local explicit_tool_ids = {}
        local wildcard_tools = {}
        
        for _, tool_id in ipairs(params.tools) do
            if is_wildcard_tool(tool_id) then
                -- Wildcard patterns (e.g., "namespace:*") are resolved at runtime
                -- and don't need registry validation
                table.insert(wildcard_tools, tool_id)
            else
                -- Explicit tool IDs need to be validated against the registry
                table.insert(explicit_tool_ids, tool_id)
            end
        end
        
        -- Only validate explicit tool IDs if there are any
        if #explicit_tool_ids > 0 then
            local tools_result_yaml = get_entries.handler({
                ids = explicit_tool_ids
            })
            
            local tools_result, tools_decode_err = yaml.decode(tools_result_yaml)
            if not tools_result then
                return {
                    success = false,
                    error = "Failed to decode tools validation response: " .. (tools_decode_err or "unknown error")
                }
            end
            
            if not tools_result.success then
                return {
                    success = false,
                    error = "Failed to validate tools: " .. (tools_result.error or "unknown error")
                }
            end
            
            -- Check if any explicit tools are missing
            if tools_result.missing_ids and #tools_result.missing_ids > 0 then
                return {
                    success = false,
                    error = "Tool(s) not found in registry: " .. table.concat(tools_result.missing_ids, ", ")
                }
            end
            
            -- Check if found entries are actually tools
            for _, tool_entry in ipairs(tools_result.result) do
                if tool_entry.meta and tool_entry.meta.type and tool_entry.meta.type ~= "tool" then
                    return {
                        success = false,
                        error = "Entry is not a tool: " .. tool_entry.id .. " (type: " .. tostring(tool_entry.meta.type) .. ")"
                    }
                end
            end
        end
        
        -- Note: Wildcard tools are allowed without validation since they resolve at runtime
        -- The agent runtime will expand "namespace:*" to all tools in that namespace
    end

    -- Get current tools array
    local current_tools = {}
    if agent_entry.data and agent_entry.data.tools and type(agent_entry.data.tools) == "table" then
        for _, tool_id in ipairs(agent_entry.data.tools) do
            table.insert(current_tools, tool_id)
        end
    end

    -- Perform operation
    local updated_tools = {}
    local changes_made = false

    if params.operation == "add" then
        -- Add new tools to existing ones
        updated_tools = add_tools_to_array(current_tools, params.tools)
        changes_made = (#updated_tools ~= #current_tools)
        
    elseif params.operation == "remove" then
        -- Remove ALL instances of specified tools
        updated_tools = remove_tools_from_array(current_tools, params.tools)
        changes_made = (#updated_tools ~= #current_tools)
        
    elseif params.operation == "set" then
        -- Replace entire tools array with provided list
        updated_tools = {}
        for _, tool_id in ipairs(params.tools) do
            table.insert(updated_tools, tool_id)
        end
        changes_made = true -- Always consider set operation as a change
    end

    -- Always deduplicate the final tools array
    updated_tools = deduplicate_tools(updated_tools)

    if not changes_made and params.operation ~= "set" then
        return {
            success = true,
            message = "No changes needed - tools already in desired state",
            agent_id = params.agent_id,
            operation = params.operation,
            tools_count = #updated_tools
        }
    end

    -- Update agent with new tools array
    local update_result = update_entry.handler({
        id = params.agent_id,
        data = {
            tools = updated_tools
        },
        merge = true
    })

    if not update_result.success then
        return {
            success = false,
            error = "Failed to update agent tools: " .. (update_result.error or "unknown error")
        }
    end

    return {
        success = true,
        message = "Agent tools updated successfully",
        agent_id = params.agent_id,
        operation = params.operation,
        tools_count = #updated_tools,
        changes_made = changes_made
    }
end

return {
    handler = handler
}