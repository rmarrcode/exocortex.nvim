-- Adapters for headless coding-agent CLIs. Each adapter builds an argv for a
-- prompt and extracts the final response text from captured stdout. Extra
-- adapters (or overrides) can be merged in via require("exocortex").setup().

local M = {}

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
        local err = vim.trim(result.stderr ~= "" and result.stderr or (result.stdout or ""))
        on_done(nil, string.format("%s exited with %d: %s", name, result.code, err:sub(1, 500)))
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
