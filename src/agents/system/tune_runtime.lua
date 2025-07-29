local system = require("system")
local json = require("json")

local function handler(params)
    if not params.parameter then
        return {
            success = false,
            error = "Missing required parameter: parameter"
        }
    end

    if not params.action then
        return {
            success = false,
            error = "Missing required parameter: action"
        }
    end

    if params.parameter == "max_procs" then
        if params.action == "get" then
            local max_procs, err = system.go_max_procs()
            if not max_procs then
                return {
                    success = false,
                    error = "Failed to get GOMAXPROCS: " .. (err or "unknown error")
                }
            end
            return {
                success = true,
                max_procs = max_procs
            }

        elseif params.action == "set" then
            if not params.value then
                return {
                    success = false,
                    error = "Missing required parameter: value"
                }
            end

            local value = tonumber(params.value)
            if not value or value < 1 or math.floor(value) ~= value then
                return {
                    success = false,
                    error = "Invalid value: must be a positive integer"
                }
            end

            local old_max_procs, err = system.go_max_procs(value)
            if not old_max_procs then
                return {
                    success = false,
                    error = "Failed to set GOMAXPROCS: " .. (err or "unknown error")
                }
            end

            return {
                success = true,
                previous_max_procs = old_max_procs,
                current_max_procs = value
            }
        end

    elseif params.parameter == "memory_limit" then
        if params.action == "get" then
            local limit, err = system.get_memory_limit()
            if not limit then
                return {
                    success = false,
                    error = "Failed to get memory limit: " .. (err or "unknown error")
                }
            end
            return {
                success = true,
                memory_limit_bytes = limit == math.maxinteger and -1 or limit,
                memory_limit_mb = limit == math.maxinteger and "unlimited" or (limit / (1024 * 1024))
            }

        elseif params.action == "set" then
            if params.value == nil then
                return {
                    success = false,
                    error = "Missing required parameter: value"
                }
            end

            local value = tonumber(params.value)
            if not value or (value ~= -1 and value <= 0) then
                return {
                    success = false,
                    error = "Invalid value: must be -1 (unlimited) or a positive number"
                }
            end

            -- Convert MB to bytes
            local limit_bytes = value == -1 and -1 or (value * 1024 * 1024)

            local old_limit, err = system.set_memory_limit(limit_bytes)
            if not old_limit then
                return {
                    success = false,
                    error = "Failed to set memory limit: " .. (err or "unknown error")
                }
            end

            return {
                success = true,
                previous_limit_bytes = old_limit == math.maxinteger and -1 or old_limit,
                previous_limit_mb = old_limit == math.maxinteger and "unlimited" or (old_limit / (1024 * 1024)),
                current_limit_bytes = value == -1 and -1 or limit_bytes,
                current_limit_mb = value == -1 and "unlimited" or value
            }
        end

    else
        return {
            success = false,
            error = "Invalid parameter: " .. params.parameter
        }
    end

    return {
        success = false,
        error = "Invalid action: " .. params.action
    }
end

return {
    handler = handler
}