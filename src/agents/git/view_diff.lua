local git_repo = require("git_repo")
local status = require("status")

local function handler(params)
    -- Default to file mode if not specified
    local mode = params.mode or "file"
    local staged = params.staged or false

    -- Handle specific file mode
    if mode == "file" then
        -- Validate required parameter for file mode
        if not params.file_path then
            return {
                success = false,
                error = "Missing required parameter for file mode: file_path"
            }
        end

        -- Get diff for the specific file
        local diff, err = git_repo.get_file_diff(params.file_path, staged)

        if err then
            return {
                success = false,
                error = "Failed to get diff: " .. err
            }
        end

        -- Check if there are no changes
        if not diff or diff == "" then
            return {
                success = true,
                message = "No changes detected for file: " .. params.file_path,
                diff = ""
            }
        end

        return {
            success = true,
            file_path = params.file_path,
            staged = staged,
            diff = diff
        }

    -- Handle all files mode
    elseif mode == "all" then
        -- Get repository status to find modified files
        local repo_status, err = status.get_full_status()

        if err then
            return {
                success = false,
                error = "Failed to get repository status: " .. err
            }
        end

        -- Determine which files list to use
        local files_list = staged and repo_status.staged or repo_status.unstaged

        -- Check if there are any files to show diff for
        if not files_list or #files_list == 0 then
            return {
                success = true,
                message = "No " .. (staged and "staged" or "unstaged") .. " changes found",
                diffs = {}
            }
        end

        -- Collect diffs for all files
        local diffs = {}

        for _, file_info in ipairs(files_list) do
            local file_path = file_info.file
            local file_diff, diff_err = git_repo.get_file_diff(file_path, staged)

            if not diff_err and file_diff and file_diff ~= "" then
                table.insert(diffs, {
                    file_path = file_path,
                    status = file_info.status,
                    diff = file_diff
                })
            end
        end

        return {
            success = true,
            staged = staged,
            count = #diffs,
            diffs = diffs
        }

    else
        return {
            success = false,
            error = "Invalid mode: " .. mode
        }
    end
end

return {
    handler = handler
}