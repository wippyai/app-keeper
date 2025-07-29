local exec = require("exec")
local json = require("json")
local git_repo = require("git_repo")
local env = require("env")

-- Git remote operations
local remote = {}

-- List remotes
-- @return Table containing remote information
function remote.list()
    local result, err = git_repo.exec_git_command({"remote", "-v"})
    if err or not result.success then
        return nil, "Failed to list remotes: " .. (err or result.stderr or "unknown error")
    end

    local remotes = {}
    for line in result.stdout:gmatch("[^\n]+") do
        local name, url, type = line:match("([^%s]+)%s+([^%s]+)%s+%(([^%)]+)%)")
        if name and url and type then
            if not remotes[name] then
                remotes[name] = {
                    name = name,
                    urls = {}
                }
            end
            remotes[name].urls[type] = url
        end
    end

    -- Convert to array
    local remote_array = {}
    for _, remote_data in pairs(remotes) do
        table.insert(remote_array, remote_data)
    end

    return remote_array
end

-- Pull changes from remote
-- @param remote_name String optional remote name (default: "origin")
-- @param branch_name String optional branch name (default: current branch)
-- @return Boolean indicating success or failure
function remote.pull(remote_name, branch_name)
    remote_name = remote_name or git_repo.DEFAULT_REMOTE

    local args = {"pull"}
    table.insert(args, remote_name)

    if branch_name and branch_name ~= "" then
        table.insert(args, branch_name)
    end

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        return nil, "Failed to pull changes: " .. (err or result.stderr or "unknown error")
    end

    return {
        success = true,
        message = result.stdout
    }
end

-- Push changes to remote
-- @param remote_name String optional remote name (default: "origin")
-- @param branch_name String optional branch name (default: current branch)
-- @param force Boolean optional flag to force push
-- @return Boolean indicating success or failure
function remote.push(remote_name, branch_name, force)
    remote_name = remote_name or git_repo.DEFAULT_REMOTE

    local args = {"push"}

    if force then
        table.insert(args, "--force")
    end

    table.insert(args, remote_name)

    if branch_name and branch_name ~= "" then
        table.insert(args, branch_name)
    end

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        return nil, "Failed to push changes: " .. (err or result.stderr or "unknown error")
    end

    return {
        success = true,
        message = result.stdout
    }
end

-- Fetch updates from remote
-- @param remote_name String optional remote name (default: "origin")
-- @param all Boolean optional flag to fetch from all remotes
-- @return Boolean indicating success or failure
function remote.fetch(remote_name, all)
    local args = {"fetch"}

    if all then
        table.insert(args, "--all")
    else
        remote_name = remote_name or git_repo.DEFAULT_REMOTE
        table.insert(args, remote_name)
    end

    local result, err = git_repo.exec_git_command(args)
    if err or not result.success then
        return nil, "Failed to fetch updates: " .. (err or result.stderr or "unknown error")
    end

    return {
        success = true,
        message = result.stdout
    }
end

-- Add a remote
-- @param name String remote name
-- @param url String remote URL
-- @return Boolean indicating success or failure
function remote.add(name, url)
    if not name or name == "" or not url or url == "" then
        return nil, "Invalid remote name or URL"
    end

    local result, err = git_repo.exec_git_command({"remote", "add", name, url})
    if err or not result.success then
        return nil, "Failed to add remote: " .. (err or result.stderr or "unknown error")
    end

    return true
end

-- Remove a remote
-- @param name String remote name
-- @return Boolean indicating success or failure
function remote.remove(name)
    if not name or name == "" then
        return nil, "Invalid remote name"
    end

    local result, err = git_repo.exec_git_command({"remote", "remove", name})
    if err or not result.success then
        return nil, "Failed to remove remote: " .. (err or result.stderr or "unknown error")
    end

    return true
end

return remote