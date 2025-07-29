local registry = require("registry")
local json     = require("json")
local governance = require("governance_client")

-- Simple debug printer
local function debug(label, tbl)
  -- label: string, tbl: any
  print(string.format("[DEBUG] %s: %s", label, json.encode(tbl)))
end

-- Deep‑copy utility
local function deep_copy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k,v in pairs(orig) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- Deep‑merge source → target (only merges keys in source)
local function deep_merge(target, source)
  for k,v in pairs(source) do
    if type(v) == "table" and type(target[k]) == "table" then
      deep_merge(target[k], v)
    elseif v ~= nil then
      target[k] = v
    end
  end
end

-- Validate a single field config
local function validate_field_cfg(name, cfg)
  assert(type(cfg.description) == "string" and #cfg.description > 0,
         ("Field '%s' must have a non-empty description"):format(name))
  assert(type(cfg.type) == "string" and #cfg.type > 0,
         ("Field '%s' must have a non-empty type"):format(name))

  if cfg.type == "enum" then
    assert(type(cfg.enum_values) == "table" and #cfg.enum_values > 0,
           ("Field '%s' needs non-empty enum_values"):format(name))
  end

  if cfg.type == "array" then
    cfg.item_type = cfg.item_type or "string"
  end
end

-- Main handler
local function handler(params)
  debug("input_params", params)

  -- 1) Validate inputs
  if type(params.id) ~= "string" then
    return { success=false, error="Missing or invalid 'id'" }
  end
  if type(params.field_updates) ~= "table" or #params.field_updates == 0 then
    return { success=false, error="Missing or invalid 'field_updates'" }
  end

  -- 2) Load registry snapshot + entry
  local snap, err = registry.snapshot()
  if not snap then
    return { success=false, error="Registry snapshot failed: "..tostring(err) }
  end
  local entry = snap:get(params.id)
  if not entry then
    return { success=false, error="Extraction group not found: "..params.id }
  end
  debug("original_entry_meta", { namespace = entry.meta.namespace, name = entry.meta.name })

  -- 3) Prepare copy for updates
  local updatedData = deep_copy(entry.data or {}).fields or {}
  debug("before_updates", updatedData)

  local changed = {}

  -- 4) Apply each update
  for _, upd in ipairs(params.field_updates) do
    local fname = upd.field_name
    if type(fname) ~= "string" then
      return { success=false, error="Each update must include field_name" }
    end

    local fieldCfg = updatedData[fname]
    if not fieldCfg then
      return { success=false, error=("Field '%s' not found"):format(fname) }
    end

    debug("merge_before_"..fname, fieldCfg)
    -- merge and validate
    local patch = deep_copy(upd)
    patch.field_name = nil
    deep_merge(fieldCfg, patch)
    validate_field_cfg(fname, fieldCfg)
    debug("merge_after_"..fname, fieldCfg)

    table.insert(changed, fname)
  end

  -- 5) Nothing to change?
  if #changed == 0 then
    print("[INFO] No changes detected; skipping apply.")
    return { success=true, message="No fields updated" }
  end

  -- 6) Commit changes
  local changeset = snap:changes()
  changeset:update({
    id   = entry.id,
    kind = entry.kind,
    meta = entry.meta,
    data = { fields = updatedData }
  })
 
  debug("final_payload", updatedData)

  -- Use governance client instead of direct apply
  local result, err2 = governance.request_changes(changeset)
  if not result then
    return { success=false, error="Apply failed: "..tostring(err2) }
  end

  return {
    success = true,
    message = "Fields updated: ["..table.concat(changed, ", ").."]",
    version = result.version,
    details = result.details
  }
end

return { handler = handler }