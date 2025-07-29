local registry = require("registry")
local funcs = require("funcs")
local json = require("json")
local time = require("time")

local function handler(params)
    -- Validate required parameters - at least one selection parameter is needed
    if not params.id and not params.group and not params.namespace and not (params.tags and #params.tags > 0) then
        return {
            success = false,
            error = "Missing test selection parameter: at least one of id, group, namespace, or tags must be provided"
        }
    end

    -- Set up filter options based on parameters
    local options = {
        ["meta.type"] = "test"
    }

    -- Apply specific filters based on provided parameters
    if params.id then
        options[".id"] = params.id
    end

    if params.group then
        options["meta.group"] = params.group
    end

    if params.namespace then
        options[".ns"] = params.namespace
    end

    if params.tags then
        options["meta.tags"] = params.tags
    end

    -- Find tests matching the criteria
    local tests, err = registry.find(options)
    if err then
        return {
            success = false,
            error = "Failed to find tests: " .. (err or "unknown error")
        }
    end

    if not tests or #tests == 0 then
        return {
            success = false,
            error = "No tests found matching the specified criteria"
        }
    end

    print("DEBUG: Found " .. #tests .. " tests matching criteria")

    -- Set up inbox to collect test messages
    local inbox = process.listen("test:result")
    if not inbox then
        return {
            success = false,
            error = "Failed to create process inbox for test results"
        }
    end

    -- Set up execution options
    local execution_options = {
        pid = process.pid(),
        topic = "test:result",
        timeout = params.timeout or "5m"
    }

    -- If specific suite or test name is provided, add to options
    if params.suite then
        execution_options.suite = params.suite
    end

    if params.test then
        execution_options.test = params.test
    end

    -- Create function executor
    local executor = funcs.new()

    -- Prepare result data structure
    local results = {
        success = true,
        tests_total = #tests,
        tests_completed = 0,
        tests_passed = 0,
        tests_failed = 0,
        execution_time = 0,
        test_results = {}
    }

    -- Create channels for controlling message processing
    local done_ch = channel.new()
    local test_done_ch = channel.new(5) -- Increased buffer size
    local wait_ch = channel.new(1)
    local test_events = {}

    -- Map test IDs to execution IDs for easier lookup
    local test_id_map = {}

    -- Structure to track detailed suite and test case information
    local suite_details = {}

    -- Extract the test ID from a reference ID
    local function extract_test_id(ref_id)
        if not ref_id then return nil end

        -- Try to match the format where test ID is after a colon
        local _, _, test_id = string.find(ref_id, ":([^:]+)$")

        -- If that doesn't work, try other pattern matching
        if not test_id then
            -- Try to extract based on known test ID patterns
            for pattern in string.gmatch(ref_id, "([^:|]+)") do
                if string.match(pattern, "%.") then
                    -- This looks like a namespaced ID (e.g. "wippy.actor:actor_test")
                    test_id = pattern
                    break
                end
            end
        end

        return test_id
    end

    -- Helper function that waits for completion event
    local function wait_for_completion(ch, timeout_duration)
        local timeout_ch = time.after(timeout_duration)
        local result = channel.select {
            ch:case_receive(),
            timeout_ch:case_receive()
        }
        if result.channel == ch then
            return result.value
        end
        return false
    end

    -- Count the number of elements in a table
    local function count_table_elements(t)
        local count = 0
        for _ in pairs(t) do
            count = count + 1
        end
        return count
    end

    -- Message processor coroutine
    -- Message processor coroutine
    coroutine.spawn(function()
        -- Collect generic test events by test ID
        local generic_events = {}
        local suite_test_cases = {}

        while true do
            local result = channel.select {
                inbox:case_receive(),
                done_ch:case_receive()
            }

            if not result.ok then break end

            -- Process the received message
            local msg = result.value
            local execution_id = msg.ref_id
            local msg_type = msg.type or "unknown"
            local msg_data = msg.data or {}

            -- Try to find the test_id in different ways
            local test_id = nil

            -- Method 1: From message data
            if msg_data.id then
                test_id = msg_data.id
            end

            -- Method 2: Extract from ref_id (handles different PID formats)
            if execution_id then
                local extracted_id = extract_test_id(execution_id)
                if extracted_id then
                    test_id = extracted_id
                end
            end

            -- Process test suite/case data for all messages regardless of match
            if msg_type == "test:case:start" or msg_type == "test:case:pass" or msg_type == "test:case:fail" or msg_type == "test:case:skip" then
                local suite_name = msg_data.suite
                local test_name = msg_data.test

                if suite_name and test_name then
                    -- Create suite if it doesn't exist
                    if not suite_test_cases[suite_name] then
                        suite_test_cases[suite_name] = {
                            name = suite_name,
                            passed = 0,
                            failed = 0,
                            skipped = 0,
                            total = 0,
                            tests = {}
                        }
                    end

                    -- Update test case status
                    if msg_type == "test:case:pass" then
                        suite_test_cases[suite_name].tests[test_name] = {
                            name = test_name,
                            status = "passed",
                            duration = msg_data.duration or 0
                        }

                        -- Only count if we haven't already (avoid duplicates)
                        if not suite_test_cases[suite_name].tests[test_name].counted then
                            suite_test_cases[suite_name].passed = suite_test_cases[suite_name].passed + 1
                            suite_test_cases[suite_name].total = suite_test_cases[suite_name].total + 1
                            suite_test_cases[suite_name].tests[test_name].counted = true
                        end

                    elseif msg_type == "test:case:fail" then
                        suite_test_cases[suite_name].tests[test_name] = {
                            name = test_name,
                            status = "failed",
                            error = msg_data.error,
                            duration = msg_data.duration or 0
                        }

                        -- Only count if we haven't already (avoid duplicates)
                        if not suite_test_cases[suite_name].tests[test_name].counted then
                            suite_test_cases[suite_name].failed = suite_test_cases[suite_name].failed + 1
                            suite_test_cases[suite_name].total = suite_test_cases[suite_name].total + 1
                            suite_test_cases[suite_name].tests[test_name].counted = true
                        end

                    elseif msg_type == "test:case:skip" then
                        suite_test_cases[suite_name].tests[test_name] = {
                            name = test_name,
                            status = "skipped"
                        }

                        -- Only count if we haven't already (avoid duplicates)
                        if not suite_test_cases[suite_name].tests[test_name].counted then
                            suite_test_cases[suite_name].skipped = suite_test_cases[suite_name].skipped + 1
                            suite_test_cases[suite_name].total = suite_test_cases[suite_name].total + 1
                            suite_test_cases[suite_name].tests[test_name].counted = true
                        end
                    end
                end
            end

            -- Save the plan if we receive it
            if msg_type == "test:plan" and msg_data.suites then
                -- Initialize suite structure from the plan if available
                for _, suite in ipairs(msg_data.suites) do
                    if suite.name and not suite_test_cases[suite.name] then
                        suite_test_cases[suite.name] = {
                            name = suite.name,
                            passed = 0,
                            failed = 0,
                            skipped = 0,
                            total = 0,
                            tests = {}
                        }
                    end
                end
            end

            -- Find the execution ID that matches this test_id
            local matched_execution_id = nil

            -- Direct match on execution_id
            if execution_id and results.test_results[execution_id] then
                matched_execution_id = execution_id
            -- Match by test_id from our mapping
            elseif test_id and test_id_map[test_id] then
                matched_execution_id = test_id_map[test_id]
            -- Try flexible matching on all known execution_ids
            else
                for exec_id, result in pairs(results.test_results) do
                    -- If the ref_id contains our test ID
                    if execution_id and string.find(execution_id, result.id, 1, true) then
                        matched_execution_id = exec_id
                        break
                    -- Or if our test ID matches the one in the result
                    elseif test_id and test_id == result.id then
                        matched_execution_id = exec_id
                        break
                    end
                end
            end

            -- If we found a match, process the message
            if matched_execution_id then
                if not test_events[matched_execution_id] then
                    test_events[matched_execution_id] = {}
                end

                table.insert(test_events[matched_execution_id], {
                    type = msg_type,
                    data = msg_data
                })

                -- Process specific event types
                if msg_type == "test:suite:result" and msg_data then
                    local suite_name = msg_data.name or "unnamed"
                    local suite_result = {
                        name = suite_name,
                        passed = msg_data.passed or 0,
                        failed = msg_data.failed or 0,
                        skipped = msg_data.skipped or 0,
                        total = msg_data.total or 0,
                        status = msg_data.status or "unknown",
                        duration = msg_data.duration or 0,
                        tests = {}
                    }

                    -- Add individual test results if available
                    if msg_data.tests then
                        suite_result.tests = msg_data.tests
                    end

                    -- Add suite result to test result
                    if not results.test_results[matched_execution_id].suites then
                        results.test_results[matched_execution_id].suites = {}
                    end

                    table.insert(results.test_results[matched_execution_id].suites, suite_result)
                end

                -- Process test:complete message to update test status and attach suite details
                if msg_type == "test:complete" then
                    -- Update test status based on the complete message
                    if msg_data.status == "passed" then
                        results.test_results[matched_execution_id].status = "passed"
                        -- Only update counters if we're not double-counting
                        if results.test_results[matched_execution_id].status ~= "passed" then
                            results.tests_passed = results.tests_passed + 1
                            results.tests_failed = math.max(0, results.tests_failed - 1)
                        end
                    else
                        -- Ensure failed status is set
                        results.test_results[matched_execution_id].status = "failed"
                    end

                    -- Add suite details gathered from individual test cases - FOR ALL TESTS
                    local suites_array = {}
                    for suite_name, suite_data in pairs(suite_test_cases) do
                        -- Convert tests map to array
                        local tests_array = {}
                        for test_name, test_data in pairs(suite_data.tests) do
                            table.insert(tests_array, test_data)
                        end

                        -- Clean up the internal tracking field
                        for i, test in ipairs(tests_array) do
                            test.counted = nil
                        end

                        suite_data.tests = tests_array
                        table.insert(suites_array, suite_data)
                    end

                    results.test_results[matched_execution_id].suites = suites_array

                    -- Signal completion
                    test_done_ch:send(msg)
                end
            else
                -- For messages without a matching execution ID
                -- Store in generic events
                if test_id then
                    if not generic_events[test_id] then
                        generic_events[test_id] = {}
                    end
                    table.insert(generic_events[test_id], {
                        type = msg_type,
                        data = msg_data
                    })
                end

                -- For completion events, always try to use the data to update statuses
                if msg_type == "test:complete" then
                    -- Try to update status for single test scenarios
                    if count_table_elements(results.test_results) == 1 then
                        for exec_id, test_result in pairs(results.test_results) do
                            if msg_data.status == "passed" then
                                test_result.status = "passed"
                                results.tests_passed = math.min(results.tests_total, results.tests_passed + 1)
                                results.tests_failed = math.max(0, results.tests_failed - 1)
                            else
                                test_result.status = "failed"
                            end

                            -- Add suite details gathered from individual test cases - FOR ALL TESTS
                            local suites_array = {}
                            for suite_name, suite_data in pairs(suite_test_cases) do
                                -- Convert tests map to array
                                local tests_array = {}
                                for test_name, test_data in pairs(suite_data.tests) do
                                    table.insert(tests_array, test_data)
                                end

                                -- Clean up the internal tracking field
                                for i, test in ipairs(tests_array) do
                                    test.counted = nil
                                end

                                suite_data.tests = tests_array
                                table.insert(suites_array, suite_data)
                            end

                            test_result.suites = suites_array
                        end
                    end

                    -- Always signal test completion
                    test_done_ch:send(msg)
                end
            end
        end

        wait_ch:send(true)
    end)

    -- Process each test
    for _, test_info in ipairs(tests) do
        local test_id = test_info.id
        local test_name = test_info.meta.name or registry.parse_id(test_id).name

        print("DEBUG: Running test: " .. test_id)

        -- Prepare result object for this test
        local test_result = {
            id = test_id,
            name = test_name,
            group = test_info.meta.group or "Ungrouped",
            status = "pending",
            suites = {},
            start_time = time.now():unix()
        }

        -- Execute the test
        -- Use process.pid() to get current process ID
        local execution_id = process.pid() .. ":" .. test_id
        execution_options.ref_id = execution_id

        -- Store mapping from test_id to execution_id
        test_id_map[test_id] = execution_id

        -- Add test result to tracking
        results.test_results[execution_id] = test_result

        -- Execute test function
        local cmd, exec_err = executor:async(test_id, execution_options)
        if exec_err then
            test_result.status = "error"
            test_result.error = "Failed to execute test: " .. exec_err
            test_result.end_time = time.now():unix()
            test_result.duration = test_result.end_time - test_result.start_time
            results.tests_failed = results.tests_failed + 1
            print("DEBUG: Error executing test " .. test_id .. ": " .. exec_err)
        else
            -- Set timeout for test completion
            local timeout_duration = "5m"
            if params.timeout then
                timeout_duration = params.timeout
            end

            -- Wait for test to complete or timeout
            local complete_channel = cmd:response()
            local timeout_channel = time.after(timeout_duration)

            print("DEBUG: Waiting for test " .. test_id .. " to complete...")
            local result = channel.select {
                complete_channel:case_receive(),
                timeout_channel:case_receive()
            }

            if result.channel == complete_channel then
                -- Test completed within timeout
                local test_data, data_err = cmd:result()
                test_result.end_time = time.now():unix()
                test_result.duration = test_result.end_time - test_result.start_time
                print("DEBUG: Test " .. test_id .. " completed in " .. (test_result.duration or 0) .. "s")

                if data_err then
                    test_result.status = "error"
                    test_result.error = "Test execution error: " .. data_err
                    results.tests_failed = results.tests_failed + 1
                    print("DEBUG: Test " .. test_id .. " failed with error: " .. data_err)
                else
                    -- Wait for test:complete message to ensure all data is processed
                    print("DEBUG: Waiting for test:complete message for " .. test_id)
                    local completion_msg = wait_for_completion(test_done_ch, "2s")  -- Increased timeout to ensure we receive all messages

                    if completion_msg then
                        print("DEBUG: Received completion message for test: " .. (completion_msg.data and completion_msg.data.status or "unknown status"))
                    else
                        print("DEBUG: No explicit completion message received, continuing")
                    end

                    -- Check test_data.status first if available
                    if test_data and test_data.status then
                        if test_data.status == "passed" then
                            test_result.status = "passed"
                            results.tests_passed = results.tests_passed + 1
                            print("DEBUG: Test " .. test_id .. " passed (data status)")
                        else
                            test_result.status = "failed"
                            results.tests_failed = results.tests_failed + 1
                            print("DEBUG: Test " .. test_id .. " failed (data status)")
                        end
                    -- If no status in test_data but we received a completion message, check that
                    elseif completion_msg and completion_msg.data and completion_msg.data.status then
                        if completion_msg.data.status == "passed" then
                            test_result.status = "passed"
                            results.tests_passed = results.tests_passed + 1
                            print("DEBUG: Test " .. test_id .. " passed (completion message)")
                        else
                            test_result.status = "failed"
                            results.tests_failed = results.tests_failed + 1
                            print("DEBUG: Test " .. test_id .. " failed (completion message)")
                        end
                    -- Default to passed if the test completed without errors and no explicit status
                    else
                        test_result.status = "passed"
                        results.tests_passed = results.tests_passed + 1
                        print("DEBUG: Test " .. test_id .. " implicitly passed (no status in data)")
                    end

                    -- Add test data to result
                    test_result.data = test_data
                end
            else
                -- Test timed out
                test_result.status = "timeout"
                test_result.error = "Test execution timed out after " .. timeout_duration
                test_result.end_time = time.now():unix()
                test_result.duration = test_result.end_time - test_result.start_time
                results.tests_failed = results.tests_failed + 1
                print("DEBUG: Test " .. test_id .. " timed out after " .. timeout_duration)

                -- Clean up any hanging test
                cmd:cancel()
            end
        end

        results.tests_completed = results.tests_completed + 1
    end

    -- Signal message processor to finish and wait for completion
    print("DEBUG: All tests completed, shutting down message processor...")
    done_ch:close()

    -- Wait longer for message processing to complete to ensure we get all suite details
    if not wait_for_completion(wait_ch, "2s") then
        -- Log if we couldn't properly wait for message processing
        print("DEBUG: Could not wait for message processing to complete")
        results.warning = "Could not wait for message processing to complete"
    else
        print("DEBUG: Message processor completed")
    end

    -- Convert test_results from map to array
    local test_results_array = {}
    for _, result in pairs(results.test_results) do
        table.insert(test_results_array, result)
    end

    -- Sort by execution duration (fastest first)
    table.sort(test_results_array, function(a, b)
        return (a.duration or 0) < (b.duration or 0)
    end)

    -- Update results with array version
    results.test_results = test_results_array

    -- Add overall status
    if results.tests_failed > 0 then
        results.status = "failed"
    else
        results.status = "passed"
    end

    print("DEBUG: Test run complete: " .. results.tests_passed .. " passed, " .. results.tests_failed .. " failed")
    print("DEBUG: Number of suites in result: " .. (results.test_results[1] and #results.test_results[1].suites or 0))

    return results
end

return {
    handler = handler
}