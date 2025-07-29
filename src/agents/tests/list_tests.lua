local registry = require("registry")

local function handler(params)
    -- Set up filter options based on parameters
    local options = {
        ["meta.type"] = "test"
    }

    -- Apply group filter if provided
    if params.group then
        options["meta.group"] = params.group
    end

    -- Apply namespace filter if provided
    if params.namespace then
        options[".ns"] = params.namespace
    end

    -- Apply name filter if provided
    if params.name then
        options["meta.name"] = params.name
    end

    -- Apply tag filters if provided
    if params.tags then
        options["meta.tags"] = params.tags
    end

    -- Find tests matching the criteria
    local tests, err = registry.find(options)
    if err then
        return {
            success = false,
            error = "Failed to find tests: " .. (err or "unknown error")
        }
    end

    if not tests or #tests == 0 then
        return {
            success = true,
            message = "No tests found matching the specified criteria",
            tests = {},
            count = 0
        }
    end

    -- Process and organize test information
    local processed_tests = {}
    local groups = {}
    local namespaces = {}
    local tags_counter = {}

    for _, test in ipairs(tests) do
        local parsed_id = registry.parse_id(test.id)
        local test_info = {
            id = test.id,
            name = test.meta.name or parsed_id.name,
            namespace = parsed_id.ns,
            group = test.meta.group or "Ungrouped",
            comment = test.meta.comment or "",
            tags = test.meta.tags or {}
        }

        -- Track groups
        groups[test_info.group] = (groups[test_info.group] or 0) + 1

        -- Track namespaces
        namespaces[test_info.namespace] = (namespaces[test_info.namespace] or 0) + 1

        -- Track tags
        if test_info.tags then
            for _, tag in ipairs(test_info.tags) do
                tags_counter[tag] = (tags_counter[tag] or 0) + 1
            end
        end

        table.insert(processed_tests, test_info)
    end

    -- Convert groups, namespaces, and tags to arrays for easier consumption
    local groups_array = {}
    for group, count in pairs(groups) do
        table.insert(groups_array, { name = group, count = count })
    end

    local namespaces_array = {}
    for namespace, count in pairs(namespaces) do
        table.insert(namespaces_array, { name = namespace, count = count })
    end

    local tags_array = {}
    for tag, count in pairs(tags_counter) do
        table.insert(tags_array, { name = tag, count = count })
    end

    -- Sort arrays by name
    table.sort(groups_array, function(a, b) return a.name < b.name end)
    table.sort(namespaces_array, function(a, b) return a.name < b.name end)
    table.sort(tags_array, function(a, b) return a.name < b.name end)

    -- Sort tests by group then name
    table.sort(processed_tests, function(a, b)
        if a.group == b.group then
            return a.name < b.name
        end
        return a.group < b.group
    end)

    return {
        success = true,
        tests = processed_tests,
        count = #processed_tests,
        groups = groups_array,
        namespaces = namespaces_array,
        tags = tags_array
    }
end

return {
    handler = handler
}