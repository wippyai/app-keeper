local commit = require("commit")

local function handler(params)
    -- Validate required parameters
    if not params.mode then
        return {
            success = false,
            error = "Missing required parameter: mode"
        }
    end

    local result = nil
    local err = nil

    -- Perform the requested staging action
    if params.mode == "file" then
        -- Stage a specific file
        if not params.file_path then
            return {
                success = false,
                error = "Missing required parameter for file mode: file_path"
            }
        end

        result, err = commit.stage_file(params.file_path)
    elseif params.mode == "all" then
        -- Stage all changes
        result, err = commit.stage_all()
    elseif params.mode == "unstage" then
        -- Unstage a file
        if not params.file_path then
            return {
                success = false,
                error = "Missing required parameter for unstage mode: file_path"
            }
        end

        result, err = commit.unstage_file(params.file_path)
    else
        return {
            success = false,
            error = "Invalid mode: " .. params.mode
        }
    end

    if err then
        return {
            success = false,
            error = "Failed to stage changes: " .. err
        }
    end

    return {
        success = true,
        message = "Successfully staged changes using mode: " .. params.mode
    }
end

return {
    handler = handler
}