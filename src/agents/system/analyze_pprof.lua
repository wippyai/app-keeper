local exec = require("exec")
local json = require("json")

local function handler(params)
    if not params.profile_path then
        return {
            success = false,
            error = "Missing required parameter: profile_path"
        }
    end

    local profile_path = params.profile_path
    local analysis_type = params.analysis_type or "top"
    local lines = params.lines or 10
    local focus = params.focus

    local result = {
        success = true,
        profile_path = profile_path,
        analysis_type = analysis_type,
        lines = lines
    }

    -- Build pprof command
    local cmd_parts = {"go", "tool", "pprof"}

    -- Add analysis flags
    if analysis_type == "top" then
        table.insert(cmd_parts, "-top")
    elseif analysis_type == "list" then
        table.insert(cmd_parts, "-list")
        table.insert(cmd_parts, ".*")
    elseif analysis_type == "tree" then
        table.insert(cmd_parts, "-tree")
    elseif analysis_type == "peek" then
        table.insert(cmd_parts, "-peek")
        table.insert(cmd_parts, ".*")
    elseif analysis_type == "disasm" then
        table.insert(cmd_parts, "-disasm")
        table.insert(cmd_parts, ".*")
    end

    -- Add nodecount for limiting output
    table.insert(cmd_parts, "-nodecount=" .. lines)

    -- Add focus if specified
    if focus then
        table.insert(cmd_parts, "-focus=" .. focus)
        result.focus = focus
    end

    -- Add profile path
    table.insert(cmd_parts, profile_path)

    local cmd = table.concat(cmd_parts, " ")

    -- Get executor
    local executor = exec.get("app:executor")

    -- Execute pprof command
    local proc = executor:exec(cmd)
    proc:start()

    -- Capture output
    local output = ""
    local output_stream = proc:stdout_stream()

    while true do
        local chunk = output_stream:read()
        if not chunk then break end
        output = output .. chunk

        -- Size protection: limit to 5KB
        if #output > 5120 then
            output = output:sub(1, 5120) .. "\n... [OUTPUT TRUNCATED AT 5KB LIMIT]"
            break
        end
    end

    output_stream:close()

    -- Capture stderr for errors
    local error_output = ""
    local error_stream = proc:stderr_stream()

    while true do
        local chunk = error_stream:read()
        if not chunk then break end
        error_output = error_output .. chunk

        -- Limit error output too
        if #error_output > 1024 then
            error_output = error_output:sub(1, 1024) .. "\n... [ERROR OUTPUT TRUNCATED]"
            break
        end
    end

    error_stream:close()

    local exit_code, err = proc:wait()
    executor:release()

    if exit_code ~= 0 then
        result.success = false
        result.error = "pprof failed with exit code " .. exit_code
        if #error_output > 0 then
            result.error = result.error .. ": " .. error_output
        end
        return result
    end

    result.output = output
    result.command = cmd
    result.output_size = #output

    if #error_output > 0 then
        result.warnings = error_output
    end

    return result
end

return {
    handler = handler
}