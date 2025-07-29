local funcs = require("funcs")

local function handler(params)
    -- 1. Input Validation
    if not params or type(params) ~= "table" then
        return { success = false, error = "Invalid input: params must be a table." }
    end
    if not params.target_id or type(params.target_id) ~= "string" or params.target_id == "" then
        return { success = false, error = "Missing or invalid required parameter: target_id (string)" }
    end
    -- Ensure namespace is present
    if not string.find(params.target_id, ":") then
         return { success = false, error = "Invalid target_id: Namespace is required (e.g., 'namespace:name')." }
    end

    local args_to_pass = params.args
    -- Ensure args_to_pass is a table if provided, default to empty table if nil
    if args_to_pass == nil then
        args_to_pass = {}
    elseif type(args_to_pass) ~= "table" then
         return { success = false, error = "Invalid parameter: args must be a table if provided." }
    end

    -- 2. Create Executor
    -- Assuming funcs.new() raises error on failure as per spec
    local executor = funcs.new()

    -- 3. Call Target Function
    -- Pass the args table as the single argument to the target function
    local result, err = executor:call(params.target_id, args_to_pass)

    -- 4. Format and Return Response
    if err then
        return { success = false, error = "Call to '" .. params.target_id .. "' failed: " .. tostring(err) }
    else
        return { success = true, result = result }
    end
end

return { handler = handler }
