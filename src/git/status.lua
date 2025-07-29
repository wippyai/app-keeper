local exec = require("exec")
local json = require("json")
local git_repo = require("git_repo")
local env = require("env")

-- Git status operations
local status = {}

-- Status error messages
local ERR_MSG = {
    STATUS_FAILED = "Failed to get Git status: ",
    BRANCH_FAILED = "Failed to get current branch: ",
    COUNT_FAILED = "Failed to get ahead/behind counts: ",
    COMMIT_FAILED = "Failed to get last commit: ",
    INVALID_LOG = "Invalid log output format"
}

-- Git commands
local GIT_CMD = {
    REV_PARSE = "rev-parse",
    LOG = "log",
    REV_LIST = "rev-list"
}

-- Get full repository status
-- @return Table containing repository status information
function status.get_full_status()
    -- Get status using porcelain format for reliability
    local status_info, err = git_repo.parse_status()
    if err then
        return nil, ERR_MSG.STATUS_FAILED .. err
    end

    -- Get ahead/behind counts
    local ahead_behind, err = status.get_ahead_behind_count()
    if not err and ahead_behind then
        status_info.ahead = ahead_behind.ahead
        status_info.behind = ahead_behind.behind
    end

    -- Get last commit info
    local last_commit, err = status.get_last_commit()
    if not err and last_commit then
        status_info.last_commit = last_commit
    end

    return status_info
end

-- Get ahead/behind count relative to remote branch
-- @return Table containing ahead and behind counts
function status.get_ahead_behind_count()
    -- Get current branch
    local branch_result, err = git_repo.exec_git_command({
        GIT_CMD.REV_PARSE,
        "--abbrev-ref",
        "HEAD"
    })

    if err or not branch_result.success then
        return nil, ERR_MSG.BRANCH_FAILED .. (err or branch_result.stderr or "unknown error")
    end

    local current_branch = branch_result.stdout:match("^%s*(.-)%s*$")
    if not current_branch or current_branch == "" then
        return nil, "Failed to determine current branch"
    end

    -- Get ahead/behind counts
    local count_result, err = git_repo.exec_git_command({
        GIT_CMD.REV_LIST,
        "--left-right",
        "--count",
        current_branch .. "..." .. git_repo.DEFAULT_REMOTE .. "/" .. current_branch
    })

    if err then
        return nil, ERR_MSG.COUNT_FAILED .. err
    end

    -- Even if the command failed (e.g., remote branch doesn't exist),
    -- we can still provide a default result
    local ahead, behind = 0, 0

    if count_result.success then
        ahead, behind = count_result.stdout:match("(%d+)%s+(%d+)")
        ahead, behind = tonumber(ahead) or 0, tonumber(behind) or 0
    end

    return {
        ahead = ahead,
        behind = behind
    }
end

-- Get last commit information
-- @return Table containing last commit details
function status.get_last_commit()
    local result, err = git_repo.exec_git_command({
        GIT_CMD.LOG,
        "-1",
        "--pretty=format:%H%n%an%n%ad%n%s"
    })

    if err or not result.success then
        return nil, ERR_MSG.COMMIT_FAILED .. (err or result.stderr or "unknown error")
    end

    local lines = {}
    for line in result.stdout:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    if #lines < 4 then
        return nil, ERR_MSG.INVALID_LOG
    end

    return {
        hash = lines[1],
        author = lines[2],
        date = lines[3],
        message = lines[4]
    }
end

-- Count changes by category
-- @return Table containing counts of staged, unstaged, and untracked files
function status.count_changes()
    local status_info, err = status.get_full_status()
    if err then
        return nil, err
    end

    return {
        staged = #(status_info.staged or {}),
        unstaged = #(status_info.unstaged or {}),
        untracked = #(status_info.untracked or {}),
        is_clean = status_info.is_clean
    }
end

-- Check if repository is clean
-- @return Boolean indicating if the repository is clean
function status.is_clean()
    local changes, err = status.count_changes()
    if err then
        return nil, err
    end

    return changes.is_clean
end

return status