-- Adapters for headless coding-agent CLIs. Each adapter builds an argv for a
-- prompt and extracts the final response text from captured stdout. Extra
-- adapters (or overrides) can be merged in via require("exocortex").setup().

local M = {}

local LIMIT_PATTERNS = {
  "usage limit",
  "rate limit",
  "quota",
  "credit balance is too low",
  "too many requests",
  "try again later",
}

local function collect_json_text(raw)
  local texts = {}

  for line in (raw or ""):gmatch("[^\n]+") do
    local ok, event = pcall(vim.json.decode, line)
    if ok and type(event) == "table" then
      if type(event.error) == "string" and vim.trim(event.error) ~= "" then
        texts[#texts + 1] = event.error
      end

      if type(event.message) == "string" and vim.trim(event.message) ~= "" then
        texts[#texts + 1] = event.message
      end

      if type(event.result) == "string" and vim.trim(event.result) ~= "" then
        texts[#texts + 1] = event.result
      end
    end
  end

  return texts
end

local function classify_limit_error(text)
  local lowered = (text or ""):lower()

  for _, pattern in ipairs(LIMIT_PATTERNS) do
    if lowered:find(pattern, 1, true) then
      return true
    end
  end

  return false
end

local function format_run_error(name, code, stdout, stderr)
  local parts = {}

  for _, text in ipairs(collect_json_text(stderr)) do
    parts[#parts + 1] = text
  end
  for _, text in ipairs(collect_json_text(stdout)) do
    parts[#parts + 1] = text
  end

  local fallback = vim.trim(stderr ~= "" and stderr or (stdout or ""))
  if fallback ~= "" then
    parts[#parts + 1] = fallback
  end

  local detail
  for _, text in ipairs(parts) do
    local trimmed = vim.trim(text)
    if trimmed ~= "" and not trimmed:match("\"subtype\"%s*:%s*\"init\"") then
      detail = trimmed
      break
    end
  end

  if not detail or detail == "" then
    detail = "the agent exited before producing a usable response"
  end

  detail = detail:gsub("%s+", " ")

  if classify_limit_error(detail) then
    return string.format(
      "%s hit a usage limit and stopped. Wait for the provider limit to reset or switch agents. %s",
      name,
      detail
    )
  end

  return string.format("%s exited with %d: %s", name, code, detail)
end

M.adapters = {
  claude = {
    exe = "claude",
    cmd = function(prompt)
      return {
        "claude",
        "-p", prompt,
        "--output-format", "stream-json",
        "--verbose",
        "--permission-mode", "bypassPermissions",
      }
    end,
    parse = function(stdout)
      local texts = {}

      for line in stdout:gmatch("[^\n]+") do
        local ok, event = pcall(vim.json.decode, line)

        if ok and type(event) == "table" then
          if event.type == "result" and type(event.result) == "string" then
            return event.result
          end

          if event.type == "assistant" and event.message and type(event.message.content) == "table" then
            for _, part in ipairs(event.message.content) do
              if part.type == "text" and part.text then
                table.insert(texts, part.text)
              end
            end
          end
        end
      end

      return table.concat(texts, "\n\n")
    end,
  },

  codex = {
    exe = "codex",
    cmd = function(prompt)
      return {
        "codex",
        "exec",
        "--json",
        "--sandbox",
        "workspace-write",
        prompt,
      }
    end,
    parse = function(stdout)
      local last

      for line in stdout:gmatch("[^\n]+") do
        local ok, event = pcall(vim.json.decode, line)

        if ok and type(event) == "table" then
          local item = event.item or event.msg or event

          if type(item) == "table" and item.text and item.type == "agent_message" then
            last = item.text
          end
        end
      end

      return last or vim.trim(stdout)
    end,
  },

  gemini = {
    exe = "gemini",
    cmd = function(prompt)
      return { "gemini", "--yolo", "-p", prompt }
    end,
    parse = function(stdout)
      return vim.trim(stdout)
    end,
  },
}

function M.available()
  local names = {}

  for name, adapter in pairs(M.adapters) do
    if vim.fn.executable(adapter.exe) == 1 then
      table.insert(names, name)
    end
  end

  table.sort(names)
  return names
end

function M.run(name, prompt, cwd, on_done)
  local adapter = M.adapters[name]

  if not adapter then
    on_done(nil, "unknown agent: " .. name)
    return
  end

  vim.system(adapter.cmd(prompt), { text = true, cwd = cwd }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err = format_run_error(name, result.code, result.stdout or "", result.stderr or "")
        on_done(nil, err:sub(1, 500))
        return
      end

      local response = adapter.parse(result.stdout or "")

      if response == "" then
        response = "(empty response)"
      end

      on_done(response)
    end)
  end)
end

return M
