local registry = require('registry')
local code_utils = require('code_utils')

local function handler(params)
    -- Validate required input
    if not params.id then
        return 'Missing required parameter: id (string or array of strings)'
    end

    -- Handle both single ID and array of IDs
    local ids = params.id
    if type(ids) == 'string' then
        ids = {ids}
    elseif type(ids) ~= 'table' then
        return 'Invalid parameter: id must be a string or array of strings'
    end

    -- Process each ID and collect results
    local results = {}
    for _, id in ipairs(ids) do
        local entry, err = code_utils.get_entry(id)
        if entry then
            table.insert(results, code_utils.format_entry_as_source(entry))
        else
            -- If any entry fails, add an error message in a format that's easy to identify
            table.insert(results, '<error id="' .. id .. '">' .. err .. '</error>')
        end
    end

    -- Return the combined results
    return table.concat(results, '\n\n')
end

return {
    handler = handler
}