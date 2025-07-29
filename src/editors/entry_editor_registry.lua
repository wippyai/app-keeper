local registry = require("registry")
local start_tokens = require("start_tokens")

local function find_editors_for_entry(entry)
    if not entry then
        return nil, "Entry is required"
    end

    -- Get the entry kind and meta.type
    local kind = entry.kind
    local meta_type = entry.meta and entry.meta.type or nil

    -- Find all editor configurations that match this entry type
    local editor_entries = nil
    local err = nil

    -- Try to find editors specific to this entry's kind and meta.type
    if meta_type then
        editor_entries, err = registry.find({
            [".kind"] = "registry.entry",
            ["meta.type"] = "entry.editors",
            ["meta.target_meta_type"] = meta_type
        })
    end

    -- If no specific editors found, try to find editors for just the kind
    if not editor_entries or #editor_entries == 0 then
        editor_entries, err = registry.find({
            [".kind"] = "registry.entry",
            ["meta.type"] = "entry.editors",
            ["meta.target_kind"] = kind
        })
    end

    -- If still no editors found, return nil
    if not editor_entries or #editor_entries == 0 then
        return nil, "No editor configurations found for entry type"
    end

    -- Sort editors by priority
    table.sort(editor_entries, function(a, b)
        local a_priority = a.meta and a.meta.priority or 0
        local b_priority = b.meta and b.meta.priority or 0
        return a_priority > b_priority
    end)

    -- Process actions to generate tokens for start_chat actions
    local processed_entries = {}
    for _, editor_entry in ipairs(editor_entries) do
        local processed_entry = {
            id = editor_entry.id,
            meta = editor_entry.meta or {},
            editors = editor_entry.data.editors or {},
            actions = {}
        }

        -- Process actions if present
        if editor_entry.data.actions then
            for _, action in ipairs(editor_entry.data.actions) do
                local processed_action = {
                    id = action.id,
                    title = action.title,
                    type = action.type,
                    icon = action.icon
                }

                -- Process special action types
                if action.type == "start_chat" then
                    -- Simply use the agent name directly
                    local agent_name = action.agent
                    local model = action.model or "gpt-4o"

                    -- Generate token for the agent
                    if agent_name then
                        local token_params = {
                            agent = agent_name,
                            model = model,
                            kind = action.kind or "default"
                        }

                        local token, token_err = start_tokens.pack(token_params)
                        if token then
                            processed_action.start_token = token
                        else
                            -- Log the error but continue without a token
                            print("Failed to generate start token: " .. (token_err or "unknown error"))
                        end
                    end
                elseif action.type == "url" then
                    -- Simply use the URL directly
                    processed_action.url = action.url
                elseif action.type == "custom_action" then
                    processed_action.action = action.action
                end

                table.insert(processed_entry.actions, processed_action)
            end
        end

        table.insert(processed_entries, processed_entry)
    end

    return processed_entries
end

return {
    find_editors_for_entry = find_editors_for_entry
}