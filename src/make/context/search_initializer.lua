-- Imports
local json = require("json")
local ctx = require("ctx")
local uuid = require("uuid")
local registry = require("registry")
local funcs = require("funcs")
local find_relevant = require("find_relevant")

-- Constants
local CONSTANTS = {
    DEFAULT_SEARCH_QUERY = "General context search for arena task",
    AGENT_CLASS = "context_search",
    DOCS_LIMIT = 50,
    CONTENT_TYPE = "text/plain",
    DISCRIMINATOR = "private",
    MODULE_SPEC_TYPE = "module.spec"
}

-- Implementation
local function execute(input_data, tool_session_context)
    local current_node_id = ctx.get("node_id")
    local dataflow_id = ctx.get("dataflow_id")

    -- Extract and prepare search query and agent selection
    local search_query = ""
    local explicit_agent_id = nil
    local provided_context_uuids = nil

    if type(input_data) == "string" then
        search_query = input_data
    elseif type(input_data) == "table" then
        search_query = input_data.query or input_data.content or input_data.task or json.encode(input_data)
        explicit_agent_id = input_data.agent_id
        provided_context_uuids = input_data.context_uuids
    end

    -- Ensure meaningful search query for agent selection
    if not search_query or search_query == "" then
        search_query = CONSTANTS.DEFAULT_SEARCH_QUERY
    end

    -- Select appropriate context search agent
    local selected_agent_id = explicit_agent_id
    local agent_selection_error = nil

    -- Only run auto-selection if no explicit agent provided
    if not selected_agent_id then
        local selector_result, selector_err = funcs.new():call("wippy.agent.gen1:agent_selector", {
            user_prompt = search_query,
            class_name = CONSTANTS.AGENT_CLASS
        })

        if selector_err then
            agent_selection_error = selector_err
        elseif selector_result and selector_result.success and selector_result.agent then
            selected_agent_id = selector_result.agent
        else
            agent_selection_error = "Agent selector returned unsuccessful result"
        end
    end

    -- Load documentation index
    local entries, err = registry.find({ ["meta.type"] = CONSTANTS.MODULE_SPEC_TYPE })
    if err then
        return {
            input = input_data,
            error = "Failed to load documentation index: " .. err,
            _control = { commands = {} }
        }
    end

    local commands = {}
    local docs_loaded = 0
    local doc_index = "Available Documentation Index:\n"

    -- Build comprehensive documentation index
    for _, entry in ipairs(entries) do
        if entry.id then
            doc_index = doc_index .. entry.id
            if entry.meta and entry.meta.comment then
                doc_index = doc_index .. " - " .. entry.meta.comment
            end
            doc_index = doc_index .. "\n"
            docs_loaded = docs_loaded + 1
        end
    end

    -- Store documentation index as context
    table.insert(commands, {
        type = "CREATE_DATA",
        payload = {
            data_id = uuid.v7(),
            data_type = "context.data",
            content = doc_index,
            content_type = CONSTANTS.CONTENT_TYPE,
            discriminator = CONSTANTS.DISCRIMINATOR,
            key = "documentation_index",
            node_id = current_node_id,
            metadata = {
                comment = "Complete documentation index with " .. docs_loaded .. " modules",
                context_type = "documentation_index",
                docs_count = docs_loaded,
                source = "search_initializer"
            }
        }
    })

    -- Load provided context UUIDs as references if available
    local referenced_context_count = 0
    if provided_context_uuids and type(provided_context_uuids) == "table" and #provided_context_uuids > 0 then
        -- Import consts for proper reference handling
        local consts = require("consts")

        for _, context_uuid in ipairs(provided_context_uuids) do
            referenced_context_count = referenced_context_count + 1

            -- Create proper context reference using the same pattern as state.lua with_context
            table.insert(commands, {
                type = "CREATE_DATA",
                payload = {
                    data_id = uuid.v7(),
                    data_type = consts.DATA_TYPE.CONTEXT_DATA,
                    content = "",  -- Empty content for reference
                    content_type = consts.CONTENT_TYPE.REFERENCE,
                    discriminator = CONSTANTS.DISCRIMINATOR,
                    key = context_uuid,  -- Key should be the referenced data_id
                    node_id = current_node_id,
                    metadata = {
                        comment = "Reference to provided context UUID: " .. context_uuid,
                        context_type = "referenced_context",
                        references_data_id = context_uuid,
                        is_reference = true,
                        source = "search_initializer",
                        creator_node_id = current_node_id
                    }
                }
            })
        end
    end

    -- Generate pre-relevant entries to guide search
    if search_query and search_query ~= "" then
        local relevant_result = find_relevant.handler({
            query = search_query,
            limit = CONSTANTS.DOCS_LIMIT
        })

        if relevant_result.success and relevant_result.result then
            local relevant_index = "Pre-Relevant Registry Entries:\n"
            local entry_objects = relevant_result.result

            for _, entry_info in ipairs(entry_objects) do
                -- entry_info is now {id = "...", comment = "..."}
                local entry_id = entry_info.id
                local entry_comment = entry_info.comment

                relevant_index = relevant_index .. entry_id
                if entry_comment and entry_comment ~= "" then
                    relevant_index = relevant_index .. " - " .. entry_comment
                end
                relevant_index = relevant_index .. "\n"
            end

            -- Store pre-relevant entries context
            table.insert(commands, {
                type = "CREATE_DATA",
                payload = {
                    data_id = uuid.v7(),
                    data_type = "context.data",
                    content = relevant_index,
                    content_type = CONSTANTS.CONTENT_TYPE,
                    discriminator = CONSTANTS.DISCRIMINATOR,
                    key = "pre_relevant_entries",
                    node_id = current_node_id,
                    metadata = {
                        comment = "Pre-relevant registry entries for: " .. search_query:sub(1, 50),
                        context_type = "pre_relevant_entries",
                        entries_count = #relevant_result.result,
                        source = "search_initializer"
                    }
                }
            })
        end
    end

    -- Prepare control directives
    local control_directives = { commands = commands }

    -- Configure selected agent if available
    if selected_agent_id then
        control_directives.config = { agent = selected_agent_id }
    end

    return {
        input = input_data,
        initialization_complete = true,
        documentation_index_loaded = docs_loaded,
        referenced_context_loaded = referenced_context_count,
        search_context_prepared = true,
        agent_selection = {
            query_used = search_query,
            selected_agent = selected_agent_id,
            selection_error = agent_selection_error,
            explicit_agent_provided = explicit_agent_id ~= nil
        },
        provided_context_processing = {
            uuids_received = provided_context_uuids and #provided_context_uuids or 0,
            references_created = referenced_context_count
        },
        _control = control_directives
    }
end

return execute