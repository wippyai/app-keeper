local http = require("http")
local json = require("json")
local security = require("security")
local status = require("status")
local env = require("env")
local llm = require("llm")
local prompt = require("prompt")
local git_repo = require("git_repo")

local function handler()
    local res = http.response()
    local req = http.request()

    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Security check
    local actor = security.actor()
    if not actor then
        res:set_status(http.STATUS.UNAUTHORIZED)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Authentication required"
        })
        return
    end

    -- Check request method
    if req:method() ~= http.METHOD.POST then
        res:set_status(http.STATUS.METHOD_NOT_ALLOWED)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Method not allowed"
        })
        return
    end

    -- Get repository status for file changes
    local repo_status, err = status.get_full_status()
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to get repository status: " .. err
        })
        return
    end

    -- Format status information for LLM
    local changes_summary = {}
    local file_changes = {}

    -- Track all file changes
    local all_files = {}

    -- Add staged files
    if repo_status.staged and #repo_status.staged > 0 then
        table.insert(changes_summary, "Staged changes:")
        for _, file in ipairs(repo_status.staged) do
            table.insert(changes_summary, "  - " .. file.status .. ": " .. file.file)
            table.insert(all_files, {status = file.status, file = file.file, staged = true})
        end
    end

    -- Add unstaged files
    if repo_status.unstaged and #repo_status.unstaged > 0 then
        table.insert(changes_summary, "Unstaged changes:")
        for _, file in ipairs(repo_status.unstaged) do
            table.insert(changes_summary, "  - " .. file.status .. ": " .. file.file)
            table.insert(all_files, {status = file.status, file = file.file, staged = false})
        end
    end

    -- Add untracked files
    if repo_status.untracked and #repo_status.untracked > 0 then
        table.insert(changes_summary, "Untracked files:")
        for _, file in ipairs(repo_status.untracked) do
            table.insert(changes_summary, "  - " .. file.status .. ": " .. file.file)
            table.insert(all_files, {status = file.status, file = file.file, staged = false})
        end
    end

    -- If no changes, return an error
    if #all_files == 0 then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "No changes to commit"
        })
        return
    end

    -- Get diff for each file
    for _, file in ipairs(all_files) do
        -- Skip untracked files as they don't have diffs
        if file.status ~= "untracked" then
            local diff, err = git_repo.get_file_diff(file.file, file.staged)
            if not err and diff and diff ~= "" then
                table.insert(file_changes, "Diff for " .. file.file .. ":")
                table.insert(file_changes, diff)
                table.insert(file_changes, "")  -- Empty line for separation
            end
        end
    end

    -- Create prompt for the LLM
    local builder = prompt.new()
    builder:add_system([[
You are a helpful AI that generates concise and informative Git commit messages based on changed files.
Follow these guidelines:
1. Keep the message under 72 characters if possible
2. Use the imperative mood (e.g., "Add" not "Added")
3. Start with a capital letter
4. No period at the end
5. Be specific but concise
6. Focus on WHY the change was made, not just WHAT was changed
7. For multiple files with related changes, create a unified message that captures the overall purpose
8. Return the message in this format:

   Overall changes description

   * itemized change 1
   * itemized change 2
   * etc.
]])

    -- Add user prompt with file changes
    builder:add_user("Generate a commit message for the following changes:\n\n" ..
                     table.concat(changes_summary, "\n") ..
                     "\n\nFile content changes:\n\n" ..
                     table.concat(file_changes, "\n"))

    -- Generate commit message using the LLM
    local response = llm.generate(builder, {
        model = "o4-mini", -- todo: use env
        options = {
            temperature = 1,
            max_tokens = 500
        }
    })

    -- Check for errors
    if response.error then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to generate commit message: " .. response.error_message
        })
        return
    end

    -- Return the generated commit message
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        message = response.result
    })
end

return {
    handler = handler
}