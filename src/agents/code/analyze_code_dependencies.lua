local registry = require("registry")
local code_utils = require("code_utils")

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

-- Extract all require() statements from source code
local function extract_require_statements(source)
    local requires = {}
    
    if not source or type(source) ~= "string" then
        return requires
    end
    
    -- Pattern to match require("module_name") or require('module_name')
    for module_name in source:gmatch('require%s*%(%s*["\']([^"\']+)["\']%s*%)') do
        requires[module_name] = true
    end
    
    return requires
end

-- Analyze system modules
local function analyze_system_modules(declared_modules, used_requires)
    local analysis = {
        declared = {},
        used_in_source = {},
        missing_declarations = {},
        unused_declarations = {}
    }
    
    -- Analyze declared modules
    for _, module in ipairs(declared_modules or {}) do
        local status = SYSTEM_MODULES[module] and "valid" or "unknown"
        table.insert(analysis.declared, {
            name = module,
            status = status,
            is_system_module = SYSTEM_MODULES[module] or false
        })
        
        -- Check if declared module is actually used
        if not used_requires[module] then
            table.insert(analysis.unused_declarations, module)
        end
    end
    
    -- Find system modules used in source but not declared
    for module, _ in pairs(used_requires) do
        if SYSTEM_MODULES[module] then
            table.insert(analysis.used_in_source, {
                name = module,
                status = "valid",
                is_system_module = true
            })
            
            -- Check if used but not declared
            local is_declared = false
            for _, declared_module in ipairs(declared_modules or {}) do
                if declared_module == module then
                    is_declared = true
                    break
                end
            end
            
            if not is_declared then
                table.insert(analysis.missing_declarations, module)
            end
        end
    end
    
    return analysis
end

-- Analyze registry imports
local function analyze_registry_imports(declared_imports, used_requires)
    local analysis = {
        declared = {},
        used_in_source = {},
        missing_declarations = {},
        unused_declarations = {}
    }
    
    -- Analyze declared imports
    for alias, registry_id in pairs(declared_imports or {}) do
        local entry, err = registry.get(registry_id)
        local status = entry and "exists" or "not_found"
        local target_comment = entry and entry.meta and entry.meta.comment or nil
        
        table.insert(analysis.declared, {
            alias = alias,
            registry_id = registry_id,
            status = status,
            target_comment = target_comment,
            error = err
        })
        
        -- Check if declared import is actually used
        if not used_requires[alias] then
            table.insert(analysis.unused_declarations, {
                alias = alias,
                registry_id = registry_id
            })
        end
    end
    
    -- Find non-system modules used in source
    for module, _ in pairs(used_requires) do
        if not SYSTEM_MODULES[module] then
            table.insert(analysis.used_in_source, {
                alias = module,
                status = "unknown_source"
            })
            
            -- Check if used but not declared as import
            local is_declared = false
            for alias, _ in pairs(declared_imports or {}) do
                if alias == module then
                    is_declared = true
                    break
                end
            end
            
            if not is_declared then
                table.insert(analysis.missing_declarations, module)
            end
        end
    end
    
    return analysis
end

local function handler(params)
    -- Input validation
    if not params or not params.code_id then
        return {
            success = false,
            error = "Missing required parameter: code_id"
        }
    end
    
    if type(params.code_id) ~= "string" then
        return {
            success = false,
            error = "Invalid parameter: code_id must be a string"
        }
    end
    
    -- Get the code entry
    local entry, err = code_utils.get_entry(params.code_id)
    if not entry then
        return {
            success = false,
            error = err
        }
    end
    
    -- Extract source code
    local source = ""
    if entry.data and entry.data.source then
        source = entry.data.source
    end
    
    -- Extract require statements from source
    local used_requires = extract_require_statements(source)
    
    -- Get declared dependencies
    local declared_modules = entry.data and entry.data.modules or {}
    local declared_imports = entry.data and entry.data.imports or {}
    
    -- Analyze system modules
    local system_analysis = analyze_system_modules(declared_modules, used_requires)
    
    -- Analyze registry imports
    local imports_analysis = analyze_registry_imports(declared_imports, used_requires)
    
    -- Create summary
    local summary = {
        total_declared_modules = #declared_modules,
        total_declared_imports = 0,
        total_used_requires = 0,
        system_modules_missing = #system_analysis.missing_declarations,
        system_modules_unused = #system_analysis.unused_declarations,
        imports_missing = #imports_analysis.missing_declarations,
        imports_unused = #imports_analysis.unused_declarations
    }
    
    -- Count declared imports
    for _, _ in pairs(declared_imports) do
        summary.total_declared_imports = summary.total_declared_imports + 1
    end
    
    -- Count used requires
    for _, _ in pairs(used_requires) do
        summary.total_used_requires = summary.total_used_requires + 1
    end
    
    -- Return comprehensive analysis
    return {
        success = true,
        entry_id = params.code_id,
        entry_kind = entry.kind,
        summary = summary,
        system_modules = {
            description = "Built-in Wippy modules (like 'http', 'json', 'registry') declared in the modules array",
            analysis = system_analysis
        },
        registry_imports = {
            description = "Other registry entries imported via the imports object (alias -> registry_id mappings)",
            analysis = imports_analysis
        },
        source_analysis = {
            description = "All require() statements found in the source code",
            requires_found = {},
            total_requires = summary.total_used_requires
        }
    }
end

return {
    handler = handler
}