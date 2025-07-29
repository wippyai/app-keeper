-- Imports
local json = require("json")
local uuid = require("uuid")
local ctx = require("ctx")
local registry = require("registry")
local yaml = require("yaml")
local data_reader = require("data_reader")
local consts = require("consts")

-- Constants
local CONSTANTS = {
    DEFAULT_TASK = "Context gathering",
    CONTENT_TYPE = "text/plain",
    YAML_INDENT = 2,
    ERROR_MESSAGES = {
        INVALID_FORMAT = "Invalid output format from context search",
        FAILED_WITH_ERROR = "Context search failed with error"
    }
}

-- Helper Functions

-- Format registry entry content for context storage.
-- Output structure:
--   <meta>
--   registry_id: <full id>
--   <YAML of entry.meta>
--   </meta>
--   <data>
--   <YAML of entry.data without the `source` field>
--   </data>
--   <source> ... </source>   -- only when entry.data.source exists & non-empty
local function format_registry_entry(entry)
    local parts = {}

    -- META SECTION
    local meta_yaml
    do
        local meta_copy = {}
        for k, v in pairs(entry.meta or {}) do
            meta_copy[k] = v
        end

        local ok, enc = pcall(yaml.encode, meta_copy, {
            indent = CONSTANTS.YAML_INDENT,
            emit_defaults = false
        })
        meta_yaml = ok and enc or ("meta_encode_error: " .. tostring(enc))
        meta_yaml = "registry_id: " .. entry.id .. "\n" .. meta_yaml
    end

    table.insert(parts, "<meta>")
    table.insert(parts, meta_yaml)
    table.insert(parts, "</meta>")

    -- DATA SECTION
    local data_yaml
    do
        local data_tbl = {}
        if type(entry.data) == "table" then
            for k, v in pairs(entry.data) do
                if k ~= "source" then
                    data_tbl[k] = v
                end
            end
        end

        local ok, enc = pcall(yaml.encode, data_tbl, {
            indent = CONSTANTS.YAML_INDENT,
            emit_defaults = false
        })
        data_yaml = ok and enc or ("data_encode_error: " .. tostring(enc))
    end

    table.insert(parts, "<data>")
    table.insert(parts, data_yaml)
    table.insert(parts, "</data>")

    -- SOURCE SECTION
    local src = entry.data and entry.data.source
    if type(src) == "string" and #src > 0 then
        table.insert(parts, "<source>")
        table.insert(parts, src)
        table.insert(parts, "</source>")
    end

    return table.concat(parts, "\n")
end

-- Sanitize entry_id for use as storage key
local function sanitize_storage_key(entry_id)
    -- Replace colons and problematic characters with underscores
    -- Keep alphanumeric, hyphens, and underscores
    return entry_id:gsub("[^%w_%-]", "_")
end

-- Check if context with the same registry_id already exists
local function context_already_exists(dataflow_id, target_node_id, registry_id, discriminator)
    local query = data_reader.with_dataflow(dataflow_id)
        :with_data_types(consts.DATA_TYPE.CONTEXT_DATA)
        :with_data_discriminators(discriminator)

    if target_node_id then
        query = query:with_nodes(target_node_id)
    end

    local existing_context = query:all()

    for _, ctx_item in ipairs(existing_context) do
        if ctx_item.metadata and ctx_item.metadata.registry_id == registry_id then
            return true
        end
    end

    return false
end

-- Main Implementation
local function execute(final_output)
    local current_node_id = ctx.get("node_id")
    local dataflow_id = ctx.get("dataflow_id")

    -- Always write to own node as private context
    local target_node_id = current_node_id  -- Always own node
    local discriminator = "private"          -- Always private
    local task_description = ctx.get("task_description") or CONSTANTS.DEFAULT_TASK

    -- Handle error cases
    if final_output.error then
        return {
            success = false,
            error = final_output.error
        }
    end

    local res_tbl = final_output.result
    if type(res_tbl) ~= "table" then
        return {
            success = false,
            error = CONSTANTS.ERROR_MESSAGES.INVALID_FORMAT
        }
    end

    local commands = {}
    local final_summary_text = res_tbl.search_summary or res_tbl.context_summary or "Context gathering completed"
    local processed_entries = {}

    -- Process selected entries if available
    if res_tbl.success and type(res_tbl.selected_entries) == "table" then
        for _, spec in ipairs(res_tbl.selected_entries) do
            if spec.entry_id and spec.comment then
                -- Check for existing context to avoid duplicates
                if not context_already_exists(dataflow_id, target_node_id, spec.entry_id, discriminator) then
                    -- Fetch and process registry entry
                    local entry, err = registry.get(spec.entry_id)
                    if entry then
                        local content = format_registry_entry(entry)
                        local context_data_id = uuid.v7()
                        local sanitized_key = sanitize_storage_key(spec.entry_id)

                        -- Create storage command
                        table.insert(commands, {
                            type = "CREATE_DATA",
                            payload = {
                                data_id = context_data_id,
                                data_type = "context.data",
                                content = content,
                                content_type = CONSTANTS.CONTENT_TYPE,
                                discriminator = discriminator,
                                key = sanitized_key,
                                node_id = target_node_id,
                                metadata = {
                                    context_type = "registry_entry",
                                    registry_id = spec.entry_id,
                                    comment = spec.comment,
                                    created_by = "context_search_arena",
                                    task_description = task_description,
                                    source_arena_node = current_node_id,
                                    entry_kind = entry.kind,
                                    entry_namespace = entry.id:match("^([^:]+):") or "",
                                    finalized_by = "context_finalizer"
                                }
                            }
                        })

                        -- Add to processed entries list with context_uuid instead of entry_id
                        table.insert(processed_entries, {
                            context_uuid = context_data_id,
                            registry_id = spec.entry_id,
                            comment = spec.comment,
                            size = #content  -- Add size in characters
                        })
                    end
                end
            end
        end
    end

    return {
        success = res_tbl.success,
        search_summary = final_summary_text,
        selected_entries = processed_entries,  -- Now contains context_uuids instead of entry_ids
        _control = { commands = commands }
    }
end

return execute