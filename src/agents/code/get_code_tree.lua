local registry = require("registry")
local yaml = require("yaml")

-- Helper function to get code entries recursively through the entire namespace hierarchy
-- Use namespaces_only=true for faster navigation when only the namespace structure is needed
local function get_entries_recursive(namespace, include_source, namespaces_only, all_entries, code_entries, processed_namespaces)
    -- Create namespace prefix for searching
    local prefix = namespace
    if prefix ~= "" then
        prefix = prefix .. ":"
    end

    -- Filter for code entries only
    local code_kinds = {
        ["function.lua"] = true,
        ["library.lua"] = true,
        ["process.lua"] = true
    }

    -- Add entries to the result if we're not in namespaces_only mode
    if not namespaces_only then
        -- Find all entries in this namespace
        for _, entry in ipairs(all_entries) do
            -- Check if this entry belongs to the current namespace
            local parsed_id = registry.parse_id(entry.id)

            if parsed_id.ns == namespace and code_kinds[entry.kind] then
                local result = {
                    id = entry.id,
                    name = parsed_id.name,
                    namespace = parsed_id.ns,
                    kind = entry.kind,
                    meta = {},
                }

                -- Add basic metadata
                if entry.meta then
                    result.meta.type = entry.meta.type
                    result.meta.title = entry.meta.title
                    result.meta.comment = entry.meta.comment or entry.meta.description
                end

                -- Add modules if present
                if entry.modules and #entry.modules > 0 then
                    result.modules = entry.modules
                end

                -- Add imports if present
                if entry.imports and next(entry.imports) then
                    result.imports = entry.imports
                end

                -- Add method if present
                if entry.method then
                    result.method = entry.method
                end

                -- Add source if requested
                if include_source then
                    if entry.source then
                        result.source = entry.source
                    elseif entry.data and entry.data.source then
                        result.source = entry.data.source
                    end
                end

                table.insert(code_entries, result)
            end
        end
    end

    -- Find child namespaces
    local child_namespaces = {}
    local ns_prefix = namespace
    if ns_prefix ~= "" then
        ns_prefix = ns_prefix .. "."
    end

    -- Collect all unique namespaces from entries
    local all_namespaces = {}
    for _, entry in ipairs(all_entries) do
        local parsed_id = registry.parse_id(entry.id)
        all_namespaces[parsed_id.ns] = true
    end

    -- Find all direct child namespaces
    for ns, _ in pairs(all_namespaces) do
        -- Check if this namespace is a direct child of our current namespace
        if ns:find(ns_prefix, 1, true) == 1 and ns ~= namespace then
            -- Extract the next namespace level
            local remaining = ns:sub(#ns_prefix + 1)
            local next_level = remaining:match("^[^%.]+")

            if next_level then
                local child_ns = ns_prefix .. next_level
                if not child_namespaces[child_ns] and not processed_namespaces[child_ns] then
                    child_namespaces[child_ns] = true
                    processed_namespaces[child_ns] = true
                end
            end
        end
    end

    -- Process each child namespace recursively
    for child_ns, _ in pairs(child_namespaces) do
        get_entries_recursive(child_ns, include_source, namespaces_only, all_entries, code_entries, processed_namespaces)
    end
end

-- Helper function to organize entries by namespace hierarchy
local function organize_by_namespace(entries)
    local tree = {}

    -- First pass: collect all unique namespaces
    local namespaces = {}
    for _, entry in ipairs(entries) do
        namespaces[entry.namespace] = true
    end

    -- Build the tree structure
    for namespace, _ in pairs(namespaces) do
        local current = tree
        local ns_parts = {}

        -- Split namespace by dots
        for part in namespace:gmatch("[^%.]+") do
            table.insert(ns_parts, part)
        end

        -- Build nested structure
        for i, part in ipairs(ns_parts) do
            if not current[part] then
                current[part] = {
                    _type = "namespace",
                    _name = part,
                    _full_name = table.concat(ns_parts, ".", 1, i),
                    _entries = {}
                }
            end
            current = current[part]
        end
    end

    -- Second pass: add entries to their namespaces
    for _, entry in ipairs(entries) do
        local ns_parts = {}
        local current = tree

        -- Split namespace by dots
        for part in entry.namespace:gmatch("[^%.]+") do
            table.insert(ns_parts, part)
        end

        -- Navigate to the right namespace
        for _, part in ipairs(ns_parts) do
            current = current[part]
        end

        -- Add entry to namespace
        table.insert(current._entries, entry)
    end

    return tree
end

-- Create empty namespace tree (for namespaces_only mode)
local function create_namespace_tree(namespaces)
    local tree = {}

    for namespace, _ in pairs(namespaces) do
        local current = tree
        local ns_parts = {}

        -- Split namespace by dots
        for part in namespace:gmatch("[^%.]+") do
            table.insert(ns_parts, part)
        end

        -- Build nested structure
        for i, part in ipairs(ns_parts) do
            if not current[part] then
                current[part] = {
                    _type = "namespace",
                    _name = part,
                    _full_name = table.concat(ns_parts, ".", 1, i),
                    _entries = {}
                }
            end
            current = current[part]
        end
    end

    return tree
end

local function handler(params)
    -- Set namespace (empty string for root, which will search ALL namespaces)
    local namespace = params.namespace or ""

    -- Include source code option
    local include_source = params.include_source or false

    -- Namespaces only option (faster navigation)
    local namespaces_only = params.namespaces_only or false

    -- Get all entries directly from registry
    local all_entries, err = registry.find({})
    if not all_entries then
        return {
            success = false,
            error = "Failed to get registry entries: " .. (err or "unknown error")
        }
    end

    -- Collect code entries recursively (through entire hierarchy)
    local code_entries = {}
    local processed_namespaces = {}

    if namespaces_only then
        -- Just collect all unique namespaces if we only need namespace structure
        for _, entry in ipairs(all_entries) do
            local parsed_id = registry.parse_id(entry.id)
            processed_namespaces[parsed_id.ns] = true
        end
    else
        -- Collect all entries
        get_entries_recursive(namespace, include_source, namespaces_only, all_entries, code_entries, processed_namespaces)
    end

    -- Create result object
    local result = {
        namespace = namespace == "" and "root" or namespace,
        count = namespaces_only and 0 or #code_entries,
        namespaces_count = 0
    }

    -- Add namespaces count
    for _ in pairs(processed_namespaces) do
        result.namespaces_count = result.namespaces_count + 1
    end

    if namespaces_only then
        -- Just create a namespace tree without entries
        result.message = "Showing namespace structure only (faster navigation)"
        result.tree = create_namespace_tree(processed_namespaces)
    else
        if #code_entries == 0 then
            result.message = "No code entries found in namespace: " .. (namespace == "" and "root" or namespace)
            result.tree = {}
        else
            -- Organize entries by namespace
            result.tree = organize_by_namespace(code_entries)

            -- Sort entries in each namespace by kind, then name
            local function sort_entries(entries)
                table.sort(entries, function(a, b)
                    if a.kind == b.kind then
                        return a.name < b.name
                    else
                        -- Order: functions first, then libraries, then processes
                        local kind_order = {
                            ["function.lua"] = 1,
                            ["library.lua"] = 2,
                            ["process.lua"] = 3
                        }
                        return kind_order[a.kind] < kind_order[b.kind]
                    end
                end)
            end

            -- Sort entries in the tree recursively
            local function sort_tree(node)
                if node._type == "namespace" and node._entries then
                    sort_entries(node._entries)
                end

                for k, v in pairs(node) do
                    if type(v) == "table" and k:sub(1, 1) ~= "_" then
                        sort_tree(v)
                    end
                end
            end

            sort_tree(result.tree)
        end
    end

    -- Convert to YAML
    local yamlOptions = {
        indent = 2,
        field_order = {"namespace", "count", "namespaces_count", "message", "tree"},
        sort_unordered = true
    }

    local yamlOutput, yamlErr = yaml.encode(result, yamlOptions)
    if yamlErr then
        return {
            success = false,
            error = "Failed to encode result to YAML: " .. yamlErr
        }
    end

    -- Return the YAML result
    return yamlOutput
end

return {
    handler = handler
}