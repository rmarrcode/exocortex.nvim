-- Horizontal DAG view: one card per prompt/response node, rendered into a
-- scratch buffer. Time flows left to right, branches stack into lanes.
-- Pan with normal motions; h/j/k/l snap between cards. The selected card is
-- drawn with a double-line border and a highlight overlay.

local state = require("exocortex.state")
local config_loader = require("exocortex.config_loader")
local keymaps = require("exocortex.keymaps")
local usage = require("exocortex.usage")

local M = {}

local BASE_CARD_W = 36
local CARD_H = 4
local BASE_HGAP = 6
local BASE_VGAP = 1
local SESSION_SIDEBAR_W = 28
local USAGE_WIDGET_H = 4

local function card_w()
  return state.is_obsidian_session and state.is_obsidian_session() and 24 or BASE_CARD_W
end

local function hgap()
  return state.is_obsidian_session and state.is_obsidian_session() and 3 or BASE_HGAP
end

local function vgap()
  return state.is_obsidian_session and state.is_obsidian_session() and 0 or BASE_VGAP
end

local function first_key(lhses)
  if type(lhses) == "table" then return lhses[1] or "" end
  return lhses or ""
end

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧" }

M.buf = nil
M.session_buf = nil
M.usage_buf = nil
M.graph_win = nil
M.session_win = nil
M.usage_win = nil
M.return_tab = nil
M.return_win = nil
M.selected = nil
M.layout = {} -- id -> { row, col, depth, lane } (1-based grid cells)
M.bar_nodes = {}
M.bar_dismissed = {}

function M.refresh_status_bar()
  if update_usage_widget then
    pcall(update_usage_widget)
  end
  pcall(vim.cmd, "redrawtabline")
end

local ns = vim.api.nvim_create_namespace("exocortex_graph")
local session_ns = vim.api.nvim_create_namespace("exocortex_sessions")
local byte_index = {} -- per row: cell -> 0-based byte offset
local spin_frame = 1
local spin_timer = nil
local flash_seq = 0
local update_usage_widget

M.unread = {} -- node id -> true when finished but not yet viewed

-- ---------------------------------------------------------------------------
-- Layout: column = depth, lane assignment by DFS. The first child inherits
-- its parent's lane; every other child gets a fresh lane below everything
-- allocated so far, which keeps edges inside a single gap band.
-- ---------------------------------------------------------------------------

local function find_named_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end

  return nil
end

local function is_graph_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
    and (buf == M.buf or buf == M.session_buf or vim.bo[buf].filetype:match("^exocortex"))
end

function M.remember_return_location(win)
  win = win or vim.api.nvim_get_current_win()

  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end

  if is_graph_buf(vim.api.nvim_win_get_buf(win)) then
    return
  end

  M.return_tab = vim.api.nvim_win_get_tabpage(win)
  M.return_win = win
end

local function flash_target_win()
  if M.return_win and vim.api.nvim_win_is_valid(M.return_win) then
    return M.return_win
  end

  local current = vim.api.nvim_get_current_win()
  if current and vim.api.nvim_win_is_valid(current) and vim.api.nvim_win_get_config(current).relative == "" then
    local buf = vim.api.nvim_win_get_buf(current)
    if not is_graph_buf(buf) then
      return current
    end
  end
end

function M.flash_code_win(message)
  local win = flash_target_win()
  if not win then
    return
  end

  flash_seq = flash_seq + 1
  local seq = flash_seq
  local old = vim.wo[win].winbar

  pcall(function()
    vim.wo[win].winbar = "%#ExocortexFlash# " .. message .. " %*"
  end)

  local timer = vim.uv.new_timer()
  timer:start(450, 0, vim.schedule_wrap(function()
    timer:stop()
    timer:close()

    if seq == flash_seq and vim.api.nvim_win_is_valid(win) then
      pcall(function()
        vim.wo[win].winbar = old
      end)
    end
  end))
end

-- Flicker the whole top tab bar when an agent finishes: the editor tabs in each
-- winbar and the native tabline both draw with the TabLine* highlight groups,
-- so overriding those (then restoring) pulses the entire bar at once.
-- Pattern: on 250ms → normal 250ms → on 250ms → normal.
local TABLINE_FLASH_GROUPS = { "TabLine", "TabLineSel", "TabLineFill" }
local TABLINE_FLASH_HL = { fg = "#1e1e1e", bg = "#6a9955", bold = true }
local tabline_flash_seq = 0
local tabline_saved = nil

function M.flash_tabline()
  -- Snapshot the real highlights only when not already mid-flash, so two
  -- completions in quick succession don't capture the flash color as "normal".
  if not tabline_saved then
    tabline_saved = {}
    for _, g in ipairs(TABLINE_FLASH_GROUPS) do
      tabline_saved[g] = vim.api.nvim_get_hl(0, { name = g })
    end
  end

  tabline_flash_seq = tabline_flash_seq + 1
  local seq = tabline_flash_seq
  local saved = tabline_saved

  local function set_flash()
    for _, g in ipairs(TABLINE_FLASH_GROUPS) do
      vim.api.nvim_set_hl(0, g, TABLINE_FLASH_HL)
    end
  end

  local function restore()
    for _, g in ipairs(TABLINE_FLASH_GROUPS) do
      vim.api.nvim_set_hl(0, g, saved[g])
    end
  end

  set_flash() -- on
  vim.defer_fn(function() if seq == tabline_flash_seq then restore() end end, 250)
  vim.defer_fn(function() if seq == tabline_flash_seq then set_flash() end end, 500)
  vim.defer_fn(function()
    if seq == tabline_flash_seq then
      restore()
      tabline_saved = nil
    end
  end, 750)
end

local function compute_layout()
  local placed = {}
  local next_lane = -1

  local function visit(node, depth, lane)
    placed[node.id] = { depth = depth, lane = lane }

    for i, kid in ipairs(state.children(node.id)) do
      local kid_lane = lane

      if i > 1 then
        next_lane = next_lane + 1
        kid_lane = next_lane
      end

      visit(kid, depth + 1, kid_lane)
    end
  end

  for _, root in ipairs(state.roots()) do
    next_lane = next_lane + 1
    visit(root, 0, next_lane)
  end

  return placed
end

-- ---------------------------------------------------------------------------
-- Grid drawing
-- ---------------------------------------------------------------------------

local function blank_grid(rows, cols)
  local grid = {}

  for r = 1, rows do
    local line = {}

    for c = 1, cols do
      line[c] = " "
    end

    grid[r] = line
  end

  return grid
end

local function put(grid, row, col, text)
  local line = grid[row]

  if not line then
    return
  end

  local i = 0

  for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
    local c = col + i

    if c >= 1 and c <= #line then
      line[c] = ch
    end

    i = i + 1
  end
end

-- Merge junction characters so sibling edges form ┬/├ joints.
local function put_join(grid, row, col, ch)
  local line = grid[row]

  if not line or col < 1 or col > #line then
    return
  end

  local existing = line[col]

  if ch == "╮" and existing == "─" then
    ch = "┬"
  elseif ch == "╰" and (existing == "│" or existing == "╰") then
    ch = "├"
  elseif ch == "│" and (existing == "╰" or existing == "├") then
    ch = "├"
  end

  line[col] = ch
end

local function fit(text, width)
  text = (text or ""):gsub("%s+", " ")
  local w = vim.fn.strdisplaywidth(text)

  if w <= width then
    return text .. string.rep(" ", width - w)
  end

  local out = {}
  local used = 0

  for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
    local cw = vim.fn.strdisplaywidth(ch)

    if used + cw > width - 1 then
      break
    end

    table.insert(out, ch)
    used = used + cw
  end

  return table.concat(out) .. "…" .. string.rep(" ", width - used - 1)
end

local function status_line(node)
  if node.status == "running" then
    return SPINNER[spin_frame] .. " running…", node.stat or ""
  elseif node.status == "error" then
    return "✗ error", node.stat or ""
  end

  return "✓ done", node.stat or ""
end

local function draw_card(grid, node, rect, selected)
  local tl, tr, bl, br, hz, vt = "╭", "╮", "╰", "╯", "─", "│"

  if selected then
    tl, tr, bl, br, hz, vt = "╔", "╗", "╚", "╝", "═", "║"
  end

  if node.kind == "src" then
    local session_meta = state.sessions[node.session_id or state.current_session] or {}
    local agent = state.format_agent(node.session_agent or session_meta.agent, node.session_model or session_meta.model)
    local timestamp = os.date("%Y-%m-%d  %H:%M", node.created or 0)
    local sha_hint = node.snapshot and node.snapshot:sub(1, 7)
      or (SPINNER[spin_frame] .. " snapshotting")

    put(grid, rect.row,     rect.col, tl .. hz .. " " .. fit("◈ source", card_w() - 6) .. " " .. hz .. tr)
    put(grid, rect.row + 1, rect.col, vt .. " " .. fit(agent, card_w() - 4) .. " " .. vt)
    put(grid, rect.row + 2, rect.col, vt .. " " .. fit(timestamp .. "  " .. sha_hint, card_w() - 4) .. " " .. vt)
    put(grid, rect.row + 3, rect.col, bl .. string.rep(hz, card_w() - 2) .. br)
    return
  end

  local icon, detail = status_line(node)
  local badge = M.unread[node.id] and "●" or " "
  put(grid, rect.row,     rect.col, tl .. hz .. " " .. fit(node.prompt, card_w() - 6) .. badge .. hz .. tr)
  put(grid, rect.row + 1, rect.col, vt .. " " .. fit(state.format_agent(node.agent, node.model) .. " · " .. icon, card_w() - 4) .. " " .. vt)
  put(grid, rect.row + 2, rect.col, vt .. " " .. fit(detail, card_w() - 4) .. " " .. vt)
  put(grid, rect.row + 3, rect.col, bl .. string.rep(hz, card_w() - 2) .. br)
end

local function draw_edge(grid, parent_rect, child_rect)
  local from_row = parent_rect.row + 1
  local to_row = child_rect.row + 1
  local from_col = parent_rect.col + card_w()
  local to_col = child_rect.col - 1

  if from_row == to_row then
    for c = from_col, to_col - 1 do
      put(grid, from_row, c, "─")
    end

    put(grid, from_row, to_col, "▶")
    return
  end

  local trunk = from_col + 2

  for c = from_col, trunk - 1 do
    put(grid, from_row, c, "─")
  end

  put_join(grid, from_row, trunk, "╮")

  for r = from_row + 1, to_row - 1 do
    put_join(grid, r, trunk, "│")
  end

  put_join(grid, to_row, trunk, "╰")

  for c = trunk + 1, to_col - 1 do
    put(grid, to_row, c, "─")
  end

  put(grid, to_row, to_col, "▶")
end

local function serialize(grid)
  local lines = {}
  byte_index = {}

  for r, row in ipairs(grid) do
    local bidx = { [1] = 0 }
    local bytes = 0

    for c, ch in ipairs(row) do
      bytes = bytes + #ch
      bidx[c + 1] = bytes
    end

    lines[r] = table.concat(row)
    byte_index[r] = bidx
  end

  return lines
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

local function card_extmarks(id, rect)
  local node = state.nodes[id]
  local base = node.kind == "src" and "ExocortexSrc"
    or node.status == "running" and "ExocortexRunning"
    or node.status == "error" and "ExocortexError"
    or "ExocortexCard"

  for r = rect.row, rect.row + CARD_H - 1 do
    local bidx = byte_index[r]

    if bidx and bidx[rect.col] and bidx[rect.col + card_w()] then
      vim.api.nvim_buf_set_extmark(M.buf, ns, r - 1, bidx[rect.col], {
        end_col = bidx[rect.col + card_w()],
        hl_group = base,
        priority = 100,
      })
    end
  end

  -- bright bold title over the prompt/label text on the top border
  local top = byte_index[rect.row]
  local title_hl = node.kind == "src" and "ExocortexSrcTitle" or "ExocortexTitle"

  if top and top[rect.col + 3] and top[rect.col + card_w() - 3] then
    vim.api.nvim_buf_set_extmark(M.buf, ns, rect.row - 1, top[rect.col + 3], {
      end_col = top[rect.col + card_w() - 3],
      hl_group = title_hl,
      priority = 105,
    })
  end

  if id == M.selected then
    for r = rect.row, rect.row + CARD_H - 1 do
      local bidx = byte_index[r]

      if bidx and bidx[rect.col] and bidx[rect.col + card_w()] then
        vim.api.nvim_buf_set_extmark(M.buf, ns, r - 1, bidx[rect.col], {
          end_col = bidx[rect.col + card_w()],
          hl_group = "ExocortexSelected",
          priority = 110,
        })
      end
    end
  end

  -- unread badge: highlight the ● on the top border (cell rect.col + card_w() - 3)
  if M.unread[id] and node.kind ~= "src" then
    local badge_cell = rect.col + card_w() - 3
    local bidx = byte_index[rect.row]
    if bidx and bidx[badge_cell] and bidx[badge_cell + 1] then
      vim.api.nvim_buf_set_extmark(M.buf, ns, rect.row - 1, bidx[badge_cell], {
        end_col = bidx[badge_cell + 1],
        hl_group = "ExocortexUnread",
        priority = 120,
      })
    end
  end
end

function M.render()
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    return
  end

  local placed = compute_layout()
  local max_depth, max_lane = 0, 0

  for _, p in pairs(placed) do
    max_depth = math.max(max_depth, p.depth)
    max_lane = math.max(max_lane, p.lane)
  end

  M.layout = {}

  for id, p in pairs(placed) do
    M.layout[id] = {
      row = p.lane * (CARD_H + vgap()) + 1,
      col = p.depth * (card_w() + hgap()) + 1,
      depth = p.depth,
      lane = p.lane,
    }
  end

  local lines

  if state.is_empty() then
    local graph_keys = config_loader.keys("graph")
    lines = { "", string.format("  no nodes yet - press %s to send the first prompt, %s for help", first_key(graph_keys.prompt_branch), first_key(graph_keys.help)), "" }
    byte_index = {}
  else
    local grid = blank_grid((max_lane + 1) * (CARD_H + vgap()), (max_depth + 1) * (card_w() + hgap()))

    for id, rect in pairs(M.layout) do
      local node = state.nodes[id]

      if node and node.parent and M.layout[node.parent] then
        draw_edge(grid, M.layout[node.parent], rect)
      end
    end

    for id, rect in pairs(M.layout) do
      draw_card(grid, state.nodes[id], rect, id == M.selected)
    end

    lines = serialize(grid)
  end

  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.bo[M.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)

  if not state.is_empty() then
    for id, rect in pairs(M.layout) do
      card_extmarks(id, rect)
    end
  end

  if update_usage_widget then
    pcall(update_usage_widget)
  end
end

-- ---------------------------------------------------------------------------
-- Selection and navigation
-- ---------------------------------------------------------------------------

local function graph_win()
  if M.graph_win and vim.api.nvim_win_is_valid(M.graph_win) then
    return M.graph_win
  end

  local win = vim.fn.bufwinid(M.buf)
  if win ~= -1 then
    M.graph_win = win
    return win
  end
end

local function cursor_to(id)
  local rect = M.layout[id]
  local win = graph_win()

  if not (rect and win) then
    return
  end

  local bidx = byte_index[rect.row + 1]
  if not (bidx and bidx[rect.col + 2]) then
    return
  end

  vim.api.nvim_win_set_cursor(win, { rect.row + 1, bidx[rect.col + 2] })

  -- Ensure the full card is visible horizontally (leftcol is 0-based display columns)
  local win_width = vim.api.nvim_win_get_width(win)
  local card_left  = rect.col - 1             -- 0-based left display column of card
  local card_right = rect.col + card_w() - 2  -- 0-based right display column of card

  local view = vim.fn.winsaveview()
  local lc = view.leftcol

  if card_right >= lc + win_width then
    lc = card_right - win_width + 4
  end
  if card_left < lc then
    lc = math.max(0, card_left - 2)
  end

  if lc ~= view.leftcol then
    vim.fn.winrestview({ leftcol = lc })
  end
end

function M.mark_read(id)
  local node = state.nodes[id]
  local key = ((node and node.session_id) or "default") .. ":" .. id
  M.unread[id] = nil
  M.bar_dismissed[key] = true
  M.refresh_status_bar()
  M.render()
end

function M.select(id)
  M.selected = id
  M.render()

  if id then
    cursor_to(id)
  end
end

function M.move(dir)
  local cur = M.selected and M.layout[M.selected]

  if not cur then
    local roots = state.roots()

    if roots[1] then
      M.select(roots[1].id)
    end

    return
  end

  if dir == "left" then
    -- only move if there is a node at depth-1 in the same lane
    for id, rect in pairs(M.layout) do
      if rect.depth == cur.depth - 1 and rect.lane == cur.lane then
        M.select(id)
        return
      end
    end
    return
  end

  if dir == "right" then
    -- only move if there is a node at depth+1 in the same lane
    for id, rect in pairs(M.layout) do
      if rect.depth == cur.depth + 1 and rect.lane == cur.lane then
        M.select(id)
        return
      end
    end
    return
  end

  -- up/down: same depth column only, nearest lane in that direction
  local want_below = dir == "down"
  local best_id, best_dl

  for id, rect in pairs(M.layout) do
    if rect.depth == cur.depth then
      local dl = rect.lane - cur.lane

      if (want_below and dl > 0) or (not want_below and dl < 0) then
        if not best_dl or math.abs(dl) < math.abs(best_dl) then
          best_id, best_dl = id, dl
        end
      end
    end
  end

  if best_id then
    M.select(best_id)
  end
end

function M.node_at_cursor()
  local win = graph_win()

  if not win then
    return nil
  end

  local pos = vim.api.nvim_win_get_cursor(win)
  local bidx = byte_index[pos[1]]

  if not bidx then
    return nil
  end

  local cell

  for c = 1, #bidx - 1 do
    if pos[2] >= bidx[c] and pos[2] < bidx[c + 1] then
      cell = c
      break
    end
  end

  if not cell then
    return nil
  end

  for id, rect in pairs(M.layout) do
    if pos[1] >= rect.row and pos[1] < rect.row + CARD_H and cell >= rect.col and cell < rect.col + card_w() then
      return id
    end
  end
end

-- Screen-space rect of a card (for the float grow transition).
function M.screen_rect(id)
  local rect = M.layout[id]
  local win = graph_win()

  if not (rect and win) then
    return nil
  end

  local bidx = byte_index[rect.row]
  local byte_col = (bidx and bidx[rect.col] or 0) + 1
  local pos = vim.fn.screenpos(win, rect.row, byte_col)

  if pos.row == 0 then
    return nil
  end

  return { row = pos.row - 1, col = pos.col - 1, width = card_w(), height = CARD_H }
end

local function session_winbar()
  local keys = config_loader.keys("graph")
  local agent = state.format_agent(state.session_agent(), state.session_model())
  return string.format("  [%s]  %%=  %s view  %s read  %s prompt  %s diff  %s agent  %s new session  %s/%s switch  %s help  %s quit  ",
    agent, first_key(keys.view), first_key(keys.read), first_key(keys.prompt_branch), first_key(keys.review_diffs),
    first_key(keys.choose_agent), first_key(keys.new_session), first_key(keys.next_session), first_key(keys.previous_session),
    first_key(keys.help), first_key(keys.close))
end

local function current_session_index()
  local sessions = state.list_sessions()

  for i, sid in ipairs(sessions) do
    if sid == state.current_session then
      return i, sessions
    end
  end

  return 1, sessions
end

local function session_label(session_id, info)
  local seq = info.seq and tostring(info.seq) or session_id:sub(-4)
  local name = info.name or ("Session " .. seq)
  local agent = state.format_agent(info.agent, info.model)
  return vim.fn.strcharpart(name .. " [" .. agent .. "]", 0, SESSION_SIDEBAR_W - 1)
end

local function usage_lines()
  return usage.format()
end

update_usage_widget = function()
  if not (M.session_win and vim.api.nvim_win_is_valid(M.session_win)) then
    if M.usage_win and vim.api.nvim_win_is_valid(M.usage_win) then
      pcall(vim.api.nvim_win_close, M.usage_win, true)
    end
    M.usage_win = nil
    M.usage_buf = nil
    return
  end

  if not (M.usage_buf and vim.api.nvim_buf_is_valid(M.usage_buf)) then
    M.usage_buf = find_named_buf("exocortex://usage") or vim.api.nvim_create_buf(false, true)
    if vim.api.nvim_buf_get_name(M.usage_buf) == "" then
      vim.api.nvim_buf_set_name(M.usage_buf, "exocortex://usage")
    end
    vim.bo[M.usage_buf].swapfile = false
    vim.bo[M.usage_buf].bufhidden = "wipe"
    vim.bo[M.usage_buf].filetype = "exocortex-usage"
  end

  local lines = usage_lines()
  vim.bo[M.usage_buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.usage_buf, 0, -1, false, lines)
  vim.bo[M.usage_buf].modifiable = false

  local width = math.max(18, vim.api.nvim_win_get_width(M.session_win))
  local height = math.min(USAGE_WIDGET_H, math.max(2, vim.api.nvim_win_get_height(M.session_win)))
  local row = math.max(0, vim.api.nvim_win_get_height(M.session_win) - height)
  local opts = {
    relative = "win",
    win = M.session_win,
    row = row,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    title = " usage ",
    title_pos = "center",
    zindex = 50,
    focusable = false,
  }

  if not (M.usage_win and vim.api.nvim_win_is_valid(M.usage_win)) then
    M.usage_win = vim.api.nvim_open_win(M.usage_buf, false, opts)
  else
    pcall(vim.api.nvim_win_set_buf, M.usage_win, M.usage_buf)
    pcall(vim.api.nvim_win_set_config, M.usage_win, opts)
  end

  if M.usage_win and vim.api.nvim_win_is_valid(M.usage_win) then
    vim.wo[M.usage_win].wrap = false
    vim.wo[M.usage_win].linebreak = false
    vim.wo[M.usage_win].number = false
    vim.wo[M.usage_win].relativenumber = false
    vim.wo[M.usage_win].signcolumn = "no"
    vim.wo[M.usage_win].cursorline = false
    vim.wo[M.usage_win].winfixwidth = true
    vim.wo[M.usage_win].winfixheight = true
    vim.wo[M.usage_win].winhl = "NormalFloat:ExocortexUsageMuted,FloatBorder:ExocortexUsageMuted,FloatTitle:ExocortexUsageTitle"
  end
end

local function render_sessions()
  if not (M.session_buf and vim.api.nvim_buf_is_valid(M.session_buf)) then
    return
  end

  local index, sessions = current_session_index()
  local lines = {}

  for i, sid in ipairs(sessions) do
    local info = state.sessions[sid] or {}
    lines[#lines + 1] = session_label(sid, info)
  end

  vim.bo[M.session_buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.session_buf, 0, -1, false, lines)
  vim.bo[M.session_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(M.session_buf, session_ns, 0, -1)

  for i = 1, #sessions do
    local line = i - 1
    vim.api.nvim_buf_set_extmark(M.session_buf, session_ns, line, 0, {
      line_hl_group = i == index and "ExocortexSessionActive" or "ExocortexSession",
    })
  end

  if M.session_win and vim.api.nvim_win_is_valid(M.session_win) then
    local target = math.max(1, index)
    pcall(vim.api.nvim_win_set_cursor, M.session_win, { target, 0 })
  end

  if update_usage_widget then
    pcall(update_usage_widget)
  end
end

local function ensure_session_sidebar()
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    return
  end

  local graph = graph_win()
  if not graph then
    return
  end

  if not (M.session_buf and vim.api.nvim_buf_is_valid(M.session_buf)) then
    M.session_buf = find_named_buf("exocortex://sessions") or vim.api.nvim_create_buf(false, true)
    if vim.api.nvim_buf_get_name(M.session_buf) == "" then
      vim.api.nvim_buf_set_name(M.session_buf, "exocortex://sessions")
    end
    vim.bo[M.session_buf].swapfile = false
    vim.bo[M.session_buf].bufhidden = "wipe"
    vim.bo[M.session_buf].filetype = "exocortex-sessions"
  end

  if not (M.session_win and vim.api.nvim_win_is_valid(M.session_win)) then
    vim.api.nvim_set_current_win(graph)
    vim.cmd("leftabove vsplit")
    M.session_win = vim.api.nvim_get_current_win()
  end

  vim.api.nvim_win_set_buf(M.session_win, M.session_buf)
  vim.api.nvim_win_set_width(M.session_win, SESSION_SIDEBAR_W)
  vim.wo[M.session_win].wrap = false
  vim.wo[M.session_win].number = false
  vim.wo[M.session_win].relativenumber = false
  vim.wo[M.session_win].signcolumn = "no"
  vim.wo[M.session_win].cursorline = true
  vim.wo[M.session_win].numberwidth = 4
  vim.wo[M.session_win].winfixwidth = true
  vim.wo[M.session_win].winbar = nil

  render_sessions()
  if update_usage_widget then
    pcall(update_usage_widget)
  end
  vim.api.nvim_set_current_win(graph)
end

function M.session_changed(what)
  M.selected = nil
  M.render()
  ensure_session_sidebar()
  render_sessions()
  if update_usage_widget then
    pcall(update_usage_widget)
  end

  local win = graph_win()
  if win then
    vim.wo[win].winbar = session_winbar()
  end

  local last = state.order[#state.order]
  if last then M.select(last) end

  vim.notify("exocortex: " .. what .. " " .. state.current_session, vim.log.levels.INFO)
end

local function cycle_session(step)
  local sessions = state.list_sessions()

  if #sessions < 2 then
    vim.notify("exocortex: no other sessions (" .. (state.current_session or "?") .. ")", vim.log.levels.INFO)
    return
  end

  local current_idx = 1

  for i, sid in ipairs(sessions) do
    if sid == state.current_session then
      current_idx = i
      break
    end
  end

  if state.switch_session(sessions[(current_idx - 1 + step) % #sessions + 1]) then
    M.session_changed("switched to session")
  end
end

function M.next_session()
  cycle_session(1)
end

function M.prev_session()
  cycle_session(-1)
end

function M.create_new_session()
  require("exocortex").new_session()
end

-- ---------------------------------------------------------------------------
-- Spinner: re-render while any node is running
-- ---------------------------------------------------------------------------

function M.start_spinner()
  if spin_timer then
    return
  end

  spin_timer = vim.uv.new_timer()
  spin_timer:start(0, 120, vim.schedule_wrap(function()
    local running = false

    for _, node in pairs(state.nodes) do
      if node.status == "running" then
        running = true
        break
      end
    end

    if not running or not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
      local t = spin_timer
      spin_timer = nil
      if t then
        t:stop()
        t:close()
      end
      M.render()
      render_sessions()
      return
    end

    spin_frame = spin_frame % #SPINNER + 1
    M.render()
  end))
end

-- ---------------------------------------------------------------------------
-- Window / keymaps
-- ---------------------------------------------------------------------------

local function restore_return_location()
  if M.return_tab and vim.api.nvim_tabpage_is_valid(M.return_tab) then
    vim.api.nvim_set_current_tabpage(M.return_tab)

    if M.return_win and vim.api.nvim_win_is_valid(M.return_win) then
      vim.api.nvim_set_current_win(M.return_win)
    end

    return true
  end
end

local function close_graph_tab()
  if not pcall(vim.cmd.tabclose) then
    if not restore_return_location() then
      vim.cmd("enew")
    end
  end
end

function M.return_to_code()
  if not pcall(vim.cmd.tabclose) then
    if not restore_return_location() then
      vim.cmd("enew")
    end

    return
  end

  restore_return_location()
end

local function show_help()
  local graph_keys = config_loader.keys("graph")
  local session_keys = config_loader.keys("sessions")
  local diff_keys = config_loader.keys("diff")
  local function pair(a, b) return first_key(a) .. " / " .. first_key(b) end
  local lines = {
    "  exocortex - talk to coding agents in a DAG",
    "",
    "  -- graph navigation ---------------------------------------------",
    string.format("  %-18s parent / child node", pair(graph_keys.parent, graph_keys.child)),
    string.format("  %-18s node below / above", pair(graph_keys.below, graph_keys.above)),
    string.format("  %-18s open node response float", first_key(graph_keys.view)),
    string.format("  %-18s open node response buffer", first_key(graph_keys.read)),
    string.format("  %-18s review node diffs", first_key(graph_keys.review_diffs)),
    string.format("  %-18s open node in Diffview", first_key(graph_keys.diffview)),
    string.format("  %-18s prompt from selected node", first_key(graph_keys.prompt_branch)),
    string.format("  %-18s prompt from a fresh root", first_key(graph_keys.prompt_root)),
    string.format("  %-18s choose session agent", first_key(graph_keys.choose_agent)),
    string.format("  %-18s redraw graph", first_key(graph_keys.redraw)),
    string.format("  %-18s close graph", first_key(graph_keys.close)),
    string.format("  %-18s return to code", first_key(graph_keys.return_to_code)),
    "",
    "  -- sessions -----------------------------------------------------",
    string.format("  %-18s switch session", first_key(session_keys.switch)),
    string.format("  %-18s next / previous session", pair(session_keys.next_session, session_keys.previous_session)),
    string.format("  %-18s new session", first_key(session_keys.new_session)),
    string.format("  %-18s close mutable session", first_key(session_keys.close_session)),
    "  obsidian is read-only and cannot be deleted",
    "",
    "  -- diff viewer --------------------------------------------------",
    string.format("  %-18s accept focused proposal hunk", first_key(diff_keys.accept)),
    string.format("  %-18s skip/reject focused proposal hunk", first_key(diff_keys.skip)),
    string.format("  %-18s undo accept/skip", first_key(diff_keys.undo)),
    string.format("  %-18s focus editable right side", first_key(diff_keys.edit_right)),
    string.format("  %-18s next / previous focused diff", pair(diff_keys.next, diff_keys.previous)),
    string.format("  %-18s next / previous diff from cursor", pair(diff_keys.next_from_cursor, diff_keys.previous_from_cursor)),
    string.format("  %-18s next / previous changed file", pair(diff_keys.next_file, diff_keys.previous_file)),
    string.format("  %-18s next page / previous page inside file", pair(diff_keys.page_down, diff_keys.page_up)),
    string.format("  %-18s put current function at top", first_key(diff_keys.function_to_top)),
    string.format("  %-18s end review", first_key(diff_keys.close)),
    "",
    "  Agents run in isolated git worktrees. Snapshots are proposals stored as git refs.",
    "  Real files change only when you accept hunks or edit the right pane.",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = 0

  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - #lines) / 2) - 1,
    col = math.floor((vim.o.columns - width - 2) / 2),
    width = width + 2,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = " exocortex help ",
    title_pos = "center",
  })

  for _, lhs in ipairs(keymaps.flatten({ graph_keys.close, graph_keys.return_to_code, graph_keys.help, session_keys.close, session_keys.return_to_code })) do
    vim.keymap.set("n", lhs, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, silent = true, nowait = true })
  end
end

local function set_keymaps(buf)
  local function map(lhs, fn, desc)
    keymaps.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc })
  end

  local keys = config_loader.keys("graph")

  map(keys.parent, function() M.move("left") end, "Parent node")
  map(keys.child, function() M.move("right") end, "Child node")
  map(keys.below, function() M.move("down") end, "Node below")
  map(keys.above, function() M.move("up") end, "Node above")
  map(keys.child_alt, function() M.move("right") end, "Child node")
  map(keys.parent_alt, function() M.move("left") end, "Parent node")
  map(keys.select_mouse, function()
    local id = M.node_at_cursor()

    if id then
      M.select(id)
    end
  end, "Select node under mouse")

  map(keys.view, function() require("exocortex").view_selected() end, "View node text")
  map(keys.read, function() require("exocortex").read_selected() end, "Read node response as file")
  map(keys.review_diffs, function() require("exocortex").review_selected() end, "Review node diffs")
  map(keys.diffview, function() require("exocortex").diffview_selected() end, "Open node in Diffview")
  map(keys.prompt_branch, function() require("exocortex").prompt(M.selected) end, "Prompt from selected node")
  map(keys.prompt_root, function() require("exocortex").prompt(nil) end, "Prompt from a fresh root")
  map(keys.choose_agent, function() require("exocortex").choose_agent() end, "Choose agent")
  map(keys.next_session, M.next_session, "Next session")
  map(keys.previous_session, M.prev_session, "Previous session")
  map(keys.new_session, M.create_new_session, "Create new session")
  map(keys.close_session, function() require("exocortex").close_session() end, "Close session")
  map(keys.redraw, M.render, "Redraw graph")
  map(keys.help, show_help, "Help")
  map(keys.return_to_code, function() M.return_to_code() end, "Return to code")
  map(keys.close, close_graph_tab, "Close graph")
end

local function set_session_keymaps(buf)
  local function map(lhs, fn, desc)
    keymaps.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc })
  end

  local keys = config_loader.keys("sessions")

  local function session_under_cursor()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local sessions = state.list_sessions()
    local index = line
    return sessions[index]
  end

  map(keys.switch, function()
    local session_id = session_under_cursor()
    if session_id and session_id ~= state.current_session then
      if state.switch_session(session_id) then
        M.session_changed("switched to session")
      end
    end

    local win = graph_win()
    if win then
      vim.api.nvim_set_current_win(win)
    end
  end, "Switch session")
  map(keys.next_session, M.next_session, "Next session")
  map(keys.previous_session, M.prev_session, "Previous session")
  map(keys.new_session, M.create_new_session, "Create new session")
  map(keys.close_session, function() require("exocortex").close_session() end, "Close session")
  map(keys.help, show_help, "Help")
  map(keys.close, close_graph_tab, "Close graph")
  map(keys.return_to_code, function() M.return_to_code() end, "Return to code")
end

function M.open()
  M.remember_return_location()

  local existing_win = M.buf and vim.api.nvim_buf_is_valid(M.buf) and vim.fn.bufwinid(M.buf) or -1

  if existing_win ~= -1 then
    M.graph_win = existing_win
    vim.api.nvim_set_current_win(existing_win)
    ensure_session_sidebar()
    if M.session_buf and vim.api.nvim_buf_is_valid(M.session_buf) then
      set_session_keymaps(M.session_buf)
    end
    M.render()
    return
  end

  vim.cmd("tabnew")
  local placeholder = vim.api.nvim_get_current_buf()

  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    M.buf = find_named_buf("exocortex://graph") or vim.api.nvim_create_buf(false, true)
    if vim.api.nvim_buf_get_name(M.buf) == "" then
      vim.api.nvim_buf_set_name(M.buf, "exocortex://graph")
    end
    vim.bo[M.buf].swapfile = false
    vim.bo[M.buf].filetype = "exocortex"
  end

  set_keymaps(M.buf)

  vim.api.nvim_win_set_buf(0, M.buf)
  M.graph_win = vim.api.nvim_get_current_win()

  if vim.api.nvim_buf_is_valid(placeholder)
    and placeholder ~= M.buf
    and vim.api.nvim_buf_get_name(placeholder) == "" then
    pcall(vim.api.nvim_buf_delete, placeholder, { force = true })
  end

  local win = vim.api.nvim_get_current_win()
  vim.wo[win].wrap = false
  vim.wo[win].number = true
  vim.wo[win].relativenumber = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].sidescrolloff = 8
  vim.wo[win].scrolloff = 4
  vim.wo[win].virtualedit = "all"
  vim.wo[win].winbar = session_winbar()

  ensure_session_sidebar()
  if M.session_buf and vim.api.nvim_buf_is_valid(M.session_buf) then
    set_session_keymaps(M.session_buf)
  end
  M.render()

  if M.selected and M.layout[M.selected] then
    cursor_to(M.selected)
  else
    local last = state.order[#state.order]

    if last then
      M.select(last)
    end
  end
end

function M.restore_win(win)
  if not (win and vim.api.nvim_win_is_valid(win) and M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    return
  end

  M.graph_win = win
  vim.api.nvim_win_set_buf(win, M.buf)
  vim.wo[win].wrap = false
  vim.wo[win].number = true
  vim.wo[win].relativenumber = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].sidescrolloff = 8
  vim.wo[win].scrolloff = 4
  vim.wo[win].virtualedit = "all"
  vim.wo[win].winbar = session_winbar()
  ensure_session_sidebar()
  if M.session_buf and vim.api.nvim_buf_is_valid(M.session_buf) then
    set_session_keymaps(M.session_buf)
  end
  M.render()
end

return M
