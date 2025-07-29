local commit = require("commit")

local function handler(params)
    -- Validate required parameters
    if not params.message and not params.amend then
        return {
            success = false,
            error = "Missing required parameter: message (required unless amending)"
        }
    end

    local result = nil
    local err = nil

    -- Perform the commit action
    if params.amend then
        -- Amend the previous commit
        result, err = commit.amend(params.message)

        if err then
            return {
                success = false,
                error = "Failed to amend commit: " .. err
            }
        end

        return {
            success = true,
            message = "Successfully amended the previous commit"
        }
    else
        -- Create a new commit
        result, err = commit.create(params.message, params.author)

        if err then
            return {
                success = false,
                error = "Failed to create commit: " .. err
            }
        end

        return {
            success = true,
            commit = result
        }
    end
end

return {
    handler = handler
}