local M = {}

local CACHE = {
  path = nil,
  mtime = nil,
  snapshot = nil,
}

local function latest_session_file()
  local root = vim.fn.expand("~/.codex/sessions")
  local paths = vim.fn.globpath(root, "**/*.jsonl", true, true)
  local best_path
  local best_stat

  for _, path in ipairs(paths) do
    local stat = vim.uv.fs_stat(path)
    if stat then
      local better = false
      if not best_stat then
        better = true
      elseif stat.mtime.sec ~= best_stat.mtime.sec then
        better = stat.mtime.sec > best_stat.mtime.sec
      else
        better = (stat.mtime.nsec or 0) > (best_stat.mtime.nsec or 0)
      end

      if better then
        best_path = path
        best_stat = stat
      end
    end
  end

  return best_path, best_stat
end

local function decode_line(line)
  local ok, event = pcall(vim.json.decode, line)
  if ok and type(event) == "table" then
    return event
  end
end

local function parse_session_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local snapshot = {}

  for line in file:lines() do
    local event = decode_line(line)
    local payload = event and (event.payload or event) or nil

    local is_token_count = type(payload) == "table" and (payload.type == "token_count" or (event and event.type == "token_count"))
    if is_token_count then
      snapshot.timestamp = event.timestamp or snapshot.timestamp
      snapshot.rate_limits = payload.rate_limits or snapshot.rate_limits
      snapshot.info = payload.info or snapshot.info
    end
  end

  file:close()

  if snapshot.rate_limits or snapshot.info then
    return snapshot
  end
end

local function same_stat(a, b)
  if not (a and b) then
    return false
  end

  return a.sec == b.sec and (a.nsec or 0) == (b.nsec or 0)
end

local function format_tokens(n)
  if type(n) ~= "number" then
    return nil
  end

  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  end

  if n >= 1000 then
    return string.format("%.1fk", n / 1000)
  end

  return tostring(n)
end

local function format_duration(seconds)
  if type(seconds) ~= "number" then
    return nil
  end

  seconds = math.max(0, math.floor(seconds + 0.5))

  if seconds < 60 then
    return string.format("%ds", seconds)
  end

  local minutes = math.floor(seconds / 60)
  local rem = seconds % 60

  if minutes < 60 then
    if rem == 0 then
      return string.format("%dm", minutes)
    end
    return string.format("%dm%02ds", minutes, rem)
  end

  local hours = math.floor(minutes / 60)
  minutes = minutes % 60

  if minutes == 0 then
    return string.format("%dh", hours)
  end

  return string.format("%dh%02dm", hours, minutes)
end

local function snapshot_rate(limit)
  if type(limit) ~= "table" then
    return nil
  end

  local used = type(limit.used_percent) == "number" and limit.used_percent or nil
  local resets_at = type(limit.resets_at) == "number" and limit.resets_at or nil

  if not used and not resets_at then
    return nil
  end

  return {
    used_percent = used,
    resets_at = resets_at,
    window_minutes = type(limit.window_minutes) == "number" and limit.window_minutes or nil,
  }
end

local function build_snapshot(raw)
  if not raw then
    return nil
  end

  local info = raw.info or {}
  local total = info.total_token_usage or {}
  local last = info.last_token_usage or {}
  local rates = raw.rate_limits or {}

  local snapshot = {
    total_tokens = type(total.total_tokens) == "number" and total.total_tokens or nil,
    last_tokens = type(last.total_tokens) == "number" and last.total_tokens or nil,
    context_window = type(info.model_context_window) == "number" and info.model_context_window or nil,
    primary = snapshot_rate(rates.primary),
    secondary = snapshot_rate(rates.secondary),
    credits = rates.credits,
    timestamp = raw.timestamp,
  }

  return snapshot
end

function M.snapshot()
  local path, stat = latest_session_file()
  if not path or not stat then
    return nil
  end

  if CACHE.path == path and same_stat(CACHE.mtime, stat.mtime) then
    return CACHE.snapshot
  end

  local raw = parse_session_file(path)
  local snapshot = build_snapshot(raw)

  CACHE.path = path
  CACHE.mtime = stat.mtime
  CACHE.snapshot = snapshot

  return snapshot
end

function M.format(snapshot)
  snapshot = snapshot or M.snapshot()

  if not snapshot then
    return {
      "usage ?",
      "reset ?",
    }
  end

  local primary = snapshot.primary or {}
  local secondary = snapshot.secondary or {}
  local used_parts = {}

  if primary.used_percent then
    used_parts[#used_parts + 1] = string.format("p%d%%", math.floor(primary.used_percent + 0.5))
  end
  if secondary.used_percent then
    used_parts[#used_parts + 1] = string.format("s%d%%", math.floor(secondary.used_percent + 0.5))
  end

  local last_tokens = format_tokens(snapshot.last_tokens)
  local total_tokens = format_tokens(snapshot.total_tokens)
  local usage_line

  if #used_parts > 0 then
    usage_line = table.concat({ "usage", table.concat(used_parts, " ") }, " ")
    if last_tokens or total_tokens then
      usage_line = usage_line .. " last " .. (last_tokens or total_tokens or "?")
    end
  else
    usage_line = "usage ?"
    if last_tokens then
      usage_line = usage_line .. " last " .. last_tokens
    end
  end

  local reset_line = "reset ?"
  local reset_at = primary.resets_at or secondary.resets_at
  if type(reset_at) == "number" then
    local delta = reset_at - os.time()
    local formatted = format_duration(delta)
    if formatted then
      reset_line = "reset " .. formatted
    end
  end

  return { usage_line, reset_line }
end

return M
