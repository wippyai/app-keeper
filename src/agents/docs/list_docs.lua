local registry = require("registry")

local function handler(params)
    -- Find all module specs directly
    local criteria = {
        ["meta.type"] = "module.spec"
    }

    local entries, err = registry.find(criteria)
    if err then
        return {
            success = false,
            error = "Failed to find entries: " .. err
        }
    end

    -- Create simple list of modules
    local docs = {}
    for _, entry in ipairs(entries) do
        table.insert(docs, {
            id = entry.id,
            description = entry.meta.comment or ""
        })
    end

    -- Sort by ID
    table.sort(docs, function(a, b) return a.id < b.id end)

    return {
        success = true,
        docs = docs,
        count = #docs
    }
end

return {
    handler = handler
}