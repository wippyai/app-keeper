local exec = require("exec")
local json = require("json")

local function handler(params)
    local profiles = params.profiles or {"cpu", "heap"}
    local cpu_seconds = params.cpu_seconds or 30
    local output_dir = params.output_dir or "./profiles"

    local result = {
        success = true,
        captured = {},
        failed = {},
        output_dir = output_dir
    }

    -- Get executor
    local executor = exec.get("app:executor")

    -- Create output directory
    local mkdir_proc = executor:exec("mkdir -p " .. output_dir)
    mkdir_proc:start()
    local exit_code, err = mkdir_proc:wait()

    if exit_code ~= 0 then
        executor:release()
        return {
            success = false,
            error = "Failed to create output directory: " .. (err or "unknown error")
        }
    end

    -- Capture each requested profile
    for _, profile_type in ipairs(profiles) do
        local url = "http://localhost:6060/debug/pprof/" .. profile_type
        local filename = output_dir .. "/" .. profile_type .. ".prof"

        -- Add seconds parameter for CPU profile
        if profile_type == "cpu" then
            url = url .. "?seconds=" .. cpu_seconds
        end

        -- Execute curl command
        local curl_cmd = string.format("curl -s \"%s\" -o \"%s\"", url, filename)
        local proc = executor:exec(curl_cmd)
        proc:start()

        local exit_code, err = proc:wait()

        if exit_code == 0 then
            table.insert(result.captured, {
                type = profile_type,
                file = filename,
                url = url
            })
        else
            table.insert(result.failed, {
                type = profile_type,
                error = "curl failed with exit code " .. exit_code,
                url = url
            })
        end
    end

    executor:release()

    -- Check if any captures succeeded
    if #result.captured == 0 then
        result.success = false
        result.error = "No profiles were successfully captured"
    end

    return result
end

return {
    handler = handler
}