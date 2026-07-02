local config_loader = require("exocortex.config_loader")
local keymaps = require("exocortex.keymaps")

local M = {}
M.model = nil

local MODELS = {
  { id = nil, label = "Default (recommended)  Let Copilot choose the best autocomplete model" },
  { id = "gpt-5.5", label = "gpt-5.5               Strongest general-purpose completion model" },
  { id = "gpt-5.4", label = "gpt-5.4               Balanced completion model" },
  { id = "gpt-5.4-mini", label = "gpt-5.4-mini          Fast, lower-latency completion model" },
}

local function current_model()
  if M.model ~= nil then
    return M.model
  end

  if vim.g.copilot_model ~= nil then
    return vim.g.copilot_model
  end

  local cfg = config_loader.load().exocortex or {}
  return cfg.copilot_model
end

local function set_model(model)
  M.model = model
  vim.g.copilot_model = model
end

local function first_key(lhses)
  if type(lhses) == "table" then
    return lhses[1] or ""
  end
  return lhses or ""
end

local function selected_label(model)
  if not model or model == "" then
    return "Default (recommended)"
  end

  for _, item in ipairs(MODELS) do
    if item.id == model then
      return item.label
    end
  end

  return model
end

local function render(buf)
  local model = current_model()
  local lines = {
    "Copilot settings",
    "",
    "Current model:",
    "  " .. selected_label(model),
    "",
    "This screen controls autocomplete-oriented Copilot behavior.",
    "Press <Tab> or <CR> to choose a model.",
    "Press <C-q>, q, or <Esc> to close.",
    "",
    "Available models:",
  }

  for i, item in ipairs(MODELS) do
    local marker = item.id == model and ">" or " "
    lines[#lines + 1] = string.format("  %s %d. %s", marker, i, item.label)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Shortcut: " .. first_key(config_loader.keys("editor").open_copilot) .. ""

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.open()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "exocortex://copilot")
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "exocortex-copilot"
  vim.bo[buf].modifiable = false

  local width = math.min(76, math.max(48, vim.o.columns - 12))
  local height = math.min(18, math.max(12, vim.o.lines - 8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " copilot ",
    title_pos = "center",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function apply(model)
    set_model(model)
    render(buf)
    vim.notify("copilot model set to " .. (model or "default"), vim.log.levels.INFO)
  end

  local function choose()
    vim.ui.select(MODELS, {
      prompt = "copilot model",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        apply(choice.id)
      end
    end)
  end

  local function map(lhs, fn)
    keymaps.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true })
  end

  map("<C-q>", close)
  map("q", close)
  map("<Esc>", close)
  map("<Tab>", choose)
  map("<CR>", choose)
  map("<S-Tab>", function()
    apply(nil)
  end)

  local cfg = config_loader.load().exocortex or {}
  if M.model == nil and cfg.copilot_model ~= nil then
    M.model = cfg.copilot_model
  end

  render(buf)
  return win
end

return M
