local branch = require("branch")

local function handler(params)
    -- Validate required parameters
    if not params.action then
        return {
            success = false,
            error = "Missing required parameter: action"
        }
    end

    if not params.branch_name then
        return {
            success = false,
            error = "Missing required parameter: branch_name"
        }
    end

    local result = nil
    local err = nil

    -- Perform the requested action
    if params.action == "create" then
        -- Create a new branch
        result, err = branch.create(params.branch_name, params.start_point)
    elseif params.action == "switch" then
        -- Switch to an existing branch
        result, err = branch.switch(params.branch_name)
    elseif params.action == "delete" then
        -- Delete a branch
        result, err = branch.delete(params.branch_name, params.force)
    else
        return {
            success = false,
            error = "Invalid action: " .. params.action
        }
    end

    if err then
        return {
            success = false,
            error = "Failed to " .. params.action .. " branch: " .. err
        }
    end

    return {
        success = true,
        message = "Successfully performed " .. params.action .. " on branch " .. params.branch_name
    }
end

return {
    handler = handler
}