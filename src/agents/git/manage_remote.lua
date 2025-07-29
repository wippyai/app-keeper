local remote = require("remote")

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

    -- Handle remote management actions
    if params.action == "add" then
        -- Add a new remote
        if not params.name or not params.url then
            return {
                success = false,
                error = "Missing required parameters for add action: name and url"
            }
        end

        result, err = remote.add(params.name, params.url)

        if err then
            return {
                success = false,
                error = "Failed to add remote: " .. err
            }
        end

        return {
            success = true,
            message = "Successfully added remote " .. params.name .. " with URL " .. params.url
        }
    elseif params.action == "list" then
        -- List remotes
        result, err = remote.list()

        if err then
            return {
                success = false,
                error = "Failed to list remotes: " .. err
            }
        end

        return {
            success = true,
            remotes = result
        }
    elseif params.action == "remove" then
        -- Remove a remote
        if not params.name then
            return {
                success = false,
                error = "Missing required parameter for remove action: name"
            }
        end

        result, err = remote.remove(params.name)

        if err then
            return {
                success = false,
                error = "Failed to remove remote: " .. err
            }
        end

        return {
            success = true,
            message = "Successfully removed remote " .. params.name
        }
    else
        return {
            success = false,
            error = "Invalid action: " .. params.action
        }
    end
end

return {
    handler = handler
}