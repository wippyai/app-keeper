-- file: get_contextual_entries.lua

local funcs = require("funcs")
local yaml = require("yaml")

-- Registry IDs of the functions we need to call
local FIND_RELEVANT_ID = "wippy.keeper.agents.registry:find_relevant"
local GET_ENTRIES_ID = "wippy.keeper.agents.registry:get_entries"

-- Helper function to create a standardized YAML error response
-- Uses the yaml module as requested.
local function create_error_yaml(error_message)
  local error_data = { success = false, error = error_message }
  -- Encode the error data into a YAML string
  local yaml_output, err_encode = yaml.encode(error_data, { indent = 2 })
  if not yaml_output then
    -- Fallback in case YAML encoding itself fails
    return "success: false\nerror: Failed to encode error message to YAML: " .. (err_encode or "unknown encoding error")
  end
  return yaml_output
end

-- Main handler function for the tool
local function handler(params)
  -- 1. --- Input Validation ---
  if not params or not params.query or type(params.query) ~= "string" or params.query == "" then
    return create_error_yaml("Missing or invalid required parameter: query (must be a non-empty string)")
  end
  local query = params.query

  -- 2. --- Initialize Funcs Executor ---
  -- Use funcs.new() to get an executor instance.
  local executor, err_funcs = funcs.new()
  if not executor then
    local err_msg = "Failed to initialize function executor: " .. (err_funcs or "unknown error")
    return create_error_yaml(err_msg)
  end

  -- 3. --- Call 'find_relevant' Function via Funcs ---
  -- Use the executor to call the find_relevant function by its ID.
  local find_payload = { query = query }
  local find_result_data, err_find = executor:call(FIND_RELEVANT_ID, find_payload)

  if err_find then
    -- Handle error during the call to find_relevant
    local err_msg = string.format("Error calling '%s': %s", FIND_RELEVANT_ID, err_find)
    return create_error_yaml(err_msg)
  end

  -- 4. --- Process 'find_relevant' Result ---
  -- We expect find_result_data to be a Lua table like { success = true, result = {id1, id2, ...} }
  -- or { success = false, error = "..." }
  if type(find_result_data) ~= "table" or not find_result_data.success then
    local err_msg = string.format("Function '%s' failed or returned unexpected data. Error: %s",
                                  FIND_RELEVANT_ID,
                                  (find_result_data and find_result_data.error) or "Unknown error from find_relevant")
    return create_error_yaml(err_msg)
  end

  if not find_result_data.result or type(find_result_data.result) ~= "table" then
     return create_error_yaml(string.format("Function '%s' returned invalid result structure.", FIND_RELEVANT_ID))
  end

  local relevant_ids = find_result_data.result

  -- 5. --- Call 'get_entries' Function via Funcs ---
  -- Prepare payload for get_entries
  local get_payload = { ids = relevant_ids }
  -- Call get_entries using the executor.
  -- IMPORTANT: The 'get_entries' function is designed to return a YAML *string* directly.
  local get_entries_yaml_output, err_get = executor:call(GET_ENTRIES_ID, get_payload)

  if err_get then
    -- Handle error during the call to get_entries
    local err_msg = string.format("Error calling '%s': %s", GET_ENTRIES_ID, err_get)
    return create_error_yaml(err_msg)
  end

  -- 6. --- Return Result ---
  -- The result from get_entries should already be the final YAML string.
  -- If the call succeeded but the output isn't a string, something is wrong upstream.
  if type(get_entries_yaml_output) ~= "string" then
      return create_error_yaml(string.format("Function '%s' did not return the expected YAML string output.", GET_ENTRIES_ID))
  end

  -- Return the YAML string directly
  return get_entries_yaml_output
end

-- Export the handler function
return {
  handler = handler
}
