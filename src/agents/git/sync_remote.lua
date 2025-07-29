local remote = require("remote")
local branch = require("branch")

local function handler(params)
    -- Validate required parameters
    if not params.action then
        return {
            success = false,
            error = "Missing required parameter: action"
        }
    end

    local result = nil
    local err = nil

    -- Handle remote sync actions
    if params.action == "push" then
        -- Push to remote
        result, err = remote.push(params.remote_name, params.branch_name, params.force)
    elseif params.action == "pull" then
        -- Pull from remote
        result, err = remote.pull(params.remote_name, params.branch_name)
    elseif params.action == "fetch" then
        -- Fetch updates from remote
        result, err = remote.fetch(params.remote_name, params.all)
    else
        return {
            success = false,
            error = "Invalid action: " .. params.action
        }
    end

    if err then
        return {
            success = false,
            error = "Failed to " .. params.action .. " changes: " .. err
        }
    end

    return {
        success = true,
        result = result
    }
end

return {
    handler = handler
}