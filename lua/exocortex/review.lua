-- One-hunk-at-a-time review. Full file visible for context; cursor navigates
-- between hunks. Left window = your real file (editable). Right = snapshot.
--
--   a    accept current diff hunk
--   r    reject current diff hunk (skip, keep your version)
--   e    accept and edit (apply hunk, stay positioned for manual changes)
--   n    next diff hunk
--   p    previous diff hunk
--   ]    next changed file
--   [    previous changed file
--   J    page down
--   K    page up
--   A    accept all hunks in this file
--   q    end review, return to graph

local git = require("exocortex.git")

local M = {}

M.session = nil

local REVIEW_MAPS = { "a", "r", "e", "n", "p", "]", "[", "J", "K", "A", "q" }

local HUNK_NS = vim.api.nvim_create_namespace("exocortex_hunk")
vim.api.nvim_set_hl(0, "ExocortexHunkMarker", { fg = "#ffcc00", bold = true, default = true })

local GUIDE = "  a accept  r reject  e edit  │  n next hunk  p prev hunk  │  ] next file  [ prev file  │  J page↓  K page↑  │  A accept all  q quit  "

local function valid_win(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function is_editor_win(win)
  if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "NvimTree"
end

local function find_editor_window()
  local tabs = vim.api.nvim_list_tabpages()
  local ordered = {}
  local alt_idx = vim.fn.tabpagenr("#")
  local alt = alt_idx > 0 and tabs[alt_idx] or nil
  if alt then table.insert(ordered, alt) end
  vim.list_extend(ordered, tabs)
  for _, tab in ipairs(ordered) do
    if vim.api.nvim_tabpage_is_valid(tab) then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if is_editor_win(win) then return win end
      end
    end
  end
  return nil
end

local function flush_pending_edits()
  local s = M.session
  if s and s.left_buf and vim.api.nvim_buf_is_valid(s.left_buf) and vim.bo[s.left_buf].modified then
    vim.api.nvim_buf_call(s.left_buf, function()
      vim.cmd("silent! update")
    end)
  end
end

local function file_winbar(s)
  local f = s.files[s.index]
  return string.format("  [%d/%d]  %s  [%s]  %%=%s", s.index, #s.files, f.path, f.status, GUIDE)
end

local function snapshot_winbar()
  return "  snapshot (read-only)  %=" .. GUIDE
end

local function update_winbars()
  local s = M.session
  if not s then return end
  if valid_win(s.left_win) then vim.wo[s.left_win].winbar = file_winbar(s) end
  if valid_win(s.right_win) then vim.wo[s.right_win].winbar = snapshot_winbar() end
end

local function left_win_current()
  local s = M.session
  if not s then return nil end
  if s.left_buf and vim.api.nvim_buf_is_valid(s.left_buf) then
    local w = vim.fn.bufwinid(s.left_buf)
    if w ~= -1 then return w end
  end
  return valid_win(s.left_win) and s.left_win or nil
end

local function center_view(win)
  if valid_win(win) then
    vim.api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
  end
end

-- Walk up/down from cursor_line to find the full extent of the diff hunk.
local function find_hunk_range(lwin, cursor_line)
  local lbuf = vim.api.nvim_win_get_buf(lwin)
  local n     = vim.api.nvim_buf_line_count(lbuf)
  local hs, he = cursor_line, cursor_line

  vim.api.nvim_win_call(lwin, function()
    if vim.fn.diff_hlID(cursor_line, 1) == 0 then return end
    for l = cursor_line - 1, math.max(1, cursor_line - 500), -1 do
      if vim.fn.diff_hlID(l, 1) == 0 then break end
      hs = l
    end
    for l = cursor_line + 1, math.min(n, cursor_line + 500) do
      if vim.fn.diff_hlID(l, 1) == 0 then break end
      he = l
    end
  end)

  return hs, he
end

-- Place bracket signs in the left buffer marking every line of the current hunk.
local function mark_current_hunk(lwin)
  local s = M.session
  if not s then return end

  for buf in pairs(s.mapped_bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, HUNK_NS, 0, -1)
    end
  end

  if not valid_win(lwin) then return end

  local lbuf = vim.api.nvim_win_get_buf(lwin)
  local row   = vim.api.nvim_win_get_cursor(lwin)[1]
  local hs, he = find_hunk_range(lwin, row)
  local span  = he - hs

  for lnum = hs, he do
    local text
    if span == 0 then
      text = "▶ "
    elseif lnum == hs then
      text = "┌ "
    elseif lnum == he then
      text = "└ "
    else
      text = "│ "
    end
    vim.api.nvim_buf_set_extmark(lbuf, HUNK_NS, lnum - 1, 0, {
      sign_text     = text,
      sign_hl_group = "ExocortexHunkMarker",
      priority      = 100,
    })
  end
end

-- Move to next hunk in win. Returns true if cursor moved (hunk found).
local function next_hunk(win)
  local row_before = vim.api.nvim_win_get_cursor(win)[1]
  vim.api.nvim_win_call(win, function()
    pcall(vim.cmd, "normal! ]c")
  end)
  local moved = vim.api.nvim_win_get_cursor(win)[1] ~= row_before
  if moved then
    center_view(win)
    mark_current_hunk(win)
  end
  return moved
end

-- Move to previous hunk in win. Returns true if cursor moved.
local function prev_hunk(win)
  local row_before = vim.api.nvim_win_get_cursor(win)[1]
  vim.api.nvim_win_call(win, function()
    pcall(vim.cmd, "normal! [c")
  end)
  local moved = vim.api.nvim_win_get_cursor(win)[1] ~= row_before
  if moved then
    center_view(win)
    mark_current_hunk(win)
  end
  return moved
end

local function make_left_editable(lbuf)
  vim.api.nvim_set_option_value("modifiable", true, { buf = lbuf })
  vim.api.nvim_set_option_value("readonly", false, { buf = lbuf })
end

-- Apply the snapshot's version of the current hunk into the real file.
local function accept_hunk(lwin)
  local lbuf = vim.api.nvim_win_get_buf(lwin)
  make_left_editable(lbuf)
  vim.api.nvim_win_call(lwin, function()
    pcall(vim.cmd, "diffget")
  end)
end

-- After acting on a hunk, move to the next one or advance to the next file.
local function advance()
  local s = M.session
  local lwin = left_win_current()
  if not lwin then return end

  if next_hunk(lwin) then
    vim.api.nvim_set_current_win(lwin)
  else
    flush_pending_edits()
    if s.index < #s.files then
      M.show_file(s.index + 1)
    else
      vim.notify("exocortex: review complete", vim.log.levels.INFO)
      M.stop()
    end
  end
end

local function page_scroll(dir)
  local lwin = left_win_current()
  if not lwin then return end
  vim.api.nvim_set_current_win(lwin)
  local key = dir > 0 and "<C-f>" or "<C-b>"
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "n", false)
end

local function set_review_maps(buf)
  M.session.mapped_bufs[buf] = true

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc })
  end

  map("a", function()
    local lwin = left_win_current()
    if not lwin then return end
    accept_hunk(lwin)
    vim.api.nvim_set_current_win(lwin)
    advance()
  end, "Accept hunk")

  map("r", function()
    advance()
  end, "Reject hunk (skip)")

  map("e", function()
    local lwin = left_win_current()
    if not lwin then return end
    accept_hunk(lwin)
    vim.api.nvim_set_current_win(lwin)
    center_view(lwin)
  end, "Accept and edit hunk")

  map("n", function()
    local lwin = left_win_current()
    if lwin then
      next_hunk(lwin)
      vim.api.nvim_set_current_win(lwin)
    end
  end, "Next hunk")

  map("p", function()
    local lwin = left_win_current()
    if lwin then
      prev_hunk(lwin)
      vim.api.nvim_set_current_win(lwin)
    end
  end, "Previous hunk")

  map("]", function() M.jump(1) end, "Next file")
  map("[", function() M.jump(-1) end, "Previous file")

  map("J", function() page_scroll(1) end, "Page down")
  map("K", function() page_scroll(-1) end, "Page up")

  map("A", M.accept_file, "Accept all hunks in file")
  map("q", M.stop, "End review")
end

local function clear_review_maps(mapped_bufs)
  for buf in pairs(mapped_bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      for _, lhs in ipairs(REVIEW_MAPS) do
        pcall(vim.keymap.del, "n", lhs, { buffer = buf })
      end
    end
  end
end

function M.stop()
  local s = M.session
  if not s then return end

  flush_pending_edits()
  M.session = nil

  for buf in pairs(s.mapped_bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, HUNK_NS, 0, -1)
    end
  end

  if valid_win(s.left_win) then
    vim.api.nvim_win_call(s.left_win, function()
      vim.cmd("silent! diffoff")
    end)
    pcall(function()
      vim.wo[s.left_win].winbar     = nil
      vim.wo[s.left_win].signcolumn = "auto"
      vim.wo[s.left_win].cursorline = false
    end)
  end

  if valid_win(s.right_win) then
    vim.api.nvim_win_close(s.right_win, true)
  end

  clear_review_maps(s.mapped_bufs)

  if s.return_tab and vim.api.nvim_tabpage_is_valid(s.return_tab) then
    vim.api.nvim_set_current_tabpage(s.return_tab)
  end
end

local function ensure_windows()
  local s = M.session

  if not valid_win(s.left_win) then
    if valid_win(s.right_win) then
      vim.api.nvim_win_close(s.right_win, true)
      s.right_win = nil
    end
    s.left_win = find_editor_window()
    if not s.left_win then
      vim.cmd("tabnew")
      s.left_win = vim.api.nvim_get_current_win()
    end
  end

  vim.api.nvim_set_current_win(s.left_win)

  if not valid_win(s.right_win) then
    vim.cmd("rightbelow vsplit")
    s.right_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(s.left_win)
  end
end

function M.jump(delta)
  local s = M.session
  if not s then return end

  local i = s.index + delta
  if i < 1 or i > #s.files then
    vim.notify(
      string.format("exocortex: no %s file (%d/%d)", delta > 0 and "next" or "previous", s.index, #s.files),
      vim.log.levels.INFO
    )
    return
  end

  flush_pending_edits()
  M.show_file(i)
end

function M.accept_file()
  local s = M.session
  if not s then return end

  local lwin = left_win_current()
  if not lwin then return end
  local lbuf = vim.api.nvim_win_get_buf(lwin)
  make_left_editable(lbuf)

  vim.api.nvim_win_call(lwin, function()
    vim.cmd("silent! %diffget")
    vim.cmd("silent! update")
  end)
end

function M.show_file(index)
  local s = M.session
  local f = s.files[index]
  s.index = index

  ensure_windows()

  for _, win in ipairs({ s.left_win, s.right_win }) do
    vim.api.nvim_win_call(win, function() vim.cmd("silent! diffoff") end)
  end

  local real_path = s.root .. "/" .. f.path
  vim.fn.mkdir(vim.fn.fnamemodify(real_path, ":h"), "p")
  vim.api.nvim_set_current_win(s.left_win)
  vim.cmd("edit " .. vim.fn.fnameescape(real_path))
  s.left_buf = vim.api.nvim_get_current_buf()
  vim.bo[s.left_buf].modifiable = true
  vim.bo[s.left_buf].readonly = false
  set_review_maps(s.left_buf)

  local right_buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, right_buf, string.format("exocortex://%s/%s", s.node.id, f.path))
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, git.file_at(s.root, s.node.snapshot, f.path))

  local ft = vim.filetype.match({ filename = f.path })
  if ft then vim.bo[right_buf].filetype = ft end

  vim.bo[right_buf].modifiable = false
  vim.bo[right_buf].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(s.right_win, right_buf)
  set_review_maps(right_buf)

  for _, win in ipairs({ s.left_win, s.right_win }) do
    vim.api.nvim_win_call(win, function() vim.cmd("diffthis") end)
  end

  -- Open all folds so the full file is visible for context.
  for _, win in ipairs({ s.left_win, s.right_win }) do
    vim.api.nvim_win_call(win, function() pcall(vim.cmd, "normal! zR") end)
  end

  -- Fixed sign column keeps layout stable when marks appear/disappear.
  vim.wo[s.left_win].signcolumn = "yes:1"
  vim.wo[s.left_win].cursorline = true

  update_winbars()

  -- Land on first hunk, centred, and mark it.
  vim.api.nvim_set_current_win(s.left_win)
  pcall(vim.cmd, "normal! gg]c")
  center_view(s.left_win)
  mark_current_hunk(s.left_win)

  vim.notify(string.format("[%d/%d] %s", index, #s.files, f.path), vim.log.levels.INFO)
end

function M.start(node, root)
  if not node.snapshot then
    vim.notify("exocortex: node has no snapshot yet", vim.log.levels.WARN)
    return
  end

  local files = node.files or {}
  if #files == 0 then
    vim.notify("exocortex: node made no file changes", vim.log.levels.INFO)
    return
  end

  M.stop()

  M.session = {
    node = node,
    root = root,
    files = files,
    index = 0,
    return_tab = vim.api.nvim_get_current_tabpage(),
    mapped_bufs = {},
  }

  M.show_file(1)
end

return M
