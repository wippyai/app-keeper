local commit = require("commit")

local function handler(params)
    -- Get the number of commits to retrieve (default: 10)
    local count = params.count or 10

    -- Get commit history
    local history, err = commit.history(count)

    if err then
        return {
            success = false,
            error = "Failed to retrieve commit history: " .. err
        }
    end

    return {
        success = true,
        commits = history
    }
end

return {
    handler = handler
}