-- exocortex: talk to coding agents in a DAG. Each node is one prompt/response
-- turn; branching from a node forks both the conversation and the file tree
-- (every node's resulting tree is a hidden git commit, and each run happens
-- in a throwaway git worktree materialized from the parent's snapshot).

local state = require("exocortex.state")
local git = require("exocortex.git")
local agents = require("exocortex.agents")
local graph = require("exocortex.graph")
local view = require("exocortex.view")
local review = require("exocortex.review")

local M = {}

M.config = {
  agent = nil,          -- default: first available adapter
  context_chars = 4000, -- per-ancestor response replayed as branch context
  terminal_lines = 50,  -- last N lines of terminal output appended to every prompt
}

-- ---------------------------------------------------------------------------
-- Terminal context
-- ---------------------------------------------------------------------------

-- Read the last N lines from whichever terminal buffer is currently visible
-- (or most recently active). Returns nil when no terminal is open.
local function get_terminal_context()
  local max = M.config.terminal_lines
  if not max or max <= 0 then return nil end

  local best_buf  = nil
  local best_tick = -1

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
      local tick = vim.api.nvim_buf_get_changedtick(buf)
      -- Visible terminal wins over a hidden one regardless of changedtick.
      if vim.fn.bufwinid(buf) ~= -1 then tick = tick + 1e9 end
      if tick > best_tick then
        best_tick = tick
        best_buf  = buf
      end
    end
  end

  if not best_buf then return nil end

  local n     = vim.api.nvim_buf_line_count(best_buf)
  local lines = vim.api.nvim_buf_get_lines(best_buf, math.max(0, n - max), n, false)

  -- Drop trailing blank lines.
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    table.remove(lines)
  end

  return #lines > 0 and table.concat(lines, "\n") or nil
end

-- ---------------------------------------------------------------------------
-- Prompt running
-- ---------------------------------------------------------------------------

-- Agents are stateless across nodes in v1: branching replays the path-to-root
-- transcript as context, which works identically for every CLI.
local function build_prompt(parent_id, prompt)
  local parts = {}

  if parent_id then
    table.insert(parts, "You are continuing an existing conversation. Earlier turns, oldest first:")

    for _, node in ipairs(state.path_to_root(parent_id)) do
      table.insert(parts, "\n--- user ---\n" .. (node.prompt or ""))

      local response = node.response or ""
      if #response > M.config.context_chars then
        response = response:sub(1, M.config.context_chars) .. "\n[...truncated...]"
      end

      table.insert(parts, "\n--- assistant ---\n" .. response)
    end

    table.insert(parts, "\n--- new user request ---\n" .. prompt)
  else
    table.insert(parts, prompt)
  end

  local term = get_terminal_context()
  if term then
    table.insert(parts, "\n\n--- terminal (last " .. M.config.terminal_lines .. " lines) ---\n" .. term)
  end

  return table.concat(parts, "\n")
end

local function fail_node(node, err)
  node.status = "error"
  node.stat = (err or "unknown error"):gsub("\n.*", ""):sub(1, 80)
  node.response = err
  state.save()
  graph.render()
  vim.notify("exocortex: " .. node.id .. " failed: " .. (err or "?"), vim.log.levels.ERROR)
end

function M.run_prompt(parent_id, prompt)
  local root = state.root_dir
  local agent = state.session_agent() or M.config.agent

  if not root then
    vim.notify("exocortex: open the graph first (:Exocortex)", vim.log.levels.ERROR)
    return
  end

  if not agent then
    vim.notify("exocortex: no agent CLI found (looked for: claude, codex, gemini)", vim.log.levels.ERROR)
    return
  end

  local parent = parent_id and state.nodes[parent_id] or nil

  if parent_id and not parent then
    vim.notify("exocortex: unknown parent node " .. parent_id, vim.log.levels.ERROR)
    return
  end

  if parent and parent.status ~= "done" then
    vim.notify("exocortex: wait for the parent node to finish", vim.log.levels.WARN)
    return
  end

  -- Base tree: parent's snapshot, or the current working tree for a root.
  local base, base_err

  if parent then
    base = parent.snapshot
  else
    base, base_err = git.snapshot(root)
  end

  if not base then
    vim.notify("exocortex: snapshot failed: " .. (base_err or "?"), vim.log.levels.ERROR)
    return
  end

  local node = state.new_node(parent_id, prompt, agent)
  node.base = base
  graph.select(node.id)
  graph.start_spinner()

  local worktree, wt_err = git.worktree_add(root, base)

  if not worktree then
    fail_node(node, "worktree: " .. (wt_err or "?"))
    return
  end

  agents.run(agent, build_prompt(parent_id, prompt), worktree, function(response, agent_err)
    if agent_err then
      git.worktree_remove(root, worktree)
      fail_node(node, agent_err)
      return
    end

    local sha, snap_err = git.snapshot(worktree, base)
    git.worktree_remove(root, worktree)

    if not sha then
      fail_node(node, "snapshot: " .. (snap_err or "?"))
      return
    end

    node.response = response
    node.snapshot = sha
    node.files = git.changed_files(root, base, sha)
    node.stat = git.shortstat(root, base, sha)
    node.status = "done"
    git.update_ref(root, state.ref_name(node.id), sha)
    state.save()
    graph.render()
    vim.notify("exocortex: " .. node.id .. " done (" .. node.stat .. ")", vim.log.levels.INFO)
  end)
end

-- ---------------------------------------------------------------------------
-- Commands invoked from the graph
-- ---------------------------------------------------------------------------

local function session_agent_choices()
  local available = {}
  for _, name in ipairs(agents.available()) do
    available[name] = true
  end

  local names = {}
  for _, name in ipairs({ "claude", "codex", "gemini" }) do
    if available[name] then
      table.insert(names, name)
    end
  end

  return names
end

local function prompt_for_session_agent(on_choice)
  local names = session_agent_choices()

  if #names == 0 then
    vim.notify("exocortex: no agent CLI found (looked for: claude, codex, gemini)", vim.log.levels.ERROR)
    return
  end

  vim.ui.select(names, {
    prompt = "exocortex: choose model for this session",
    format_item = function(name) return name end,
  }, function(choice)
    if choice then
      M.config.agent = choice
      state.set_session_agent(choice)
      vim.notify("exocortex: agent set to " .. choice, vim.log.levels.INFO)
      on_choice(choice)
    end
  end)
end

function M.prompt(parent_id)
  local hint = parent_id and (" from " .. parent_id) or " (new root)"

  local function do_input(agent_name)
    vim.ui.input({ prompt = "exocortex" .. hint .. " [" .. agent_name .. "] > " }, function(input)
      if input and vim.trim(input) ~= "" then
        M.config.agent = agent_name
        state.set_session_agent(agent_name)
        M.run_prompt(parent_id, vim.trim(input))
      end
    end)
  end

  local current = state.session_agent()

  if state.is_empty() and not current then
    prompt_for_session_agent(do_input)
    return
  end

  if current then
    do_input(current)
    return
  end

  local names = agents.available()
  do_input(names[1] or M.config.agent or "?")
end

local function selected_node()
  local node = graph.selected and state.nodes[graph.selected]

  if not node then
    vim.notify("exocortex: no node selected", vim.log.levels.WARN)
  end

  return node
end

local function is_graph_buf(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return false
  end

  if graph.buf and buf == graph.buf then
    return true
  end

  if graph.session_buf and buf == graph.session_buf then
    return true
  end

  local ft = vim.bo[buf].filetype
  return ft == "exocortex" or ft == "exocortex-sessions"
end

local function is_workspace_win(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end

  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if is_graph_buf(buf) then
    return false
  end

  local bt = vim.bo[buf].buftype
  return bt == "" or bt == "terminal"
end

local function tabpage_winlayout(tab)
  local current = vim.api.nvim_get_current_tabpage()

  if tab ~= current then
    vim.api.nvim_set_current_tabpage(tab)
  end

  local layout = vim.fn.winlayout()

  if tab ~= current then
    vim.api.nvim_set_current_tabpage(current)
  end

  return layout
end

local function capture_workspace_tab(tab)
  if not (tab and vim.api.nvim_tabpage_is_valid(tab)) then
    return nil
  end

  local wins = vim.api.nvim_tabpage_list_wins(tab)
  local target = nil
  local state_by_win = {}

  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    state_by_win[win] = {
      buf = buf,
      cursor = vim.api.nvim_win_get_cursor(win),
      width = vim.api.nvim_win_get_width(win),
      height = vim.api.nvim_win_get_height(win),
    }

    if is_workspace_win(win) then
      if vim.bo[buf].buftype == "" then
        target = win
        break
      end

      target = target or win
    end
  end

  if not target then
    return nil
  end

  local layout = tabpage_winlayout(tab)

  return {
    tab = tab,
    current = vim.api.nvim_tabpage_get_win(tab),
    target = target,
    layout = layout,
    wins = state_by_win,
  }
end

local function find_workspace_tab()
  local tabs = vim.api.nvim_list_tabpages()
  local ordered = {}
  local seen = {}
  local alt_idx = vim.fn.tabpagenr("#")
  local alt = alt_idx > 0 and tabs[alt_idx] or nil

  local function add(tab)
    if tab and not seen[tab] then
      seen[tab] = true
      table.insert(ordered, tab)
    end
  end

  add(alt)
  for _, tab in ipairs(tabs) do
    if tab ~= vim.api.nvim_get_current_tabpage() then
      add(tab)
    end
  end

  for _, tab in ipairs(ordered) do
    local captured = capture_workspace_tab(tab)
    if captured then
      return captured
    end
  end
end

local function restore_workspace_leaf(src_win, dst_win, captured)
  local info = captured.wins[src_win]
  if not info then
    return
  end

  if info.buf and vim.api.nvim_buf_is_valid(info.buf) then
    vim.api.nvim_win_set_buf(dst_win, info.buf)
  end

  pcall(vim.api.nvim_win_set_cursor, dst_win, info.cursor)
  pcall(vim.api.nvim_win_set_width, dst_win, info.width)
  pcall(vim.api.nvim_win_set_height, dst_win, info.height)
end

local function clone_workspace_layout(node, win_map, captured)
  if node[1] == "leaf" then
    local src_win = node[2]
    local dst_win = vim.api.nvim_get_current_win()
    win_map[src_win] = dst_win
    restore_workspace_leaf(src_win, dst_win, captured)
    return dst_win
  end

  local edge = clone_workspace_layout(node[2][1], win_map, captured)

  for i = 2, #node[2] do
    vim.api.nvim_set_current_win(edge)
    vim.cmd(node[1] == "row" and "rightbelow vsplit" or "rightbelow split")
    edge = clone_workspace_layout(node[2][i], win_map, captured)
  end

  return edge
end

local function open_response_tab(buf)
  local captured = find_workspace_tab()

  if not captured then
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, buf)
    return
  end

  vim.api.nvim_set_current_tabpage(captured.tab)
  vim.cmd("tabnew")

  local win_map = {}
  clone_workspace_layout(captured.layout, win_map, captured)
  vim.cmd("wincmd =")

  local target = win_map[captured.target] or vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(target)
  vim.api.nvim_win_set_buf(target, buf)
end

function M.read_selected()
  local node = selected_node()
  if not node then return end

  if not node.response or node.response == "" then
    vim.notify("exocortex: node has no response yet", vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_create_buf(true, false)
  local suffix = tostring((vim.uv or vim.loop).hrtime())
  pcall(vim.api.nvim_buf_set_name, buf,
    string.format("exocortex://%s/response-%s.md", node.id, suffix))

  local lines = vim.split(node.response, "\n", { plain = true })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].modified = false

  open_response_tab(buf)

  vim.wo[0].wrap = true
  vim.wo[0].linebreak = true
  vim.wo[0].conceallevel = 2
end

function M.view_selected()
  local node = selected_node()

  if node then
    view.open(node, graph.screen_rect(node.id), state.root_dir)
  end
end

function M.review_selected()
  local node = selected_node()

  if node then
    review.start(node, state.root_dir)
  end
end

function M.diffview_selected()
  local node = selected_node()

  if not node then
    return
  end

  if not (node.base and node.snapshot) then
    vim.notify("exocortex: node has no snapshot yet", vim.log.levels.WARN)
    return
  end

  vim.cmd(string.format("DiffviewOpen %s..%s", node.base, node.snapshot))
end

function M.close_session()
  if not state.root_dir then
    vim.notify("exocortex: open the graph first (:Exocortex)", vim.log.levels.ERROR)
    return
  end

  for _, node in pairs(state.nodes) do
    if node.status == "running" then
      vim.notify("exocortex: wait for running nodes before closing the session", vim.log.levels.WARN)
      return
    end
  end

  local sid = state.current_session or "default"

  if vim.fn.confirm('Close session "' .. sid .. '" and delete its nodes?', "&Yes\n&No", 2) ~= 1 then
    return
  end

  -- Unpin this session's snapshots so git can eventually gc them.
  for _, id in ipairs(state.order) do
    git.delete_ref(state.root_dir, state.ref_name(id))
  end

  state.delete_session(sid)

  local remaining = state.list_sessions()
  state.load(state.root_dir, remaining[1] or "default")
  graph.session_changed('closed "' .. sid .. '", now on session')
end

function M.choose_agent()
  local names = session_agent_choices()

  if #names == 0 then
    vim.notify("exocortex: no agent CLI found on PATH", vim.log.levels.ERROR)
    return
  end

  vim.ui.select(names, { prompt = "exocortex agent" }, function(choice)
    if choice then
      M.config.agent = choice
      state.set_session_agent(choice)
      vim.notify("exocortex: agent set to " .. choice, vim.log.levels.INFO)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

function M.new_session()
  if not state.root_dir then
    vim.notify("exocortex: open the graph first (:Exocortex)", vim.log.levels.ERROR)
    return
  end

  state.new_session()
  graph.session_changed("created session")
end

function M.open()
  local root, err = git.repo_root()

  if not root then
    vim.notify("exocortex: not inside a git repository (" .. (err or "?") .. ")", vim.log.levels.ERROR)
    return
  end

  if root ~= state.root_dir then
    state.load(root, "default")
    graph.selected = nil
  end

  graph.open()
end

-- Colors match the VSCode-dark palette; reapplied on :colorscheme changes.
local function set_highlights()
  vim.api.nvim_set_hl(0, "ExocortexCard", { fg = "#8b919c", bg = "#252526" })
  vim.api.nvim_set_hl(0, "ExocortexTitle", { fg = "#e5e5e5", bg = "#252526", bold = true })
  vim.api.nvim_set_hl(0, "ExocortexRunning", { fg = "#dcdcaa", bg = "#252526" })
  vim.api.nvim_set_hl(0, "ExocortexError", { fg = "#f44747", bg = "#252526" })
  vim.api.nvim_set_hl(0, "ExocortexSelected", { fg = "#ffffff", bg = "#264f78", bold = true })
  vim.api.nvim_set_hl(0, "ExocortexSession", { fg = "#8b919c", bg = "#1e1e1e" })
  vim.api.nvim_set_hl(0, "ExocortexSessionActive", { fg = "#ffffff", bg = "#264f78", bold = true })
end

function M.setup(opts)
  opts = opts or {}

  if opts.adapters then
    agents.adapters = vim.tbl_deep_extend("force", agents.adapters, opts.adapters)
    opts.adapters = nil
  end

  M.config = vim.tbl_deep_extend("force", M.config, opts)

  set_highlights()

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("exocortex", { clear = true }),
    callback = set_highlights,
  })

  vim.api.nvim_create_user_command("Exocortex", M.open, { desc = "Open the exocortex agent graph" })
end

return M
