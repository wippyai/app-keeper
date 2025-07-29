local upload_repo = require("upload_repo")
local security = require("security")

local function execute(params)
    -- Get current user ID from security context
    local actor = security.actor()
    if not actor then
        return {
            success = false,
            error = "No authenticated user found"
        }
    end

    local user_id = actor:id()

    -- Set and validate inputs with reasonable defaults
    local status = params.status
    local type_id = params.type_id
    local limit = params.limit or 100  -- Default to 100 items
    local offset = params.offset or 0   -- Default to start at beginning

    -- Enforce reasonable limits
    if limit > 500 then limit = 500 end  -- Cap at 500 for performance
    if limit < 1 then limit = 100 end    -- Minimum of 1, default to 100 if invalid
    if offset < 0 then offset = 0 end    -- Prevent negative offsets

    -- Always filter by current user's ID unless they have specific access permissions
    local can_view_all = false
    local scope = security.scope()

    if scope then
        -- Check if user has permission to view all uploads
        can_view_all = security.can("view_all", "uploads")
    end

    -- Get total count of user's uploads (regardless of pagination)
    local total_count, count_err = upload_repo.count_by_user(user_id)
    if count_err then
        -- Non-fatal error, we can continue without the total count
        total_count = nil
    end

    -- Determine which listing function to use based on provided filters
    local uploads, err

    if status and can_view_all then
        uploads, err = upload_repo.list_by_status(status, limit, offset)
    elseif type_id and can_view_all then
        uploads, err = upload_repo.list_by_type(type_id, limit, offset)
    else
        -- Default to filtering by user_id (most secure option)
        uploads, err = upload_repo.list_by_user(user_id, limit, offset)
    end

    if err then
        return {
            success = false,
            error = "Failed to list uploads: " .. err
        }
    end

    -- Format uploads for output
    local formatted_uploads = {}
    for i, upload in ipairs(uploads) do
        table.insert(formatted_uploads, {
            uuid = upload.uuid,
            user_id = upload.user_id,
            size = upload.size,
            mime_type = upload.mime_type,
            status = upload.status,
            type_id = upload.type_id,
            created_at = upload.created_at,
            updated_at = upload.updated_at,
            filename = upload.metadata and upload.metadata.filename or nil
        })
    end

    return {
        success = true,
        uploads = formatted_uploads,
        count = #formatted_uploads,
        total_count = total_count,
        filtered_by_user = not can_view_all
    }
end

return { execute = execute }