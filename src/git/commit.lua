local exec = require("exec")
local json = require("json")
local time = require("time")
local git_repo = require("git_repo")
local env = require("env")

-- Git commit operations
local commit = {}

-- Stage a file
-- @param file_path String path of the file to stage
-- @return Boolean indicating success or failure
function commit.stage_file(file_path)
    if not file_path or file_path == "" then
        return nil, "Invalid file path"
    end

    local result, err = git_repo.exec_git_command({"add", file_path})
    if err or not result.success then
        return nil, "Failed to stage file: " .. (err or result.stderr or "unknown error")
    end

    return true
end

-- Stage all changes
-- @return Boolean indicating success or failure
function commit.stage_all()
    local result, err = git_repo.exec_git_command({"add", "."})
    if err or not result.success then
        return nil, "Failed to stage all changes: " .. (err or result.stderr or "unknown error")
    end

    return true
end

-- Unstage a file
-- @param file_path String path of the file to unstage
-- @return Boolean indicating success or failure
function commit.unstage_file(file_path)
    if not file_path or file_path == "" then
        return nil, "Invalid file path"
    end

    local result, err = git_repo.exec_git_command({"reset", "HEAD", file_path})
    if err or not result.success then
        return nil, "Failed to unstage file: " .. (err or result.stderr or "unknown error")
    end

    return true
end

-- Create a commit
-- @param message String commit message
-- @param author String optional author information
-- @return Boolean indicating success or failure
function commit.create(message, author)
    if not message or message == "" then
        return nil, "Invalid commit message"
    end

    local args = {"commit", "-m", message}

    if author and author ~= "" then
        table.insert(args, "--author")
        table.insert(args, author)
    end

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        -- Check if there's nothing to commit
        if result.stderr and result.stderr:match("nothing to commit") then
            return nil, "Nothing to commit"
        end
        return nil, "Failed to create commit: " .. (err or result.stderr or "unknown error")
    end

    -- Parse commit hash from output
    local commit_hash = result.stdout:match("(%[[^%]]+%])[%s%S]*([a-f0-9]+)")
    if not commit_hash then
        commit_hash = "unknown"
    end

    return {
        success = true,
        hash = commit_hash,
        timestamp = os.time()
    }
end

-- Amend the last commit
-- @param message String optional new commit message
-- @return Boolean indicating success or failure
function commit.amend(message)
    local args = {"commit", "--amend"}

    if message and message ~= "" then
        table.insert(args, "-m")
        table.insert(args, message)
    else
        table.insert(args, "--no-edit")
    end

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        return nil, "Failed to amend commit: " .. (err or result.stderr or "unknown error")
    end

    return true
end

-- Get commit history
-- @param count Number optional number of commits to retrieve (default: 10)
-- @return Table containing commit history
function commit.history(count)
    count = count or 10

    local result, err = git_repo.exec_git_command({"log", "-" .. tostring(count)})
    if err or not result.success then
        return nil, "Failed to get commit history: " .. (err or result.stderr or "unknown error")
    end

    local commits, parse_err = git_repo.parse_log(result.stdout)
    if parse_err then
        return nil, "Failed to parse commit log: " .. parse_err
    end

    return commits
end

return commit