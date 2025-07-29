local http = require("http")
local json = require("json")
local registry = require("registry")
local editor_registry = require("entry_editor_registry")

local function handler()
    -- Get response and request objects
    local res = http.response()
    local req = http.request()
    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Get entry ID from query
    local entry_id = req:query("id")
    if not entry_id or entry_id == "" then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Missing required query parameter: id"
        })
        return
    end

    -- Get the entry directly from registry
    local entry, err = registry.get(entry_id)
    if not entry then
        res:set_status(http.STATUS.NOT_FOUND)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Entry not found: " .. entry_id
        })
        return
    end

    -- Find editor configurations for this entry
    local editor_entries, err = editor_registry.find_editors_for_entry(entry)
    if not editor_entries then
        -- No editors found, return empty lists
        res:set_status(http.STATUS.OK)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = true,
            editors = {},
            actions = {}
        })
        return
    end

    -- Process editor entries into a flat list of editors and actions
    local editors = {}
    local actions = {}

    for _, editor_entry in ipairs(editor_entries) do
        -- Add all editors from this configuration
        if editor_entry.editors then
            for _, editor in ipairs(editor_entry.editors) do
                table.insert(editors, editor)
            end
        end

        -- Add all actions from this configuration
        if editor_entry.actions then
            for _, action in ipairs(editor_entry.actions) do
                table.insert(actions, action)
            end
        end
    end

    -- Sort editors by order
    table.sort(editors, function(a, b)
        local a_order = a.order or 1000
        local b_order = b.order or 1000
        return a_order < b_order
    end)

    -- Return the editors and actions
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        editors = editors,
        actions = actions
    })
end

return {
    handler = handler
}