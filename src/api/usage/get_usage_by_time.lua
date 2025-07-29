local http = require("http")
local json = require("json")
local time = require("time")
local token_usage_repo = require("token_usage_repo")

-- Time period constants
local PERIOD = {
    TODAY = "today",
    WEEK = "week",
    MONTH = "month",
    CUSTOM = "custom"
}

-- Helper function to get time range based on period
local function get_time_range(period, start_param, end_param)
    local now = os.time()
    local start_time, end_time

    if period == PERIOD.TODAY then
        -- Current day (midnight to now)
        local today = os.date("*t", now)
        today.hour, today.min, today.sec = 0, 0, 0
        start_time = os.time(today)
        end_time = now
    elseif period == PERIOD.WEEK then
        -- Last 7 days
        start_time = now - (7 * 24 * 60 * 60)
        end_time = now
    elseif period == PERIOD.MONTH then
        -- Last 30 days
        start_time = now - (30 * 24 * 60 * 60)
        end_time = now
    else
        -- Custom range from parameters (fallback to last 24 hours if not provided)
        start_time = tonumber(start_param) or (now - (24 * 60 * 60))
        end_time = tonumber(end_param) or now
    end

    return start_time, end_time
end

-- Helper function to determine best interval based on time range
local function get_default_interval(start_time, end_time)
    local range_seconds = end_time - start_time

    if range_seconds <= 60 * 60 * 24 then -- Less than 1 day
        return token_usage_repo.INTERVAL.HOUR
    elseif range_seconds <= 60 * 60 * 24 * 7 then -- Less than 1 week
        return token_usage_repo.INTERVAL.DAY
    elseif range_seconds <= 60 * 60 * 24 * 30 then -- Less than 1 month
        return token_usage_repo.INTERVAL.DAY
    else -- More than 1 month
        return token_usage_repo.INTERVAL.WEEK
    end
end

local function handler()
    local res = http.response()
    local req = http.request()

    if not res or not req then
        return nil, "Failed to get HTTP context"
    end

    -- Security is validated at a higher level, no need to check here

    -- Get parameters for time range
    local period = req:query("period") or PERIOD.TODAY
    local start_param = req:query("start_time")
    local end_param = req:query("end_time")
    local interval = req:query("interval")

    -- Validate period
    if period ~= PERIOD.TODAY and
       period ~= PERIOD.WEEK and
       period ~= PERIOD.MONTH and
       period ~= PERIOD.CUSTOM then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Invalid period parameter. Must be one of: today, week, month, custom"
        })
        return
    end

    -- If custom period, ensure start_time and end_time are provided and valid
    if period == PERIOD.CUSTOM and (not start_param or not end_param) then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Custom period requires both start_time and end_time parameters"
        })
        return
    end

    -- Get time range based on period
    local start_time, end_time = get_time_range(period, start_param, end_param)

    -- Validate interval if provided
    if interval and interval ~= token_usage_repo.INTERVAL.HOUR and
                    interval ~= token_usage_repo.INTERVAL.DAY and
                    interval ~= token_usage_repo.INTERVAL.WEEK and
                    interval ~= token_usage_repo.INTERVAL.MONTH then
        res:set_status(http.STATUS.BAD_REQUEST)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Invalid interval parameter. Must be one of: hour, day, week, month"
        })
        return
    end

    -- If interval not provided, determine best interval based on time range
    if not interval then
        interval = get_default_interval(start_time, end_time)
    end

    -- Get usage by time from repository
    local usage_data, err = token_usage_repo.get_usage_by_time(start_time, end_time, interval)
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:set_content_type(http.CONTENT.JSON)
        res:write_json({
            success = false,
            error = "Failed to get usage by time: " .. err
        })
        return
    end

    -- Format time range for response
    local time_range = {
        start_time = start_time,
        end_time = end_time,
        period = period,
        interval = interval,
        -- Add formatted timestamps
        start_formatted = time.unix(start_time, 0):format_rfc3339(),
        end_formatted = time.unix(end_time, 0):format_rfc3339()
    }

    -- Calculate totals across all periods
    local totals = {
        prompt_tokens = 0,
        completion_tokens = 0,
        thinking_tokens = 0,
        cache_read_tokens = 0,
        cache_write_tokens = 0,
        total_tokens = 0,
        request_count = 0
    }

    for _, period_data in ipairs(usage_data) do
        totals.prompt_tokens = totals.prompt_tokens + (period_data.prompt_tokens or 0)
        totals.completion_tokens = totals.completion_tokens + (period_data.completion_tokens or 0)
        totals.thinking_tokens = totals.thinking_tokens + (period_data.thinking_tokens or 0)
        totals.cache_read_tokens = totals.cache_read_tokens + (period_data.cache_read_tokens or 0)
        totals.cache_write_tokens = totals.cache_write_tokens + (period_data.cache_write_tokens or 0)
        totals.total_tokens = totals.total_tokens + (period_data.total_tokens or 0)
        totals.request_count = totals.request_count + (period_data.request_count or 0)
    end

    -- Return response
    res:set_status(http.STATUS.OK)
    res:set_content_type(http.CONTENT.JSON)
    res:write_json({
        success = true,
        time_range = time_range,
        periods = usage_data,
        totals = totals
    })
end

return {
    handler = handler
}