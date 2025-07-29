local registry = require("registry")
local json     = require("json")  -- For potential debugging
local governance = require("governance_client")

-- Deep copy helper to avoid mutating original tables
local function deep_copy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deep_copy(v)
    end
    return copy
end

local function handler(params)
    -- 1. Validate required top‑level params
    if type(params.namespace) ~= "string" or params.namespace == "" then
        return { success = false, error = "Missing or invalid 'namespace' (string)" }
    end
    if type(params.name) ~= "string" or params.name == "" then
        return { success = false, error = "Missing or invalid 'name' (string)" }
    end
    if type(params.title) ~= "string" or params.title == "" then
        return { success = false, error = "Missing or invalid 'title' (string)" }
    end

    -- 2. Normalize 'fields': accept either numeric‑indexed list or keyed table
    if type(params.fields) ~= "table" then
        return { success = false, error = "Missing or invalid 'fields' (table expected)" }
    end

    local fields = {}
    local is_array = false
    for k,_ in pairs(params.fields) do
        if type(k) == "number" then
            is_array = true
            break
        end
    end

    if is_array then
        -- Convert list to keyed table by each entry's field_name
        for idx, fc in ipairs(params.fields) do
            if type(fc) ~= "table" then
                return { success = false, error = ("Field entry #%d is not a table"):format(idx) }
            end
            if type(fc.field_name) ~= "string" or fc.field_name == "" then
                return { success = false, error = ("Entry #%d missing 'field_name'"):format(idx) }
            end
            local key = fc.field_name
            fields[key] = deep_copy(fc)
            -- Remove the redundant field_name inside config if desired:
            fields[key].field_name = nil
        end
    else
        -- Already a keyed table
        fields = deep_copy(params.fields)
    end

    -- 3. Validate each field config
    for fname, cfg in pairs(fields) do
        if type(cfg) ~= "table"
           or type(cfg.description) ~= "string"
           or type(cfg.type) ~= "string" then
            return {
                success = false,
                error = ("Invalid config for field '%s': requires 'description' (string) and 'type' (string)."):format(fname)
            }
        end

        -- Enforce enum_values for enums
        if cfg.type == "enum" then
            if type(cfg.enum_values) ~= "table" then
                return {
                    success = false,
                    error = ("Field '%s' is type 'enum' but missing or invalid 'enum_values' array."):format(fname)
                }
            end
        end

        -- Enforce item_type for arrays, and nested enum_values if needed
        if cfg.type == "array" then
            if type(cfg.item_type) ~= "string" or cfg.item_type == "" then
                return {
                    success = false,
                    error = ("Field '%s' is type 'array' but missing or invalid 'item_type'."):format(fname)
                }
            end
            if cfg.item_type == "enum" then
                if type(cfg.enum_values) ~= "table" then
                    return {
                        success = false,
                        error = ("Array field '%s' of 'enum' items missing 'enum_values'."):format(fname)
                    }
                end
            end
        end
    end

    -- 4. Validate optional 'scouting' and 'extracting' configs
    if params.scouting then
        if type(params.scouting.model) ~= "string" or params.scouting.model == "" then
            return { success = false, error = "Scouting section requires 'model' (string)" }
        end
    end
    if params.extracting then
        if type(params.extracting.model) ~= "string" or params.extracting.model == "" then
            return { success = false, error = "Extracting section requires 'model' (string)" }
        end
    end

    local entry_id = params.namespace .. ":" .. params.name

    -- 5. Ensure entry does not already exist
    local snap, err = registry.snapshot()
    if not snap then
        return { success = false, error = "Failed to fetch registry snapshot: " .. tostring(err) }
    end
    if snap:get(entry_id) then
        return { success = false, error = "Extraction group already exists: " .. entry_id }
    end

    -- 6. Build the new entry data
    local entry_data = {
        fields     = fields,
        prefetch   = params.prefetch or {},
        scouting   = params.scouting or {},
        extracting = params.extracting or {},
        options    = params.options or {}
    }

    -- Apply defaults
    if params.extracting and entry_data.extracting.structured_output == nil then
        entry_data.extracting.structured_output = true
    end
    if params.options and entry_data.options.shared_context == nil then
        entry_data.options.shared_context = true
    end

    local new_entry = {
        id   = { ns = params.namespace, name = params.name },
        kind = "registry.entry",
        meta = {
            type    = "docscout.extraction_group",
            name    = params.name,
            title   = params.title,
            comment = params.comment
                       or ("DocScout Extraction Group: " .. params.title),
            tags    = params.tags or {}
        },
        data = entry_data
    }

    -- 7. Apply changes
    local changes = snap:changes()
    changes:create(new_entry)

    -- Use governance client instead of direct apply
    local result, err_apply = governance.request_changes(changes)
    if not result then
        return { success = false, error = "Failed to apply registry changes: " .. tostring(err_apply) }
    end

    -- 8. Fetch and return the created entry
    local final_snap, err_final = registry.snapshot(result.version)
    if not final_snap then
        return {
            success = true,
            message = "Entry created; failed to fetch final state.",
            entry_id = entry_id,
            version = result.version,
            warning = "Could not fetch entry: " .. tostring(err_final)
        }
    end

    local created = final_snap:get(entry_id) -- todo we really can just use result changeset info
    if not created then
        return {
            success = true,
            message = "Entry created; but missing on fetch.",
            entry_id = entry_id,
            version = result.version,
            warning = "Entry not found after creation."
        }
    end

    return {
        success = true,
        message = "Extraction group created successfully.",
        entry   = {
            id   = created.id,
            kind = created.kind,
            meta = created.meta,
            data = created.data
        },
        version = result.version,
        details = result.details
    }
end

return { handler = handler }