local registry = require('registry')
local governance = require('governance_client')
local code_utils = require('code_utils')

-- Known system modules (built-in Wippy modules)
local SYSTEM_MODULES = {
    ["http"] = true,
    ["json"] = true,
    ["registry"] = true,
    ["logger"] = true,
    ["yaml"] = true,
    ["sql"] = true,
    ["http_client"] = true,
    ["crypto"] = true,
    ["time"] = true,
    ["fs"] = true,
    ["uuid"] = true,
    ["base64"] = true,
    ["url"] = true,
    ["template"] = true,
    ["config"] = true,
    ["cache"] = true,
    ["queue"] = true,
    ["email"] = true,
    ["pdf"] = true,
    ["image"] = true,
    ["csv"] = true,
    ["xml"] = true,
    ["markdown"] = true,
    ["zip"] = true,
    ["jwt"] = true,
    ["oauth"] = true,
    ["ldap"] = true,
    ["redis"] = true,
    ["mongo"] = true,
    ["postgres"] = true,
    ["mysql"] = true,
    ["sqlite"] = true
}

-- Helper function to deep copy a table
local function deep_copy(t)
    if type(t) ~= "table" then
        return t
    end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deep_copy(v)
    end
    return copy
end

-- Helper function to check if value exists in array
local function array_contains(arr, value)
    for _, v in ipairs(arr) do
        if v == value then
            return true
        end
    end
    return false
end

-- Helper function to remove value from array
local function array_remove(arr, value)
    local new_arr = {}
    for _, v in ipairs(arr) do
        if v ~= value then
            table.insert(new_arr, v)
        end
    end
    return new_arr
end

-- Manage system modules
local function manage_system_module(entry, operation, module_name)
    local modules = entry.data.modules or {}
    local changes_made = false
    local message = ""
    
    if operation == "add" then
        -- Validate it's a known system module
        if not SYSTEM_MODULES[module_name] then
            return nil, "Unknown system module: " .. module_name .. ". Must be a built-in Wippy module."
        end
        
        -- Check if already exists
        if array_contains(modules, module_name) then
            return nil, "System module '" .. module_name .. "' already exists in modules array"
        end
        
        -- Add the module
        table.insert(modules, module_name)
        changes_made = true
        message = "Added system module '" .. module_name .. "'"
        
    elseif operation == "remove" then
        -- Check if exists
        if not array_contains(modules, module_name) then
            return nil, "System module '" .. module_name .. "' not found in modules array"
        end
        
        -- Remove the module
        modules = array_remove(modules, module_name)
        changes_made = true
        message = "Removed system module '" .. module_name .. "'"
        
    elseif operation == "update" then
        return nil, "Update operation not supported for system modules. Use add/remove instead."
    end
    
    return {
        modules = modules,
        changes_made = changes_made,
        message = message
    }
end

-- Manage registry imports
local function manage_registry_import(entry, operation, alias, target_id)
    local imports = entry.data.imports or {}
    local changes_made = false
    local message = ""
    
    if operation == "add" then
        -- Validate target_id is provided
        if not target_id then
            return nil, "Target registry ID is required for adding registry import"
        end
        
        -- Check if alias already exists
        if imports[alias] then
            return nil, "Import alias '" .. alias .. "' already exists. Use update operation to change target."
        end
        
        -- Validate target registry entry exists
        local target_entry, err = registry.get(target_id)
        if not target_entry then
            return nil, "Target registry entry not found: " .. target_id .. " (" .. (err or "unknown error") .. ")"
        end
        
        -- Add the import
        imports[alias] = target_id
        changes_made = true
        message = "Added registry import '" .. alias .. "' -> '" .. target_id .. "'"
        
    elseif operation == "remove" then
        -- Check if exists
        if not imports[alias] then
            return nil, "Import alias '" .. alias .. "' not found in imports"
        end
        
        -- Remove the import
        local old_target = imports[alias]
        imports[alias] = nil
        changes_made = true
        message = "Removed registry import '" .. alias .. "' (was pointing to '" .. old_target .. "')"
        
    elseif operation == "update" then
        -- Validate target_id is provided
        if not target_id then
            return nil, "Target registry ID is required for updating registry import"
        end
        
        -- Check if alias exists
        if not imports[alias] then
            return nil, "Import alias '" .. alias .. "' not found in imports. Use add operation to create new import."
        end
        
        -- Check if target is the same
        if imports[alias] == target_id then
            return nil, "Import alias '" .. alias .. "' already points to '" .. target_id .. "'. No change needed."
        end
        
        -- Validate target registry entry exists
        local target_entry, err = registry.get(target_id)
        if not target_entry then
            return nil, "Target registry entry not found: " .. target_id .. " (" .. (err or "unknown error") .. ")"
        end
        
        -- Update the import
        local old_target = imports[alias]
        imports[alias] = target_id
        changes_made = true
        message = "Updated registry import '" .. alias .. "' from '" .. old_target .. "' to '" .. target_id .. "'"
    end
    
    return {
        imports = imports,
        changes_made = changes_made,
        message = message
    }
end

local function handler(params)
    -- Input validation
    if not params or type(params) ~= "table" then
        return {
            success = false,
            error = "Invalid input: params must be a table"
        }
    end
    
    -- Validate required parameters
    if not params.code_id or type(params.code_id) ~= "string" or params.code_id == "" then
        return {
            success = false,
            error = "Missing or invalid required parameter: code_id (must be non-empty string)"
        }
    end
    
    if not params.dependency_type or type(params.dependency_type) ~= "string" then
        return {
            success = false,
            error = "Missing or invalid required parameter: dependency_type (must be 'system_module' or 'registry_import')"
        }
    end
    
    if params.dependency_type ~= "system_module" and params.dependency_type ~= "registry_import" then
        return {
            success = false,
            error = "Invalid dependency_type: '" .. params.dependency_type .. "'. Must be 'system_module' or 'registry_import'"
        }
    end
    
    if not params.operation or type(params.operation) ~= "string" then
        return {
            success = false,
            error = "Missing or invalid required parameter: operation (must be 'add', 'remove', or 'update')"
        }
    end
    
    if params.operation ~= "add" and params.operation ~= "remove" and params.operation ~= "update" then
        return {
            success = false,
            error = "Invalid operation: '" .. params.operation .. "'. Must be 'add', 'remove', or 'update'"
        }
    end
    
    if not params.name or type(params.name) ~= "string" or params.name == "" then
        return {
            success = false,
            error = "Missing or invalid required parameter: name (must be non-empty string)"
        }
    end
    
    -- Validate target parameter for registry_import operations
    if params.dependency_type == "registry_import" and (params.operation == "add" or params.operation == "update") then
        if not params.target or type(params.target) ~= "string" or params.target == "" then
            return {
                success = false,
                error = "Missing or invalid parameter: target (required for registry_import add/update operations)"
            }
        end
    end
    
    -- Get the code entry
    local entry, err = code_utils.get_entry(params.code_id)
    if not entry then
        return {
            success = false,
            error = err
        }
    end
    
    -- Perform the dependency management operation
    local result, operation_err
    
    if params.dependency_type == "system_module" then
        result, operation_err = manage_system_module(entry, params.operation, params.name)
    else -- registry_import
        result, operation_err = manage_registry_import(entry, params.operation, params.name, params.target)
    end
    
    if not result then
        return {
            success = false,
            error = operation_err
        }
    end
    
    -- If no changes were made, return early
    if not result.changes_made then
        return {
            success = true,
            message = result.message,
            changes_made = false,
            code_id = params.code_id
        }
    end
    
    -- Prepare updated entry data
    local updated_entry = deep_copy(entry)
    
    if params.dependency_type == "system_module" then
        updated_entry.data.modules = result.modules
    else -- registry_import
        updated_entry.data.imports = result.imports
    end
    
    -- Apply changes using registry changeset
    local changes = registry.snapshot():changes()
    changes:update(updated_entry)
    
    local version, apply_err = governance.request_changes(changes)
    if not version then
        return {
            success = false,
            error = "Failed to apply dependency changes: " .. (apply_err or "unknown error")
        }
    end
    
    -- Return success
    return {
        success = true,
        message = result.message,
        changes_made = true,
        code_id = params.code_id,
        dependency_type = params.dependency_type,
        operation = params.operation,
        name = params.name,
        target = params.target,
        version = version.version
    }
end

return {
    handler = handler
}