local registry = require("registry")
local json = require("json")

-- Agent Configuration Analyzer Tool
-- Provides comprehensive analysis of agent configuration including inheritance, tools, delegation, and recommendations

local function handler(params)
    local response = {
        success = false,
        agent_id = params.agent_id,
        analysis = {},
        error = nil
    }

    -- Validate input
    if not params.agent_id or type(params.agent_id) ~= "string" or params.agent_id == "" then
        response.error = "Missing or invalid required parameter: agent_id (must be a non-empty string)"
        return response
    end

    -- Fetch the target agent using direct registry.get
    local agent_entry, err = registry.get(params.agent_id)
    if not agent_entry then
        response.error = "Agent not found: " .. params.agent_id .. " (" .. (err or "unknown error") .. ")"
        return response
    end

    -- Validate it's an agent
    if not agent_entry.meta or agent_entry.meta.type ~= "agent.gen1" then
        response.error = "Entry is not a valid agent.gen1: " .. params.agent_id
        return response
    end

    -- Initialize analysis structure
    local analysis = {
        basic_info = {},
        inheritance = {},
        tools = {},
        tool_schema_validation = {},
        traits = {},
        delegation = {},
        memory = {},
        metadata_quality = {},
        warnings = {},
        recommendations = {}
    }

    -- Helper function to check if array contains value
    local function contains(array, value)
        if not array then return false end
        for _, item in ipairs(array) do
            if item == value then
                return true
            end
        end
        return false
    end

    -- Helper function to add unique items
    local function add_unique_items(target_array, source_array)
        if not source_array then return end
        for _, item in ipairs(source_array) do
            if not contains(target_array, item) then
                table.insert(target_array, item)
            end
        end
    end

    -- Analyze basic information
    analysis.basic_info = {
        id = agent_entry.id,
        name = (agent_entry.meta and agent_entry.meta.name) or "",
        title = (agent_entry.meta and agent_entry.meta.title) or "",
        description = (agent_entry.meta and agent_entry.meta.comment) or "",
        model = (agent_entry.data and agent_entry.data.model) or "",
        max_tokens = (agent_entry.data and agent_entry.data.max_tokens) or 0,
        temperature = (agent_entry.data and agent_entry.data.temperature) or 0,
        thinking_effort = (agent_entry.data and agent_entry.data.thinking_effort) or 0,
        prompt_length = (agent_entry.data and agent_entry.data.prompt and #agent_entry.data.prompt) or 0
    }

    -- Analyze inheritance chain
    local function analyze_inheritance(agent_id, visited_ids, depth)
        visited_ids = visited_ids or {}
        depth = depth or 0
        
        if visited_ids[agent_id] then
            table.insert(analysis.warnings, "Circular inheritance detected involving: " .. agent_id)
            return {}
        end
        
        visited_ids[agent_id] = true
        local inheritance_info = {
            id = agent_id,
            depth = depth,
            exists = false,
            is_valid_agent = false,
            inherited_traits = {},
            inherited_tools = {},
            inherited_memory = {},
            parents = {}
        }
        
        local entry, err = registry.get(agent_id)
        if entry then
            inheritance_info.exists = true
            if entry.meta and entry.meta.type == "agent.gen1" then
                inheritance_info.is_valid_agent = true
                inheritance_info.inherited_traits = entry.data.traits or {}
                inheritance_info.inherited_tools = entry.data.tools or {}
                inheritance_info.inherited_memory = entry.data.memory or {}
                
                -- Process parent inheritance
                if entry.data.inherit then
                    for _, parent_id in ipairs(entry.data.inherit) do
                        local parent_info = analyze_inheritance(parent_id, visited_ids, depth + 1)
                        table.insert(inheritance_info.parents, parent_info)
                    end
                end
            else
                table.insert(analysis.warnings, "Inheritance target is not a valid agent: " .. agent_id)
            end
        else
            table.insert(analysis.warnings, "Inheritance target not found: " .. agent_id)
        end
        
        return inheritance_info
    end

    -- Build inheritance chain
    if agent_entry.data.inherit then
        analysis.inheritance.has_inheritance = true
        analysis.inheritance.direct_parents = agent_entry.data.inherit
        analysis.inheritance.chain = {}
        
        for _, parent_id in ipairs(agent_entry.data.inherit) do
            local parent_info = analyze_inheritance(parent_id, {}, 1)
            table.insert(analysis.inheritance.chain, parent_info)
        end
    else
        analysis.inheritance.has_inheritance = false
        analysis.inheritance.direct_parents = {}
        analysis.inheritance.chain = {}
    end

    -- Analyze tools (including wildcard expansion)
    local function resolve_tool_wildcards(tools_array)
        if not tools_array or #tools_array == 0 then
            return {}
        end
        
        local resolved_tools = {}
        local wildcard_expansions = {}
        
        for _, tool_id in ipairs(tools_array) do
            if type(tool_id) == "string" and tool_id:match(":%*$") then
                local namespace = tool_id:gsub(":%*$", "")
                -- Use registry.find with proper namespace filtering
                local matching_entries, err = registry.find({
                    [".ns"] = namespace,
                    ["meta.type"] = "tool"
                })
                
                local expanded_tools = {}
                if matching_entries and #matching_entries > 0 then
                    for _, entry in ipairs(matching_entries) do
                        table.insert(expanded_tools, entry.id)
                        if not contains(resolved_tools, entry.id) then
                            table.insert(resolved_tools, entry.id)
                        end
                    end
                end
                
                wildcard_expansions[tool_id] = {
                    namespace = namespace,
                    expanded_count = #expanded_tools,
                    expanded_tools = expanded_tools
                }
            else
                if not contains(resolved_tools, tool_id) then
                    table.insert(resolved_tools, tool_id)
                end
            end
        end
        
        return resolved_tools, wildcard_expansions
    end

    -- Collect all tools from agent and inheritance
    local all_tools = {}
    add_unique_items(all_tools, agent_entry.data.tools or {})
    
    -- Add tools from inheritance chain
    local function collect_inherited_tools(inheritance_chain)
        for _, parent_info in ipairs(inheritance_chain) do
            if parent_info.is_valid_agent then
                add_unique_items(all_tools, parent_info.inherited_tools)
                collect_inherited_tools(parent_info.parents)
            end
        end
    end
    collect_inherited_tools(analysis.inheritance.chain)

    local resolved_tools, wildcard_expansions = resolve_tool_wildcards(all_tools)
    
    analysis.tools = {
        direct_tools = agent_entry.data.tools or {},
        all_tools_before_expansion = all_tools,
        resolved_tools = resolved_tools,
        wildcard_expansions = wildcard_expansions or {},
        total_count = #resolved_tools,
        has_wildcards = wildcard_expansions and next(wildcard_expansions) ~= nil
    }

    -- Validate tool existence
    local missing_tools = {}
    for _, tool_id in ipairs(resolved_tools) do
        local tool_entry, err = registry.get(tool_id)
        if not tool_entry then
            table.insert(missing_tools, tool_id)
        elseif not tool_entry.meta or tool_entry.meta.type ~= "tool" then
            table.insert(missing_tools, tool_id .. " (not a valid tool)")
        end
    end
    analysis.tools.missing_tools = missing_tools

    -- Tool Schema Validation (RELAXED VERSION)
    local function validate_tool_schemas(tool_ids)
        local validation_result = {
            valid_schemas = {},
            invalid_schemas = {},
            schema_warnings = {},
            total_tools_with_schemas = 0
        }
        
        if #tool_ids == 0 then
            return validation_result
        end
        
        -- Helper function to validate schema structure recursively
        local function validate_schema_structure(schema, path, errors, warnings)
            path = path or "root"
            
            if type(schema) ~= "table" then
                table.insert(errors, path .. ": Schema must be a table/object")
                return
            end
            
            -- Check for forbidden directives
            local forbidden_directives = {"anyOf", "oneOf", "allOf", "not", "if", "then", "else"}
            for _, directive in ipairs(forbidden_directives) do
                if schema[directive] then
                    table.insert(errors, path .. ": Schema contains forbidden directive '" .. directive .. "'")
                end
            end
            
            -- Check type field
            if schema.type then
                if type(schema.type) == "table" then
                    table.insert(errors, path .. ": Type field cannot be an array (found: [" .. table.concat(schema.type, ", ") .. "])")
                elseif type(schema.type) ~= "string" then
                    table.insert(errors, path .. ": Type field must be a string")
                end
            end
            
            -- Check description/comment requirement
            if not schema.description and not schema.comment then
                table.insert(errors, path .. ": Missing description or comment field")
            end
            
            -- Validate object type requirements (RELAXED VERSION)
            if schema.type == "object" and schema.properties then
                local required_fields = schema.required or {}
                
                -- Recursively validate all property schemas
                for prop_name, prop_schema in pairs(schema.properties) do
                    validate_schema_structure(prop_schema, path .. ".properties." .. prop_name, errors, warnings)
                end
                
                -- Check for required fields not in properties
                for _, required_field in ipairs(required_fields) do
                    if not schema.properties[required_field] then
                        table.insert(warnings, path .. ": Required field '" .. required_field .. "' not found in properties")
                    end
                end
                
                -- Optional: Warn about properties that might benefit from being required
                -- Only warn if there are no required fields at all and many properties exist
                if #required_fields == 0 and next(schema.properties) then
                    local prop_count = 0
                    for _ in pairs(schema.properties) do
                        prop_count = prop_count + 1
                    end
                    if prop_count > 3 then
                        table.insert(warnings, path .. ": Object has " .. prop_count .. " properties but no required fields - consider marking essential parameters as required")
                    end
                end
            end
            
            -- Validate array items
            if schema.type == "array" and schema.items then
                validate_schema_structure(schema.items, path .. ".items", errors, warnings)
            end
        end
        
        -- Process each tool
        for _, tool_id in ipairs(tool_ids) do
            local tool_entry, err = registry.get(tool_id)
            if tool_entry and tool_entry.meta and tool_entry.meta.type == "tool" then
                if tool_entry.meta.input_schema then
                    validation_result.total_tools_with_schemas = validation_result.total_tools_with_schemas + 1
                    
                    local schema = nil
                    local parse_error = nil
                    
                    -- Parse schema if it's a string
                    if type(tool_entry.meta.input_schema) == "string" then
                        if tool_entry.meta.input_schema == "" then
                            parse_error = "Schema is empty string"
                        else
                            schema, parse_error = json.decode(tool_entry.meta.input_schema)
                        end
                    elseif type(tool_entry.meta.input_schema) == "table" then
                        schema = tool_entry.meta.input_schema
                    else
                        parse_error = "Schema must be a string or table"
                    end
                    
                    if parse_error then
                        table.insert(validation_result.invalid_schemas, {
                            tool_id = tool_id,
                            validation_errors = {"Schema parsing error: " .. parse_error}
                        })
                    elseif schema then
                        local errors = {}
                        local warnings = {}
                        
                        -- Check if schema is empty
                        if next(schema) == nil then
                            table.insert(errors, "Schema is empty")
                        else
                            -- Root schema must be type object
                            if not schema.type then
                                table.insert(errors, "Root schema missing type field")
                            elseif schema.type ~= "object" then
                                table.insert(errors, "Root schema must be type 'object' (found: '" .. tostring(schema.type) .. "')")
                            end
                            
                            -- Validate schema structure
                            validate_schema_structure(schema, "root", errors, warnings)
                        end
                        
                        if #errors > 0 then
                            table.insert(validation_result.invalid_schemas, {
                                tool_id = tool_id,
                                validation_errors = errors
                            })
                        else
                            table.insert(validation_result.valid_schemas, tool_id)
                        end
                        
                        -- Add warnings to global warnings array
                        for _, warning in ipairs(warnings) do
                            table.insert(validation_result.schema_warnings, {
                                tool_id = tool_id,
                                warning = warning
                            })
                        end
                    end
                end
            end
        end
        
        return validation_result
    end
    
    -- Perform tool schema validation on resolved tools (excluding missing ones)
    local valid_tools = {}
    for _, tool_id in ipairs(resolved_tools) do
        local is_missing = false
        for _, missing_tool in ipairs(missing_tools) do
            if missing_tool == tool_id or missing_tool:find(tool_id, 1, true) then
                is_missing = true
                break
            end
        end
        if not is_missing then
            table.insert(valid_tools, tool_id)
        end
    end
    
    analysis.tool_schema_validation = validate_tool_schemas(valid_tools)

    -- Analyze traits
    local all_traits = {}
    add_unique_items(all_traits, agent_entry.data.traits or {})
    
    -- Add traits from inheritance
    local function collect_inherited_traits(inheritance_chain)
        for _, parent_info in ipairs(inheritance_chain) do
            if parent_info.is_valid_agent then
                add_unique_items(all_traits, parent_info.inherited_traits)
                collect_inherited_traits(parent_info.parents)
            end
        end
    end
    collect_inherited_traits(analysis.inheritance.chain)

    analysis.traits = {
        direct_traits = agent_entry.data.traits or {},
        all_traits = all_traits,
        total_count = #all_traits
    }

    -- Validate trait existence (check both by ID and by name)
    local missing_traits = {}
    for _, trait_id in ipairs(all_traits) do
        local trait_found = false
        
        -- First try to get by ID
        local trait_entry, err = registry.get(trait_id)
        if trait_entry and trait_entry.meta and trait_entry.meta.type == "agent.trait" then
            trait_found = true
        else
            -- If not found by ID, try to find by name
            local trait_entries, err = registry.find({
                [".kind"] = "registry.entry",
                ["meta.type"] = "agent.trait",
                ["meta.name"] = trait_id
            })
            
            if trait_entries and #trait_entries > 0 then
                trait_found = true
            end
        end
        
        if not trait_found then
            table.insert(missing_traits, trait_id)
        end
    end
    analysis.traits.missing_traits = missing_traits

    -- Analyze delegation
    analysis.delegation = {
        has_delegation = false,
        delegates = {},
        missing_targets = {},
        invalid_targets = {}
    }

    if agent_entry.data.delegate then
        analysis.delegation.has_delegation = true
        
        for target_id, config in pairs(agent_entry.data.delegate) do
            local delegate_info = {
                target_id = target_id,
                name = config.name,
                rule = config.rule,
                exists = false,
                is_valid_agent = false
            }
            
            local target_entry, err = registry.get(target_id)
            if target_entry then
                delegate_info.exists = true
                if target_entry.meta and target_entry.meta.type == "agent.gen1" then
                    delegate_info.is_valid_agent = true
                else
                    table.insert(analysis.delegation.invalid_targets, target_id)
                end
            else
                table.insert(analysis.delegation.missing_targets, target_id)
            end
            
            table.insert(analysis.delegation.delegates, delegate_info)
        end
    end

    -- Analyze memory
    local all_memory = {}
    add_unique_items(all_memory, agent_entry.data.memory or {})
    
    -- Add memory from inheritance
    local function collect_inherited_memory(inheritance_chain)
        for _, parent_info in ipairs(inheritance_chain) do
            if parent_info.is_valid_agent then
                add_unique_items(all_memory, parent_info.inherited_memory)
                collect_inherited_memory(parent_info.parents)
            end
        end
    end
    collect_inherited_memory(analysis.inheritance.chain)

    analysis.memory = {
        direct_memory = agent_entry.data.memory or {},
        all_memory = all_memory,
        total_count = #all_memory
    }

    -- Analyze metadata quality
    analysis.metadata_quality = {
        has_name = (agent_entry.meta.name and #agent_entry.meta.name > 0) or false,
        has_title = (agent_entry.meta.title and #agent_entry.meta.title > 0) or false,
        has_description = (agent_entry.meta.comment and #agent_entry.meta.comment > 0) or false,
        has_prompt = (agent_entry.data.prompt and #agent_entry.data.prompt > 0) or false,
        has_model = (agent_entry.data.model and #agent_entry.data.model > 0) or false,
        has_class = (agent_entry.meta.class ~= nil) or false,
        has_tags = (agent_entry.meta.tags and #agent_entry.meta.tags > 0) or false,
        has_icon = (agent_entry.meta.icon and #agent_entry.meta.icon > 0) or false
    }

    -- Generate warnings
    if #missing_tools > 0 then
        table.insert(analysis.warnings, "Missing or invalid tools: " .. table.concat(missing_tools, ", "))
    end
    
    if #missing_traits > 0 then
        table.insert(analysis.warnings, "Missing or invalid traits: " .. table.concat(missing_traits, ", "))
    end
    
    if #analysis.delegation.missing_targets > 0 then
        table.insert(analysis.warnings, "Missing delegation targets: " .. table.concat(analysis.delegation.missing_targets, ", "))
    end
    
    if #analysis.delegation.invalid_targets > 0 then
        table.insert(analysis.warnings, "Invalid delegation targets (not agents): " .. table.concat(analysis.delegation.invalid_targets, ", "))
    end
    
    if not analysis.metadata_quality.has_prompt then
        table.insert(analysis.warnings, "Agent has no prompt defined")
    end
    
    if not analysis.metadata_quality.has_model then
        table.insert(analysis.warnings, "Agent has no model specified")
    end

    -- Generate recommendations
    if not analysis.metadata_quality.has_description then
        table.insert(analysis.recommendations, "Add a description (meta.comment) to explain the agent's purpose")
    end
    
    if not analysis.metadata_quality.has_title then
        table.insert(analysis.recommendations, "Add a title (meta.title) for better display")
    end
    
    if not analysis.metadata_quality.has_class then
        table.insert(analysis.recommendations, "Add a class (meta.class) for better organization")
    end
    
    if analysis.tools.total_count == 0 then
        table.insert(analysis.recommendations, "Consider adding tools to extend agent capabilities")
    end
    
    if analysis.traits.total_count == 0 then
        table.insert(analysis.recommendations, "Consider adding traits like 'conversational' or 'thinking' for better behavior")
    end
    
    if analysis.memory.total_count == 0 then
        table.insert(analysis.recommendations, "Consider adding memory items for contextual knowledge")
    end
    
    if analysis.basic_info.prompt_length < 50 then
        table.insert(analysis.recommendations, "Consider expanding the prompt for clearer agent behavior")
    end

    response.success = true
    response.analysis = analysis
    return response
end

return {
    handler = handler
}