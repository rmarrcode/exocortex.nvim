-- Node detail float with a grow-from-card transition. The float starts at the
-- card's screen rect and animates to a centered reading pane.

local config_loader = require("exocortex.config_loader")
local keymaps = require("exocortex.keymaps")
local state = require("exocortex.state")

local M = {}

local function first_key(lhses)
  if type(lhses) == "table" then
    return lhses[1] or ""
  end
  return lhses or ""
end

local function smoothstep(t)
  return t * t * (3 - 2 * t)
end

local MAX_CHANGED_FILES = 25

local function changed_files_preview(files)
  if not files or #files == 0 then
    return nil
  end

  local lines = {}
  local limit = math.min(#files, MAX_CHANGED_FILES)

  for i = 1, limit do
    local f = files[i]
    lines[#lines + 1] = string.format("%d. `%s` %s", i, f.status or "?", f.path or "?")
  end

  if #files > limit then
    lines[#lines + 1] = string.format("... and %d more files", #files - limit)
  end

  return lines
end

local function animate(win, from, to, duration_ms)
  local steps = 8
  local step = 0
  local timer = vim.uv.new_timer()

  timer:start(0, math.floor(duration_ms / steps), vim.schedule_wrap(function()
    step = step + 1
    local t = smoothstep(step / steps)

    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = math.floor(from.row + (to.row - from.row) * t + 0.5),
        col = math.floor(from.col + (to.col - from.col) * t + 0.5),
        width = math.max(8, math.floor(from.width + (to.width - from.width) * t + 0.5)),
        height = math.max(2, math.floor(from.height + (to.height - from.height) * t + 0.5)),
      })
    end

    if step >= steps then
      timer:stop()
      timer:close()
    end
  end))
end

function M.open(node, from_rect, root_dir)
  local lines = { "# " .. (node.prompt or ""):gsub("\n", " "), "" }

  table.insert(lines, string.format("_%s · %s · %s_", state.format_agent(node.agent, node.model), node.status, node.stat or ""))
  table.insert(lines, "")

  for _, line in ipairs(vim.split(node.response or "(no response yet)", "\n")) do
    table.insert(lines, line)
  end

  if node.files and #node.files > 0 then
    table.insert(lines, "")
    table.insert(lines, "## changed files")

    local preview = changed_files_preview(node.files)
    if preview then
      vim.list_extend(lines, preview)
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  local final = {
    width = math.min(100, vim.o.columns - 8),
    height = math.min(32, vim.o.lines - 8),
  }
  final.row = math.max(0, math.floor((vim.o.lines - final.height) / 2) - 1)
  final.col = math.floor((vim.o.columns - final.width) / 2)

  local start = from_rect or final

  local keys = config_loader.keys("node_view")
  local footer = node.snapshot
    and string.format("  %s read  %s review diffs  %s diffview  %s close  ", first_key(keys.read), first_key(keys.review_diffs), first_key(keys.diffview), first_key(keys.close))
    or string.format("  %s read  %s close  ", first_key(keys.read), first_key(keys.close))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = start.row,
    col = start.col,
    width = math.max(8, start.width),
    height = math.max(2, start.height),
    style = "minimal",
    border = "rounded",
    title = " node " .. (node.id or "?") .. " ",
    title_pos = "center",
    footer = footer,
    footer_pos = "right",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].number = true
  vim.wo[win].relativenumber = true
  vim.wo[win].numberwidth = 4

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function map(lhs, fn)
    keymaps.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true })
  end

  local function paste_register(direction)
    local was_modifiable = vim.bo[buf].modifiable
    local was_readonly = vim.bo[buf].readonly

    vim.bo[buf].modifiable = true
    vim.bo[buf].readonly = false
    pcall(vim.cmd, "normal! " .. direction)
    vim.bo[buf].modifiable = was_modifiable
    vim.bo[buf].readonly = was_readonly
  end

  map(keys.close, close)
  map(keys.return_to_code, function()
    close()
    require("exocortex.graph").return_to_code()
  end)
  map("p", function() paste_register("p") end)
  map("P", function() paste_register("P") end)

  local noop = function() end
  for _, lhs in ipairs({ "i", "I", "gi", "a", "A", "o", "O", "s", "S", "c", "C", "x", "X", "~", "J" }) do
    map(lhs, noop)
  end

  keymaps.set("n", keys.read, function()
    close()
    require("exocortex").read_selected()
  end, { buffer = buf, silent = true, nowait = true, desc = "Read view" })

  if node.snapshot and root_dir then
    keymaps.set("n", keys.review_diffs, function()
      close()
      require("exocortex.review").start(node, root_dir)
    end, { buffer = buf, silent = true, nowait = true, desc = "Review diffs" })

    keymaps.set("n", keys.diffview, function()
      close()
      vim.cmd(string.format("DiffviewOpen %s..%s", node.base, node.snapshot))
    end, { buffer = buf, silent = true, nowait = true, desc = "Open in Diffview" })
  end

  if from_rect then
    animate(win, start, final, 120)
  end

  return win
end

return M
