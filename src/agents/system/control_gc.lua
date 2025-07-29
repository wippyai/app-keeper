local system = require("system")
local json = require("json")

local function handler(params)
    if not params.action then
        return {
            success = false,
            error = "Missing required parameter: action"
        }
    end

    if params.action == "run" then
        local success, err = system.gc()
        if not success then
            return {
                success = false,
                error = "Failed to run garbage collection: " .. (err or "unknown error")
            }
        end
        return {
            success = true,
            gc_run = true
        }

    elseif params.action == "get_percent" then
        local percent, err = system.get_gc_percent()
        if not percent then
            return {
                success = false,
                error = "Failed to get GC percentage: " .. (err or "unknown error")
            }
        end
        return {
            success = true,
            gc_percent = percent
        }

    elseif params.action == "set_percent" then
        if not params.percent then
            return {
                success = false,
                error = "Missing required parameter: percent"
            }
        end

        local percent = tonumber(params.percent)
        if not percent or percent < 50 or percent > 1000 then
            return {
                success = false,
                error = "Invalid percent value: must be between 50 and 1000"
            }
        end

        local old_percent, err = system.set_gc_percent(percent)
        if not old_percent then
            return {
                success = false,
                error = "Failed to set GC percentage: " .. (err or "unknown error")
            }
        end

        return {
            success = true,
            previous_percent = old_percent,
            current_percent = percent
        }

    else
        return {
            success = false,
            error = "Invalid action: " .. params.action
        }
    end
end

return {
    handler = handler
}