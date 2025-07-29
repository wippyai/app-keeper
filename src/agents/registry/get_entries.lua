local yaml = require("yaml")
local registry = require("registry")

local function handler(params)
    local response_data = {
        success = false, -- Default to failure
        result = {},     -- Default to empty list for entries
        error = nil,
        missing_ids = {},
        version = nil
    }

    -- --- Input Validation ---
    if not params.ids or type(params.ids) ~= "table" then
        response_data.error = "Missing or invalid required parameter: ids (must be a table of entry ID strings)"
        -- Encode and return the error response as YAML
        local yaml_output, _ = yaml.encode(response_data, { indent = 2 })
        return yaml_output or "success: false\nerror: Failed to encode validation error to YAML" -- Fallback
    end

    -- --- Get Snapshot ---
    local snapshot, err_snap = registry.snapshot()
    if not snapshot then
        response_data.error = "Failed to get registry snapshot: " .. (err_snap or "unknown error")
        -- Encode and return the error response as YAML
        local yaml_output, _ = yaml.encode(response_data, { indent = 2 })
        return yaml_output or "success: false\nerror: Failed to encode snapshot error to YAML" -- Fallback
    end

    -- --- Get Version Info (do this early if snapshot succeeded) ---
    local version = snapshot:version()
    if version then
        response_data.version = {
            id = version:id(),
            previous = version:previous() and version:previous():id() or nil,
            string = version:string()
        }
    end

    -- --- Iterate and Fetch Entries ---
    local found_entries = {}
    local current_missing_ids = {}
    for _, id in ipairs(params.ids) do
        if type(id) == "string" then
            local entry, err_get = snapshot:get(id)
            if entry then
                table.insert(found_entries, {
                    id = entry.id,
                    kind = entry.kind,
                    meta = entry.meta or {},
                    data = entry.data or {}
                })
            else
                table.insert(current_missing_ids, id)
            end
        else
            table.insert(current_missing_ids, "(invalid ID type: " .. type(id) .. ")")
        end
    end
    response_data.missing_ids = current_missing_ids -- Update missing IDs in the response

    -- --- Always return success unless there's a system error ---
    -- The operation succeeded if we were able to process the request,
    -- regardless of whether all entries were found
    response_data.success = true
    response_data.result = found_entries
    response_data.error = nil

    -- If there are missing IDs, add a warning message but keep success=true
    if #current_missing_ids > 0 then
        local missing_count = #current_missing_ids
        local total_count = #params.ids
        local found_count = #found_entries

        -- Add a warning field instead of error
        response_data.warning = string.format(
            "Found %d of %d requested entries. %d entries were not found.",
            found_count, total_count, missing_count
        )
    end

    -- --- Encode Final Response to YAML ---
    local final_yaml_output, err_yaml = yaml.encode(response_data, { indent = 2 })

    if not final_yaml_output then
        -- Handle the rare case where final encoding fails
        return "success: false\nerror: Failed to encode final response to YAML\ndetails: " .. (err_yaml or "unknown")
    end

    return final_yaml_output
end

return {
    handler = handler
}