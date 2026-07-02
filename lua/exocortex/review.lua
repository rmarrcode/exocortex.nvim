-- One-diff-at-a-time review. Left window = the node proposal (read-only).
-- Right window = your current file (editable). Each proposed diff gets a
-- stable # marker; the real file changes only when you accept a focused hunk.
--
--   Ctrl-a        accept current diff hunk
--   Leader+s      skip current diff hunk
--   Ctrl-u        undo accept/skip and show the proposal again
--   Ctrl-e        focus the editable right side
--   Ctrl-j / Ctrl-k next / previous focused diff hunk
--   Ctrl-; / Ctrl-p next / previous diff hunk from cursor position
--   Ctrl-l / Ctrl-h next / previous changed file
--   ] / [         page down / up inside the file
--   Ctrl-t        put the current function at the top of the window
--   Ctrl-q / Esc  end review

local git = require("exocortex.git")
local config_loader = require("exocortex.config_loader")
local keymaps = require("exocortex.keymaps")

local M = {}

M.session = nil

local function review_maps()
  return keymaps.flatten(config_loader.keys("diff"))
end

local function first_key(lhses)
  if type(lhses) == "table" then return lhses[1] or "" end
  return lhses or ""
end

local function pretty_key(lhses)
  local key = first_key(lhses)

  return (key
    :gsub("<leader>", "Leader+")
    :gsub("<M%-(.-)>", function(inner)
      if #inner == 1 then
        return "Alt+" .. inner:upper()
      end
      return "Alt+" .. inner
    end)
    :gsub("<C%-(.-)>", function(inner)
      if #inner == 1 then
        return "Ctrl+" .. inner:upper()
      end
      return "Ctrl+" .. inner
    end)
    :gsub("<PageDown>", "PgDn")
    :gsub("<PageUp>", "PgUp")
    :gsub("<Down>", "Down")
    :gsub("<Up>", "Up")
    :gsub("<Left>", "Left")
    :gsub("<Right>", "Right"))
end

local MARK_NS = vim.api.nvim_create_namespace("exocortex_review_marks")
local TRACK_NS = vim.api.nvim_create_namespace("exocortex_review_tracks")

vim.api.nvim_set_hl(0, "ExocortexDiffCurrent", { fg = "#ffcc00", bold = true, default = true })
vim.api.nvim_set_hl(0, "ExocortexDiffProposed", { fg = "#7aa2f7", default = true })
vim.api.nvim_set_hl(0, "ExocortexDiffAccepted", { fg = "#73daca", default = true })
vim.api.nvim_set_hl(0, "ExocortexDiffSkipped", { fg = "#8b919c", default = true })

local function guide()
  local keys = config_loader.keys("diff")
  return string.format(
    "  diff keys: %s accept  %s skip  %s undo  %s edit  |  %s/%s diff  %s/%s from-cursor  |  %s/%s file  |  %s/%s page  |  %s top  |  %s/%s close  ",
    pretty_key(keys.accept),
    pretty_key(keys.skip),
    pretty_key(keys.undo),
    pretty_key(keys.edit_right),
    pretty_key(keys.previous),
    pretty_key(keys.next),
    pretty_key(keys.previous_from_cursor),
    pretty_key(keys.next_from_cursor),
    pretty_key(keys.previous_file),
    pretty_key(keys.next_file),
    pretty_key(keys.page_up),
    pretty_key(keys.page_down),
    pretty_key(keys.function_to_top),
    pretty_key(keys.close),
    pretty_key(type(keys.close) == "table" and keys.close[2] or keys.close)
  )
end

local function valid_win(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function is_editor_win(win)
  if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  return vim.bo[buf].buftype == "" and ft ~= "NvimTree" and not ft:match("^exocortex")
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

local function current_hunk(s)
  if not s or not s.hunks then return nil end
  return s.hunks[s.hunk_index or 1]
end

local function status_label(hunk)
  if not hunk then return "no diffs" end
  if hunk.status == "accepted" then return "accepted" end
  if hunk.status == "skipped" then return "skipped/rejected" end
  return "proposed"
end

local function proposal_winbar(s)
  local f = s.files[s.index]
  local h = current_hunk(s)
  local target = h and string.format("proposal #%d/%d %s", h.index, #s.hunks, status_label(h)) or "no diffs"
  return string.format("  [%d/%d]  %s  [%s]  %s  %%=%s", s.index, #s.files, f.path, f.status, target, guide())
end

local function target_winbar(s)
  local h = current_hunk(s)
  local target = h and string.format("target #%d/%d %s", h.index, #s.hunks, status_label(h)) or "target"
  return "  editable file  " .. target .. "  %=" .. guide()
end

local function open_node_diff(node)
  if not (node.base and node.snapshot) then
    return false
  end

  vim.cmd(string.format("DiffviewOpen %s..%s", node.base, node.snapshot))
  return true
end

local function update_winbars()
  local s = M.session
  if not s then return end
  if valid_win(s.left_win) then vim.wo[s.left_win].winbar = proposal_winbar(s) end
  if valid_win(s.right_win) then vim.wo[s.right_win].winbar = target_winbar(s) end
end

local function target_win_current()
  local s = M.session
  if not s then return nil end
  if s.right_buf and vim.api.nvim_buf_is_valid(s.right_buf) then
    local w = vim.fn.bufwinid(s.right_buf)
    if w ~= -1 then return w end
  end
  return valid_win(s.right_win) and s.right_win or nil
end

local function center_view(win)
  if valid_win(win) then
    vim.api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
  end
end

local function top_view(win)
  if valid_win(win) then
    vim.api.nvim_win_call(win, function() vim.cmd("normal! zt") end)
  end
end

local function reveal_view(win, row, line_count, force_top)
  if not valid_win(win) then
    return
  end

  pcall(vim.api.nvim_win_set_cursor, win, { row + 1, 0 })

  local height = math.max(1, vim.api.nvim_win_get_height(win) - 3)
  if force_top or line_count >= height then
    top_view(win)
  else
    center_view(win)
  end
end

local function is_function_node(node)
  if not node then
    return false
  end

  local typ = node:type():lower()
  return typ:find("function", 1, true)
    or typ:find("method", 1, true)
    or typ:find("constructor", 1, true)
    or typ:find("lambda", 1, true)
    or typ:find("subroutine", 1, true)
end

local function function_start_row(buf, row0)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if ok and parser then
    local parsed = parser:parse()
    local tree = parsed and parsed[1]
    if tree then
      local node = vim.treesitter.get_node({ bufnr = buf, pos = { row0, 0 } })
      while node do
        if is_function_node(node) then
          local start_row = node:range()
          return start_row
        end
        node = node:parent()
      end
    end
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, row0 + 1, false)
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line:match("^%s*function%s+")
      or line:match("^%s*local%s+function%s+")
      or line:match("^%s*def%s+")
      or line:match("^%s*class%s+")
      or line:match("^%s*[A-Za-z_][A-Za-z0-9_]*%s*=%s*function%s*") then
      return i - 1
    end
  end
end

local function function_to_top(win)
  if not valid_win(win) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local row0 = vim.api.nvim_win_get_cursor(win)[1] - 1
  local start_row = function_start_row(buf, row0)

  if start_row == nil then
    vim.notify("exocortex: no enclosing function found", vim.log.levels.INFO)
    return
  end

  pcall(vim.api.nvim_win_set_cursor, win, { start_row + 1, 0 })
  vim.api.nvim_win_call(win, function() vim.cmd("normal! zt") end)
end

local function make_target_editable(buf)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("readonly", false, { buf = buf })
end

local function save_target()
  local s = M.session
  if not (s and s.right_buf and vim.api.nvim_buf_is_valid(s.right_buf)) then
    return
  end

  if vim.bo[s.right_buf].modified then
    vim.api.nvim_buf_call(s.right_buf, function()
      local ok, err = pcall(vim.cmd, "silent update")
      if not ok then
        vim.notify("exocortex: failed to save accepted diff: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end
end

local function slice(lines, start, count)
  local out = {}

  if count <= 0 then
    return out
  end

  for i = start, start + count - 1 do
    out[#out + 1] = lines[i] or ""
  end

  return out
end

local function text_from_lines(lines)
  return table.concat(lines, "\n")
end

local function compute_hunks(left_lines, right_lines)
  local ok, diff = pcall(vim.diff, text_from_lines(left_lines), text_from_lines(right_lines), {
    result_type = "indices",
    algorithm = "histogram",
  })

  if not ok or type(diff) ~= "table" then
    vim.notify(string.format("exocortex: vim.diff failed (ok=%s diff_type=%s err=%s)", tostring(ok), type(diff), tostring(diff)), vim.log.levels.ERROR)
    return {}
  end

  local hunks = {}

  for _, item in ipairs(diff) do
    local old_start, old_count, new_start, new_count = item[1], item[2], item[3], item[4]

    if old_count > 0 or new_count > 0 then
      local start0 = old_count > 0 and old_start - 1 or old_start
      hunks[#hunks + 1] = {
        index = #hunks + 1,
        old_start = old_start,
        old_count = old_count,
        new_start = new_start,
        new_count = new_count,
        start0 = start0,
        count = old_count,
        original = slice(left_lines, old_start, old_count),
        proposed = slice(right_lines, new_start, new_count),
        status = "proposed",
      }
    end
  end

  return hunks
end

local function ext_row(buf, row)
  local n = vim.api.nvim_buf_line_count(buf)
  if row < 0 then return 0 end
  if row > n then return n end
  return row
end

local function display_row(buf, row)
  local n = vim.api.nvim_buf_line_count(buf)
  return math.max(0, math.min(row, n - 1))
end

local function place_track(lbuf, hunk, start0, end0)
  start0 = ext_row(lbuf, start0)
  end0 = ext_row(lbuf, math.max(start0, end0))
  hunk.start0 = start0
  hunk.count = end0 - start0

  hunk.start_mark = vim.api.nvim_buf_set_extmark(lbuf, TRACK_NS, start0, 0, {
    id = hunk.start_mark,
    right_gravity = false,
  })
  hunk.end_mark = vim.api.nvim_buf_set_extmark(lbuf, TRACK_NS, end0, 0, {
    id = hunk.end_mark,
    right_gravity = true,
  })
end

local function place_tracks(lbuf, hunks)
  vim.api.nvim_buf_clear_namespace(lbuf, TRACK_NS, 0, -1)

  for _, hunk in ipairs(hunks) do
    place_track(lbuf, hunk, hunk.start0, hunk.start0 + hunk.count)
  end
end

local function mark_pos(buf, id, fallback)
  if not id then return fallback end
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, TRACK_NS, id, {})
  if not pos or not pos[1] then return fallback end
  return pos[1]
end

local function hunk_range(hunk)
  local s = M.session
  local buf = s and s.right_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return hunk.start0, hunk.start0 + hunk.count
  end

  local start0 = mark_pos(buf, hunk.start_mark, hunk.start0)
  local end0 = mark_pos(buf, hunk.end_mark, hunk.start0 + hunk.count)

  if end0 < start0 then
    -- Extmarks crossed: a previous accept shifted lines and the tracking is
    -- broken for this hunk. Return a zero-length range so callers can detect
    -- it rather than silently converting a replacement into an insertion.
    end0 = start0
  end

  hunk.start0 = start0
  hunk.count = end0 - start0
  return start0, end0
end

local function hunk_row_for_buf(hunk, buf)
  local s = M.session
  if not (s and hunk and buf and vim.api.nvim_buf_is_valid(buf)) then
    return nil
  end

  if buf == s.left_buf then
    local left_start0 = hunk.new_count > 0 and hunk.new_start - 1 or hunk.new_start
    return display_row(buf, left_start0)
  end

  if buf == s.right_buf then
    local right_start0 = hunk_range(hunk)
    return display_row(buf, right_start0)
  end

  return nil
end

local function marker_hl(hunk, current)
  if current then return "ExocortexDiffCurrent" end
  if hunk.status == "accepted" then return "ExocortexDiffAccepted" end
  if hunk.status == "skipped" then return "ExocortexDiffSkipped" end
  return "ExocortexDiffProposed"
end

local function mark_hunks()
  local s = M.session
  if not s then return end

  for _, buf in ipairs({ s.left_buf, s.right_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, MARK_NS, 0, -1)
    end
  end

  if not (s.left_buf and vim.api.nvim_buf_is_valid(s.left_buf)) then
    return
  end

  local total = #(s.hunks or {})

  for _, hunk in ipairs(s.hunks or {}) do
    local current = hunk.index == s.hunk_index
    local hl = marker_hl(hunk, current)
    local label = string.format("  #%d/%d %s%s", hunk.index, total, status_label(hunk), current and " current" or "")
    local left_start0 = hunk.new_count > 0 and hunk.new_start - 1 or hunk.new_start
    local left_row = display_row(s.left_buf, left_start0)

    vim.api.nvim_buf_set_extmark(s.left_buf, MARK_NS, left_row, 0, {
      sign_text = current and ">>" or "  ",
      sign_hl_group = hl,
      virt_text = { { label, hl } },
      virt_text_pos = "eol",
      priority = current and 140 or 120,
    })

    if s.right_buf and vim.api.nvim_buf_is_valid(s.right_buf) then
      local right_start0 = hunk_range(hunk)
      local right_row = display_row(s.right_buf, right_start0)
      vim.api.nvim_buf_set_extmark(s.right_buf, MARK_NS, right_row, 0, {
        virt_text = { { string.format("  #%d/%d target %s", hunk.index, total, status_label(hunk)), hl } },
        virt_text_pos = "eol",
        priority = current and 140 or 120,
      })
    end
  end
end

local function sync_diff()
  local s = M.session
  if not s then return end

  for _, win in ipairs({ s.left_win, s.right_win }) do
    if valid_win(win) then
      vim.api.nvim_win_call(win, function() pcall(vim.cmd, "diffupdate") end)
    end
  end

  mark_hunks()
  update_winbars()
end

local function select_hunk(index)
  local s = M.session
  if not (s and s.hunks and #s.hunks > 0) then
    update_winbars()
    mark_hunks()
    return false
  end

  s.hunk_index = math.max(1, math.min(index, #s.hunks))
  local hunk = current_hunk(s)
  local left_row, left_count
  local right_row, right_count

  if valid_win(s.left_win) and s.left_buf and vim.api.nvim_buf_is_valid(s.left_buf) then
    local left_start0 = hunk.new_count > 0 and hunk.new_start - 1 or hunk.new_start
    left_row = display_row(s.left_buf, left_start0)
    left_count = math.max(1, hunk.new_count or 0)
  end

  if valid_win(s.right_win) and s.right_buf and vim.api.nvim_buf_is_valid(s.right_buf) then
    local right_start0, right_end0 = hunk_range(hunk)
    right_row = display_row(s.right_buf, right_start0)
    right_count = math.max(1, right_end0 - right_start0)
  end

  local left_large = left_count and valid_win(s.left_win)
    and left_count >= math.max(1, vim.api.nvim_win_get_height(s.left_win) - 3)
  local right_large = right_count and valid_win(s.right_win)
    and right_count >= math.max(1, vim.api.nvim_win_get_height(s.right_win) - 3)
  local force_top = left_large or right_large

  if left_row then
    reveal_view(s.left_win, left_row, left_count or 1, force_top)
  end

  if right_row then
    reveal_view(s.right_win, right_row, right_count or 1, force_top)
  end

  -- In diff mode the second window reveal can move the first via scrollbind.
  -- For large hunks, anchor the side that actually contains more changed lines
  -- so full-page insertions stay visible before they are accepted.
  if force_top and left_row and right_row then
    if (left_count or 1) >= (right_count or 1) then
      reveal_view(s.left_win, left_row, left_count or 1, true)
    else
      reveal_view(s.right_win, right_row, right_count or 1, true)
    end
  end

  if valid_win(s.right_win) then
    vim.api.nvim_set_current_win(s.right_win)
  end

  sync_diff()
  return true
end

local function current_or_notify()
  local s = M.session
  local hunk = current_hunk(s)

  if not hunk then
    vim.notify("exocortex: no diffs in this file", vim.log.levels.INFO)
    return nil
  end

  return hunk
end

local function replace_hunk(hunk, lines, status, opts)
  opts = opts or {}
  local s = M.session
  if not (s and s.right_buf and vim.api.nvim_buf_is_valid(s.right_buf)) then
    return
  end

  local start0, end0 = hunk_range(hunk)

  -- hunk_range returns start0 == end0 when extmarks have crossed (broken
  -- tracking after a complex multi-hunk accept sequence). Reject the accept
  -- rather than silently turning a replacement into an insertion.
  if not opts.allow_zero_length_restore and hunk.count == 0 and #lines > 0 and end0 == start0 and (hunk.old_count or 0) > 0 then
    vim.notify("exocortex: hunk position tracking lost — cannot safely apply this hunk", vim.log.levels.WARN)
    return
  end

  make_target_editable(s.right_buf)
  vim.api.nvim_buf_set_lines(s.right_buf, start0, end0, false, lines)
  place_track(s.right_buf, hunk, start0, start0 + #lines)
  hunk.status = status
  save_target()
  select_hunk(hunk.index)
end

local function accept_current()
  local hunk = current_or_notify()
  if not hunk then return end

  local s = M.session
  if s and s.right_buf and vim.api.nvim_buf_is_valid(s.right_buf) and hunk.status ~= "accepted" then
    local start0, end0 = hunk_range(hunk)
    hunk.target_original = vim.api.nvim_buf_get_lines(s.right_buf, start0, end0, false)
  end

  replace_hunk(hunk, hunk.proposed, "accepted")
end

local function skip_current()
  local hunk = current_or_notify()
  if not hunk then return end
  hunk.status = "skipped"
  select_hunk(hunk.index)
end

local function undo_current()
  local hunk = current_or_notify()
  if not hunk then return end

  if hunk.status == "accepted" then
    replace_hunk(hunk, hunk.target_original or hunk.original, "proposed", { allow_zero_length_restore = true })
    hunk.target_original = nil
  else
    hunk.status = "proposed"
    select_hunk(hunk.index)
  end
end

local function edit_current()
  local s = M.session
  local hunk = current_or_notify()
  if not (s and hunk and valid_win(s.right_win)) then return end
  make_target_editable(s.right_buf)
  select_hunk(hunk.index)
  vim.notify("exocortex: edit on the right; proposal side is read-only", vim.log.levels.INFO)
end

local function next_hunk()
  local s = M.session
  if not (s and s.hunks and #s.hunks > 0) then return end

  if s.hunk_index >= #s.hunks then
    vim.notify("exocortex: already on last diff", vim.log.levels.INFO)
    select_hunk(s.hunk_index)
    return
  end

  select_hunk(s.hunk_index + 1)
end

local function prev_hunk()
  local s = M.session
  if not (s and s.hunks and #s.hunks > 0) then return end

  if s.hunk_index <= 1 then
    vim.notify("exocortex: already on first diff", vim.log.levels.INFO)
    select_hunk(s.hunk_index)
    return
  end

  select_hunk(s.hunk_index - 1)
end

local function hunk_from_cursor(dir)
  local s = M.session
  if not (s and s.hunks and #s.hunks > 0) then
    return nil
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()

  if not (valid_win(win) and (buf == s.left_buf or buf == s.right_buf)) then
    win = target_win_current()
    buf = win and vim.api.nvim_win_get_buf(win) or nil
  end

  if not (win and buf and vim.api.nvim_buf_is_valid(buf)) then
    return nil
  end

  local cursor_row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local candidate

  for _, hunk in ipairs(s.hunks) do
    local hunk_row = hunk_row_for_buf(hunk, buf)
    if hunk_row ~= nil then
      if dir > 0 and hunk_row > cursor_row then
        candidate = hunk.index
        break
      end

      if dir < 0 and hunk_row < cursor_row then
        candidate = hunk.index
      end
    end
  end

  return candidate
end

local function page_hunk(dir)
  local s = M.session
  if not (s and s.hunks and #s.hunks > 0) then return end

  local candidate = hunk_from_cursor(dir)

  if candidate then
    select_hunk(candidate)
    return
  end

  if dir > 0 then
    vim.notify("exocortex: already on last diff", vim.log.levels.INFO)
  else
    vim.notify("exocortex: already on first diff", vim.log.levels.INFO)
  end
end

local function page_scroll(dir)
  local win = target_win_current()
  if not win then return end

  local key = dir > 0 and "<C-f>" or "<C-b>"
  vim.api.nvim_win_call(win, function()
    vim.cmd.normal({ args = { key }, bang = true })
  end)
end

local function set_review_maps(buf)
  M.session.mapped_bufs[buf] = true

  local function map(lhs, fn, desc)
    keymaps.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc })
  end

  local keys = config_loader.keys("diff")

  map(keys.accept, accept_current, "Accept diff")
  map(keys.skip, skip_current, "Skip diff")
  map(keys.undo, undo_current, "Undo accept/skip")
  map(keys.edit_right, edit_current, "Edit right side")
  map(keys.next, next_hunk, "Next diff")
  map(keys.previous, prev_hunk, "Previous diff")
  map(keys.next_from_cursor, function() page_hunk(1) end, "Next diff")
  map(keys.previous_from_cursor, function() page_hunk(-1) end, "Previous diff")
  map(keys.next_file, function() M.jump(1) end, "Next file")
  map(keys.previous_file, function() M.jump(-1) end, "Previous file")
  map(keys.page_down, function() page_scroll(1) end, "Page down")
  map(keys.page_up, function() page_scroll(-1) end, "Page up")
  map(keys.function_to_top, function() function_to_top(vim.api.nvim_get_current_win()) end, "Put function at top")
  map(keys.close, M.stop, "End review")
end

local function clear_review_maps(mapped_bufs)
  for buf in pairs(mapped_bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      for _, lhs in ipairs(review_maps()) do
        pcall(vim.keymap.del, "n", lhs, { buffer = buf })
      end
    end
  end
end

function M.stop()
  local s = M.session
  if not s then return end

  save_target()
  M.session = nil

  for buf in pairs(s.mapped_bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, MARK_NS, 0, -1)
      vim.api.nvim_buf_clear_namespace(buf, TRACK_NS, 0, -1)
    end
  end

  for _, win in ipairs({ s.left_win, s.right_win }) do
    if valid_win(win) then
      vim.api.nvim_win_call(win, function() vim.cmd("silent! diffoff") end)
    end
  end

  -- close the review tab and restore the original window to what it showed before
  if valid_win(s.right_win) then
    pcall(vim.api.nvim_win_close, s.right_win, true)
  end

  if valid_win(s.left_win) then
    pcall(function()
      vim.wo[s.left_win].winbar     = nil
      vim.wo[s.left_win].signcolumn = "auto"
      vim.wo[s.left_win].cursorline = false
    end)
  end

  if s.review_tab and vim.api.nvim_tabpage_is_valid(s.review_tab) then
    pcall(vim.api.nvim_set_current_tabpage, s.review_tab)
    pcall(vim.cmd, "tabclose")
  end

  if s.return_tab and vim.api.nvim_tabpage_is_valid(s.return_tab) then
    pcall(vim.api.nvim_set_current_tabpage, s.return_tab)
  end

  if s.left_win and vim.api.nvim_win_is_valid(s.left_win) and s.original_left_buf and vim.api.nvim_buf_is_valid(s.original_left_buf) then
    pcall(vim.api.nvim_win_set_buf, s.left_win, s.original_left_buf)
  end

  -- delete buffers the review opened that the user didn't already have loaded
  for buf in pairs(s.opened_bufs or {}) do
    if vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified then
      pcall(vim.api.nvim_buf_delete, buf, { force = false })
    end
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
      pcall(vim.api.nvim_win_close, s.right_win, true)
      s.right_win = nil
    end

    if s.review_tab and vim.api.nvim_tabpage_is_valid(s.review_tab) then
      local wins = vim.api.nvim_tabpage_list_wins(s.review_tab)
      s.left_win = wins[1]
    end

    if not valid_win(s.left_win) then
      vim.cmd("tabnew")
      s.review_tab = vim.api.nvim_get_current_tabpage()
      s.left_win = vim.api.nvim_get_current_win()
    end
  end

  if s.review_tab and vim.api.nvim_tabpage_is_valid(s.review_tab) then
    vim.api.nvim_set_current_tabpage(s.review_tab)
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

  save_target()
  M.show_file(i)
end

function M.show_file(index)
  local s = M.session
  local f = s.files[index]
  s.index = index
  s.hunks = {}
  s.hunk_index = 1

  ensure_windows()

  for _, win in ipairs({ s.left_win, s.right_win }) do
    vim.api.nvim_win_call(win, function() vim.cmd("silent! diffoff") end)
  end

  local real_path = s.root .. "/" .. f.path
  vim.fn.mkdir(vim.fn.fnamemodify(real_path, ":h"), "p")

  if not s.original_left_buf then
    s.original_left_buf = vim.api.nvim_win_get_buf(s.left_win)
  end

  local file_state = s.file_states[f.path]
  local proposal_lines = file_state and file_state.proposal_lines or git.file_at(s.root, s.node.snapshot, f.path)

  local proposal_buf = vim.api.nvim_create_buf(false, true)
  s.left_buf = proposal_buf
  pcall(vim.api.nvim_buf_set_name, proposal_buf, string.format("exocortex://%s/proposal/%s", s.node.id, f.path))
  vim.api.nvim_buf_set_lines(proposal_buf, 0, -1, false, proposal_lines)

  local ft = vim.filetype.match({ filename = f.path })
  if ft then vim.bo[proposal_buf].filetype = ft end

  vim.bo[proposal_buf].modifiable = false
  vim.bo[proposal_buf].readonly = true
  vim.bo[proposal_buf].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(s.left_win, proposal_buf)
  set_review_maps(proposal_buf)

  local right_buf = vim.fn.bufadd(real_path)
  local was_loaded = vim.api.nvim_buf_is_loaded(right_buf)
  vim.fn.bufload(right_buf)
  s.right_buf = right_buf
  if not was_loaded then
    s.opened_bufs[right_buf] = true
  end
  make_target_editable(right_buf)
  if ft and vim.bo[right_buf].filetype == "" then vim.bo[right_buf].filetype = ft end
  vim.api.nvim_win_set_buf(s.right_win, right_buf)
  set_review_maps(right_buf)

  local current_lines = vim.api.nvim_buf_get_lines(s.right_buf, 0, -1, false)
  if file_state then
    s.hunks = file_state.hunks
  else
    s.hunks = compute_hunks(current_lines, proposal_lines)
    file_state = { proposal_lines = proposal_lines, hunks = s.hunks }
    s.file_states[f.path] = file_state
  end

  vim.notify(string.format("exocortex: %d proposal lines, %d current lines -> %d tracked hunks", #proposal_lines, #current_lines, #s.hunks), vim.log.levels.INFO)
  s.hunk_index = #s.hunks > 0 and 1 or 0
  place_tracks(s.right_buf, s.hunks)

  for _, win in ipairs({ s.left_win, s.right_win }) do
    vim.api.nvim_win_call(win, function() vim.cmd("diffthis") end)
  end

  for _, win in ipairs({ s.left_win, s.right_win }) do
    vim.wo[win].foldlevel = 999
  end

  vim.wo[s.left_win].signcolumn = "yes:2"
  vim.wo[s.right_win].signcolumn = "yes:1"
  vim.wo[s.left_win].number = true
  vim.wo[s.left_win].relativenumber = true
  vim.wo[s.left_win].numberwidth = 4
  vim.wo[s.right_win].number = true
  vim.wo[s.right_win].relativenumber = true
  vim.wo[s.right_win].numberwidth = 4
  vim.wo[s.left_win].cursorline = false
  vim.wo[s.right_win].cursorline = true

  update_winbars()
  mark_hunks()

  if #s.hunks > 0 then
    select_hunk(1)
  else
    vim.api.nvim_set_current_win(s.right_win)
    vim.notify(string.format("[%d/%d] %s: no proposed diffs", index, #s.files, f.path), vim.log.levels.INFO)
  end

  vim.notify(string.format("[%d/%d] %s", index, #s.files, f.path), vim.log.levels.INFO)
end

function M.start(node, root)
  if not node.snapshot then
    vim.notify("exocortex: node has no snapshot yet", vim.log.levels.WARN)
    return
  end

  local files = node.files or {}

  if #files == 0 and node.base then
    files = git.changed_files(root, node.base, node.snapshot)
  end

  if #files == 0 then
    if not open_node_diff(node) then
      vim.notify("exocortex: node made no file changes", vim.log.levels.INFO)
    end
    return
  end

  M.stop()

  M.session = {
    node = node,
    root = root,
    files = files,
    index = 0,
    hunks = {},
    hunk_index = 1,
    return_tab = vim.api.nvim_get_current_tabpage(),
    mapped_bufs = {},
    file_states = {},
    opened_bufs = {},
    review_tab = nil,
  }

  vim.cmd("tabnew")
  M.session.review_tab = vim.api.nvim_get_current_tabpage()

  M.show_file(1)
end


M.function_to_top = function_to_top

return M
