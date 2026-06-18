-- Node detail float with a grow-from-card transition. The float starts at the
-- card's screen rect and animates to a centered reading pane.

local M = {}

local function smoothstep(t)
  return t * t * (3 - 2 * t)
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

  table.insert(lines, string.format("_%s · %s · %s_", node.agent or "?", node.status, node.stat or ""))
  table.insert(lines, "")

  for _, line in ipairs(vim.split(node.response or "(no response yet)", "\n")) do
    table.insert(lines, line)
  end

  if node.files and #node.files > 0 then
    table.insert(lines, "")
    table.insert(lines, "## changed files")

    for _, f in ipairs(node.files) do
      table.insert(lines, string.format("- `%s` %s", f.status, f.path))
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

  local footer = node.snapshot
    and "  r read  d review diffs  D diffview  q close  "
    or  "  r read  q close  "

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

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    close()
    if not pcall(vim.cmd.tabclose) then
      vim.cmd("enew")
    end
  end, { buffer = buf, silent = true, nowait = true })

  vim.keymap.set("n", "r", function()
    close()
    require("exocortex").read_selected()
  end, { buffer = buf, silent = true, nowait = true, desc = "Read view" })

  if node.snapshot and root_dir then
    vim.keymap.set("n", "d", function()
      close()
      require("exocortex.review").start(node, root_dir)
    end, { buffer = buf, silent = true, nowait = true, desc = "Review diffs" })

    vim.keymap.set("n", "D", function()
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
