local exec = require("exec")
local json = require("json")
local git_repo = require("git_repo")
local env = require("env")

-- Git branch operations
local branch = {}

-- List all branches in the repository
-- @param include_remote Boolean to include remote branches (default: false)
-- @return Table containing branch information
function branch.list(include_remote)
    local args = {"branch"}
    if include_remote then
        table.insert(args, "-a")
    end

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        return nil, "Failed to list branches: " .. (err or result.stderr or "unknown error")
    end

    local branches, parse_err = git_repo.parse_branches(result.stdout)
    if parse_err then
        return nil, "Failed to parse branches: " .. parse_err
    end

    return branches
end

-- Get current branch
-- @return String containing current branch name
function branch.current()
    local result, err = git_repo.exec_git_command({"rev-parse", "--abbrev-ref", "HEAD"})
    if err or not result.success then
        return nil, "Failed to get current branch: " .. (err or result.stderr or "unknown error")
    end

    local branch_name = result.stdout:match("^%s*(.-)%s*$")
    if not branch_name or branch_name == "" then
        return nil, "Failed to determine current branch"
    end

    return branch_name
end

-- Switch to a branch
-- @param branch_name String name of the branch to switch to
-- @return Boolean indicating success or failure
function branch.switch(branch_name)
    if not branch_name or branch_name == "" then
        return nil, "Invalid branch name"
    end

    local result, err = git_repo.exec_git_command({"checkout", branch_name})
    if err or not result.success then
        return nil, "Failed to switch to branch: " .. (err or result.stderr or "unknown error")
    end

    return true
end

-- Create a new branch
-- @param branch_name String name of the new branch
-- @param start_point String optional starting point for the branch
-- @return Boolean indicating success or failure
function branch.create(branch_name, start_point)
    if not branch_name or branch_name == "" then
        return nil, "Invalid branch name"
    end

    local args = {"branch", branch_name}
    if start_point and start_point ~= "" then
        table.insert(args, start_point)
    end

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        return nil, "Failed to create branch: " .. (err or result.stderr or "unknown error")
    end

    return true
end

-- Create a new branch and switch to it
-- @param branch_name String name of the new branch
-- @param start_point String optional starting point for the branch
-- @return Boolean indicating success or failure
function branch.create_and_switch(branch_name, start_point)
    if not branch_name or branch_name == "" then
        return nil, "Invalid branch name"
    end

    local args = {"checkout", "-b", branch_name}
    if start_point and start_point ~= "" then
        table.insert(args, start_point)
    end

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        return nil, "Failed to create and switch to branch: " .. (err or result.stderr or "unknown error")
    end

    return true
end

-- Delete a branch
-- @param branch_name String name of the branch to delete
-- @param force Boolean to force deletion even if not merged
-- @return Boolean indicating success or failure
function branch.delete(branch_name, force)
    if not branch_name or branch_name == "" then
        return nil, "Invalid branch name"
    end

    local option = force and "-D" or "-d"

    local result, err = git_repo.exec_git_command({"branch", option, branch_name})
    if err or not result.success then
        return nil, "Failed to delete branch: " .. (err or result.stderr or "unknown error")
    end

    return true
end

return branch