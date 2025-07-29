local registry = require("registry")
local json = require("json")
local governance = require("governance_client")

-- Main handler
local function handler(params)
    -- 1) Validate inputs
    if type(params.id) ~= "string" then
        return { success = false, error = "Missing or invalid 'id'" }
    end

    -- At least one metadata field must be provided
    if not params.title and not params.comment and not params.tags then
        return { success = false, error = "At least one of 'title', 'comment', or 'tags' must be provided" }
    end

    -- 2) Load registry snapshot + entry
    local snap, err = registry.snapshot()
    if not snap then
        return { success = false, error = "Registry snapshot failed: " .. tostring(err) }
    end
    local entry = snap:get(params.id)
    if not entry then
        return { success = false, error = "Extraction group not found: " .. params.id }
    end

    -- Verify it's an extraction group
    if not entry.meta or entry.meta.type ~= "docscout.extraction_group" then
        return { success = false, error = "Entry is not a DocScout extraction group: " .. params.id }
    end

    -- 3) Prepare updated metadata
    local updatedMeta = {
        type = "docscout.extraction_group", -- Ensure type is preserved
        name = entry.meta.name,         -- Preserve name
    }

    -- Copy existing values first
    if entry.meta.title then updatedMeta.title = entry.meta.title end
    if entry.meta.comment then updatedMeta.comment = entry.meta.comment end
    if entry.meta.tags then
        -- Convert existing tags from object format to array if needed
        if type(entry.meta.tags) == "table" and next(entry.meta.tags) ~= nil then
            if #entry.meta.tags > 0 then
                -- Already an array, use directly
                updatedMeta.tags = entry.meta.tags
            else
                -- Convert from object format to array
                local tagsArray = {}
                for tag, _ in pairs(entry.meta.tags) do
                    table.insert(tagsArray, tag)
                end
                updatedMeta.tags = tagsArray
            end
        end
    end

    -- Apply updates
    if params.title then updatedMeta.title = params.title end
    if params.comment then updatedMeta.comment = params.comment end
    if params.tags then
        -- Ensure tags are stored as array
        if type(params.tags) == "table" then
            if #params.tags > 0 then
                -- Already an array, use directly
                updatedMeta.tags = params.tags
            else
                -- Convert from object format to array if needed
                local tagsArray = {}
                for tag, _ in pairs(params.tags) do
                    table.insert(tagsArray, tag)
                end
                updatedMeta.tags = tagsArray
            end
        else
            return { success = false, error = "Tags must be provided as an array of strings" }
        end
    end

    -- 4) Commit changes
    local changeset = snap:changes()
    changeset:update({
        id = entry.id,
        kind = entry.kind,
        meta = updatedMeta,
        data = entry.data
    })

    -- Use governance client instead of direct apply
    local result, err2 = governance.request_changes(changeset)
    if not result then
        return { success = false, error = "Apply failed: " .. tostring(err2) }
    end

    -- 5) Build response with changes made
    local changes = {}
    if params.title then table.insert(changes, "title") end
    if params.comment then table.insert(changes, "comment") end
    if params.tags then table.insert(changes, "tags") end

    return {
        success = true,
        message = "Metadata updated: [" .. table.concat(changes, ", ") .. "]",
        id = params.id,
        meta = updatedMeta,
        version = result.version,
        details = result.details
    }
end

return { handler = handler }
