local status = require("status")

local function handler(params)
    -- Get full repository status
    local repo_status, err = status.get_full_status()

    if err then
        return {
            success = false,
            error = "Failed to get repository status: " .. err
        }
    end

    return {
        success = true,
        status = repo_status
    }
end

return {
    handler = handler
}