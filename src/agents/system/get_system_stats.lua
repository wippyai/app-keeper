local system = require("system")
local json = require("json")

local function format_size(bytes, format)
    if format == "bytes" then
        return bytes
    elseif format == "kb" then
        return bytes / 1024
    elseif format == "mb" then
        return bytes / (1024 * 1024)
    elseif format == "gb" then
        return bytes / (1024 * 1024 * 1024)
    else
        return bytes / (1024 * 1024)
    end
end

local function handler(params)
    local format = params.format or "mb"
    local result = {
        success = true,
        format = format
    }

    -- System info
    local hostname, _ = system.hostname()
    local pid, _ = system.pid()
    local num_cpu, _ = system.num_cpu()

    result.system = {
        hostname = hostname,
        pid = pid,
        num_cpu = num_cpu
    }

    -- Runtime info
    local goroutines, _ = system.num_goroutines()
    local max_procs, _ = system.go_max_procs()
    local gc_percent, _ = system.get_gc_percent()
    local memory_limit, _ = system.get_memory_limit()

    result.runtime = {
        goroutines = goroutines,
        max_procs = max_procs,
        gc_percent = gc_percent,
        memory_limit_bytes = memory_limit == math.maxinteger and -1 or memory_limit,
        memory_limit_formatted = memory_limit == math.maxinteger and "unlimited" or format_size(memory_limit, format)
    }

    -- Memory stats
    local mem_stats, _ = system.mem_stats()
    if mem_stats then
        result.memory = {
            alloc = format_size(mem_stats.alloc, format),
            total_alloc = format_size(mem_stats.total_alloc, format),
            sys = format_size(mem_stats.sys, format),
            heap_alloc = format_size(mem_stats.heap_alloc, format),
            heap_sys = format_size(mem_stats.heap_sys, format),
            heap_idle = format_size(mem_stats.heap_idle, format),
            heap_in_use = format_size(mem_stats.heap_in_use, format),
            heap_released = format_size(mem_stats.heap_released, format),
            heap_objects = mem_stats.heap_objects,
            stack_in_use = format_size(mem_stats.stack_in_use, format),
            stack_sys = format_size(mem_stats.stack_sys, format),
            mspan_in_use = format_size(mem_stats.mspan_in_use, format),
            mspan_sys = format_size(mem_stats.mspan_sys, format),
            num_gc = mem_stats.num_gc,
            next_gc = format_size(mem_stats.next_gc, format)
        }
    end

    return result
end

return {
    handler = handler
}