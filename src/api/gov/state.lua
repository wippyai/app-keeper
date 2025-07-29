local http = require("http")
local json = require("json")
local registry = require("registry")
local time = require("time")
local gov_client = require("gov_client")

-- Constants
local GOVERNANCE_PROCESS_NAME = "registry.governance"

-- Handler function for HTTP endpoint
local function handler()
    local res = http.response()
    local req = http.request()

    if not req or not res then
        return nil, "Failed to get HTTP context"
    end

    -- Set JSON content type
    res:set_content_type(http.CONTENT.JSON)

    -- Get current registry version
    local current_version, err = registry.current_version()
    if err then
        res:set_status(http.STATUS.INTERNAL_ERROR)
        res:write_json({
            success = false,
            message = "Failed to get current registry version: " .. err
        })
        return
    end

    -- Try to get the governance process PID
    local governance_pid = process.registry.lookup(GOVERNANCE_PROCESS_NAME)
    local governance_status = "unknown"
    local has_changes = false

    -- Use the client library to get system state
    if governance_pid then
        governance_status = "running"

        local system_state, err = gov_client.get_state({}, 5000)  -- 5 second timeout

        if system_state then
            -- Extract change status information
            has_changes = system_state.changes.filesystem_changes_pending or system_state.changes.registry_changes_pending
        end
    end

    -- Build response with current state (maintains old format for FE compatibility)
    local state = {
        success = true,
        registry = {
            current_version = current_version:id(),
            timestamp = time.now():unix(),
            has_changes = has_changes
        },
        syncer = {
            status = governance_status
        }
    }

    res:set_status(http.STATUS.OK)
    res:write_json(state)
end

return {
    handler = handler
}