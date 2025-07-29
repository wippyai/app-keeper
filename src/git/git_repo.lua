local exec = require("exec")
local json = require("json")
local time = require("time")
local env = require("env")

-- Git repository operations
local git_repo = {}

-- Constants
git_repo.DEFAULT_REMOTE = "origin"
git_repo.DEFAULT_BRANCH = "main"

-- Git command constants
local GIT_CMD = {
    STATUS = "status",
    BRANCH = "branch",
    LOG = "log",
    REV_PARSE = "rev-parse",
    REV_LIST = "rev-list"
}

-- Git porcelain status constants
local STATUS = {
    UNTRACKED = "?",
    UNMODIFIED = ".",
    MODIFIED = "M",
    ADDED = "A",
    DELETED = "D",
    RENAMED = "R",
    COPIED = "C",
    UPDATED = "U"
}

-- Headers in porcelain v2 output
local PORCELAIN_HEADERS = {
    BRANCH_HEAD = "# branch.head ",
    BRANCH_UPSTREAM = "# branch.upstream ",
    BRANCH_AB = "# branch.ab "
}

-- File entry types in porcelain v2 output
local ENTRY_TYPES = {
    ORDINARY = "1",
    RENAMED = "2",
    UNMERGED = "u"
}

-- Git porcelain format version
local PORCELAIN_VERSION = "v2"

-- Executor name constant
local EXECUTOR_NAME = "app:executor"

-- Helper function to get the app source directory from environment variables
local function get_app_src_dir()
    local app_src, err = env.get("APP_SRC")
    if err or not app_src then
        return nil, "Failed to get APP_SRC environment variable: " .. (err or "not set")
    end
    return app_src
end

-- Execute a Git command and return the result
-- @param cmd_args Table containing Git command arguments
-- @param options Optional table with execution options
-- @return Table containing command output and status
function git_repo.exec_git_command(cmd_args, options)
    if not cmd_args or type(cmd_args) ~= "table" then
        return nil, "Invalid Git command arguments"
    end

    local app_src, err = get_app_src_dir()
    if err then
        return nil, err
    end

    -- Prepare command
    local cmd = "git "
    for _, arg in ipairs(cmd_args) do
        -- Escape quotes and spaces in arguments
        local escaped_arg = arg:gsub('"', '\\"')
        cmd = cmd .. '"' .. escaped_arg .. '" '
    end

    -- Prepare options
    options = options or {}
    options.work_dir = options.work_dir or app_src

    -- Get executor
    local executor = exec.get(EXECUTOR_NAME)
    if not executor then
        return nil, "Failed to get executor"
    end

    -- Execute command
    local process = executor:exec(cmd, options)
    if not process then
        executor:release()
        return nil, "Failed to create process for Git command"
    end

    process:start()

    -- Capture stdout
    local stdout = ""
    coroutine.spawn(function()
        local stream = process:stdout_stream()
        while true do
            local chunk = stream:read()
            if not chunk then break end
            stdout = stdout .. chunk
        end
        stream:close()
    end)

    -- Capture stderr
    local stderr = ""
    coroutine.spawn(function()
        local stream = process:stderr_stream()
        while true do
            local chunk = stream:read()
            if not chunk then break end
            stderr = stderr .. chunk
        end
        stream:close()
    end)

    -- Wait for process to complete
    local exit_code = process:wait()

    -- Release resources
    executor:release()

    -- Return results
    return {
        stdout = stdout,
        stderr = stderr,
        exit_code = exit_code,
        success = exit_code == 0
    }
end

-- Map porcelain status code to human-readable status
-- @param status_code Single character status code from Git
-- @return String with human-readable status
local function map_status_code(status_code)
    if status_code == STATUS.ADDED then return "new"
    elseif status_code == STATUS.DELETED then return "deleted"
    elseif status_code == STATUS.MODIFIED then return "modified"
    elseif status_code == STATUS.RENAMED then return "renamed"
    elseif status_code == STATUS.COPIED then return "copied"
    elseif status_code == STATUS.UNTRACKED then return "untracked"
    elseif status_code == STATUS.UPDATED then return "updated"
    else return "modified" -- Default fallback
    end
end

-- Parse Git status using porcelain format for reliability
-- @return Table containing parsed status information
function git_repo.parse_status()
    -- Get status using the porcelain format for machine parsing
    local result, err = git_repo.exec_git_command({
        GIT_CMD.STATUS,
        "--porcelain=" .. PORCELAIN_VERSION,
        "--branch"
    })

    if err or not result.success then
        return nil, "Failed to get Git status: " .. (err or result.stderr or "unknown error")
    end

    local status = {
        branch = nil,
        is_clean = true,
        staged = {},
        unstaged = {},
        untracked = {}
    }

    -- Process porcelain v2 output line by line
    for line in result.stdout:gmatch("[^\r\n]+") do
        local prefix = line:sub(1, 1)

        -- Process branch information
        if prefix == "#" then
            if line:find(PORCELAIN_HEADERS.BRANCH_HEAD, 1, true) then
                local branch_info = line:match(PORCELAIN_HEADERS.BRANCH_HEAD .. "(.+)$")
                if branch_info then
                    status.branch = branch_info
                end
            end

        -- Process regular file entries (tracked files)
        elseif prefix == ENTRY_TYPES.ORDINARY or prefix == ENTRY_TYPES.RENAMED then
            local parts = {}
            for part in line:gmatch("%S+") do
                table.insert(parts, part)
            end

            if #parts >= 3 then
                local xy = parts[2]
                local x, y = xy:sub(1, 1), xy:sub(2, 2)
                local file_path = parts[#parts] -- Last part is the path

                -- Staged changes (x)
                if x ~= STATUS.UNMODIFIED and x ~= STATUS.UNTRACKED then
                    status.is_clean = false
                    local status_type = map_status_code(x)

                    table.insert(status.staged, {
                        file = file_path,
                        status = status_type
                    })
                end

                -- Unstaged changes (y)
                if y ~= STATUS.UNMODIFIED and y ~= STATUS.UNTRACKED then
                    status.is_clean = false
                    local status_type = map_status_code(y)

                    table.insert(status.unstaged, {
                        file = file_path,
                        status = status_type
                    })
                end
            end

        -- Process merge conflicts
        elseif prefix == ENTRY_TYPES.UNMERGED then
            local parts = {}
            for part in line:gmatch("%S+") do
                table.insert(parts, part)
            end

            if #parts >= 7 then
                local file_path = parts[7]
                status.is_clean = false

                table.insert(status.unstaged, {
                    file = file_path,
                    status = "conflict"
                })
            end

        -- Process untracked files
        elseif prefix == "?" then
            -- In porcelain v2, untracked files are marked with "?" prefix
            local file_path = line:match("^%? (.+)$")
            if file_path then
                status.is_clean = false

                table.insert(status.untracked, {
                    file = file_path,
                    status = "untracked"
                })
            end
        end
    end

    return status
end

-- Get diff for a specific file
-- @param file_path String path of the file to get diff for
-- @param staged Boolean whether to get diff for staged changes
-- @return String containing the diff output
function git_repo.get_file_diff(file_path, staged)
    if not file_path or file_path == "" then
        return nil, "Invalid file path"
    end

    local args = {"diff"}

    if staged then
        table.insert(args, "--staged")
    end

    table.insert(args, file_path)

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        return nil, "Failed to get diff: " .. (err or result.stderr or "unknown error")
    end

    return result.stdout
end

-- Parse Git branch list output
-- @param branch_output String output from git branch command
-- @return Table containing branch information
function git_repo.parse_branches(branch_output)
    if not branch_output then
        return nil, "No branch output to parse"
    end

    local branches = {
        current = nil,
        list = {}
    }

    for line in branch_output:gmatch("[^\n]+") do
        local is_current = line:match("^%*")
        local branch_name = line:match("^%*?%s*(.-)%s*$")

        if branch_name and branch_name ~= "" then
            table.insert(branches.list, branch_name)
            if is_current then
                branches.current = branch_name
            end
        end
    end

    return branches
end

-- Parse Git log output
-- @param log_output String output from git log command
-- @return Table containing commit information
function git_repo.parse_log(log_output)
    if not log_output then
        return nil, "No log output to parse"
    end

    local commits = {}
    local current_commit = nil

    for line in log_output:gmatch("[^\n]+") do
        local commit_match = line:match("^commit%s+([0-9a-f]+)")
        local author_match = line:match("^Author:%s+(.+)")
        local date_match = line:match("^Date:%s+(.+)")

        if commit_match then
            if current_commit then
                table.insert(commits, current_commit)
            end
            current_commit = {
                hash = commit_match,
                author = nil,
                date = nil,
                message = nil
            }
        elseif author_match and current_commit then
            current_commit.author = author_match
        elseif date_match and current_commit then
            current_commit.date = date_match
        elseif line:match("^%s+") and current_commit then
            local message = line:match("^%s+(.+)")
            if message and message ~= "" then
                current_commit.message = message
            end
        end
    end

    if current_commit then
        table.insert(commits, current_commit)
    end

    return commits
end

return git_repo