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
local obsidian = require("exocortex.obsidian")
local config_loader = require("exocortex.config_loader")
local keymaps = require("exocortex.keymaps")

local M = {}

M.config = vim.tbl_deep_extend("force", {
  agent = nil,
  context_chars = 4000,
  terminal_lines = 50,
}, config_loader.load().exocortex or {})

local function get_terminal_label(buf)
  local ok, label = pcall(vim.api.nvim_buf_get_var, buf, "bottom_terminal_label")
  if ok and type(label) == "string" and label ~= "" then
    return label
  end

  local shell = vim.fn.fnamemodify(vim.o.shell, ":t")
  if shell == "" then
    return "terminal"
  end
  return shell
end

-- ---------------------------------------------------------------------------
-- Terminal context
-- ---------------------------------------------------------------------------

-- Read the last N lines from every open terminal buffer. Visible terminals are
-- ordered first, then the rest by recency. Returns nil when no terminal is open.
local function get_terminal_context()
  local max = M.config.terminal_lines
  if not max or max <= 0 then return nil end

  local terminals = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
      local n = vim.api.nvim_buf_line_count(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, math.max(0, n - max), n, false)

      while #lines > 0 and vim.trim(lines[#lines]) == "" do
        table.remove(lines)
      end

      if #lines > 0 then
        table.insert(terminals, {
          buf = buf,
          label = get_terminal_label(buf):gsub("[\r\n]", " "),
          lines = table.concat(lines, "\n"),
          visible = vim.fn.bufwinid(buf) ~= -1,
          tick = vim.api.nvim_buf_get_changedtick(buf),
        })
      end
    end
  end

  if #terminals == 0 then
    return nil
  end

  table.sort(terminals, function(a, b)
    if a.visible ~= b.visible then
      return a.visible
    end
    if a.tick ~= b.tick then
      return a.tick > b.tick
    end
    return a.buf < b.buf
  end)

  local parts = {}
  for _, term in ipairs(terminals) do
    parts[#parts + 1] = string.format("--- terminal: %s (buf %d) ---\n%s", term.label, term.buf, term.lines)
  end

  return table.concat(parts, "\n\n")
end

-- ---------------------------------------------------------------------------
-- Prompt running
-- ---------------------------------------------------------------------------

-- Agents are stateless across nodes in v1: branching replays the path-to-root
-- transcript as context, which works identically for every CLI.
local function build_prompt(parent_id, prompt)
  local parts = {
    "You are running in an isolated proposal worktree. Modify only files under the current working directory.",
    "Do not edit files through absolute paths outside this worktree. The user will review and explicitly accept proposed hunks later.",
  }

  if parent_id then
    table.insert(parts, "You are continuing an existing conversation. Earlier turns, oldest first:")

    for _, node in ipairs(state.path_to_root(parent_id)) do
      if node.kind == "src" then goto continue_build end

      table.insert(parts, "\n--- user ---\n" .. (node.prompt or ""))

      local response = node.response or ""
      if #response > M.config.context_chars then
        response = response:sub(1, M.config.context_chars) .. "\n[...truncated...]"
      end

      table.insert(parts, "\n--- assistant ---\n" .. response)

      ::continue_build::
    end

    table.insert(parts, "\n--- new user request ---\n" .. prompt)
  else
    table.insert(parts, prompt)
  end

  local term = get_terminal_context()
  if term then
    table.insert(parts, "\n\n--- terminals (last " .. M.config.terminal_lines .. " lines each) ---\n" .. term)
  end

  return table.concat(parts, "\n")
end

-- The node may belong to a session the user has since switched away from, so
-- persist to its own session and redraw only when it is in front.
local function save_node(node)
  state.save_session(node.session_id)
end

local function render_if_current(node)
  if node.session_id == state.current_session then
    graph.render()
  end
end

local function session_suffix(node)
  if node.session_id and node.session_id ~= state.current_session then
    return " [" .. node.session_id .. "]"
  end
  return ""
end

local function fail_node(node, err)
  node.status = "error"
  node.stat = (err or "unknown error"):gsub("\n.*", ""):sub(1, 80)
  node.response = err
  save_node(node)
  render_if_current(node)

  if graph.flash_code_win then
    graph.flash_code_win("exocortex: " .. node.id .. " failed")
  end

  vim.notify("exocortex: " .. node.id .. session_suffix(node) .. " failed: " .. (err or "?"), vim.log.levels.ERROR)
end

local function finish_node(node, root, base, ref_name, response, sha, files)
  node.response = response
  node.snapshot = sha
  node.files = files or {}
  node.stat = "updating stats"
  save_node(node)
  render_if_current(node)

  git.shortstat_async(root, base, sha, function(stat, stat_err)
    node.stat = stat or (stat_err and ("stat failed: " .. stat_err:gsub("\n.*", "")) or "no file changes")

    node.status = "done"
    git.update_ref_async(root, ref_name, sha, function(_, ref_err)
      if ref_err then
        vim.notify("exocortex: failed to pin " .. node.id .. ": " .. ref_err, vim.log.levels.WARN)
      end

      graph.unread[node.id] = true
      if graph.bar_nodes then
        graph.bar_nodes[(node.session_id or "default") .. ":" .. node.id] = true
      end
      save_node(node)
      render_if_current(node)
      if graph.refresh_status_bar then graph.refresh_status_bar() end
      pcall(obsidian.on_done, node)

      if graph.flash_code_win then
        graph.flash_code_win("exocortex: " .. node.id .. session_suffix(node) .. " done")
      end

      if graph.flash_tabline then
        graph.flash_tabline()
      end

      vim.notify("exocortex: " .. node.id .. session_suffix(node) .. " done (" .. node.stat .. ")", vim.log.levels.INFO)
    end)
  end)
end

local function finish_worktree_snapshot(node, root, base, ref_name, response, worktree_sha)
  git.changed_files_async(root, base, worktree_sha, function(files, files_err)
    if files_err then
      fail_node(node, "diff: " .. files_err)
      return
    end

    finish_node(node, root, base, ref_name, response, worktree_sha, files or {})
  end)
end

function M.run_prompt(parent_id, prompt)
  local root = state.root_dir
  local agent = state.session_agent() or M.config.agent

  if not root then
    vim.notify("exocortex: open the graph first (:Exocortex)", vim.log.levels.ERROR)
    return
  end

  if state.is_read_only_session() then
    vim.notify("exocortex: obsidian session is read-only", vim.log.levels.WARN)
    return
  end

  local available_agents = agents.available()
  local available = {}
  for _, name in ipairs(available_agents) do
    available[name] = true
  end

  if agent and not available[agent] then
    local fallback = available_agents[1]
    if fallback then
      vim.notify("exocortex: saved agent " .. agent .. " is no longer supported; using " .. fallback, vim.log.levels.WARN)
      agent = fallback
      M.config.agent = fallback
      state.set_session_agent(fallback)
    else
      agent = nil
    end
  end

  if not agent then
    vim.notify("exocortex: no agent CLI found (looked for: claude, agy, codex, aider)", vim.log.levels.ERROR)
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

  local node, node_err = state.new_node(parent_id, prompt, agent)
  if not node then
    vim.notify("exocortex: " .. (node_err or "could not create node"), vim.log.levels.WARN)
    return
  end

  local ref_name = state.ref_name(node.id)
  node.stat = parent and "preparing worktree" or "snapshotting base"
  if graph.bar_nodes then
    graph.bar_nodes[(node.session_id or "default") .. ":" .. node.id] = true
  end
  graph.select(node.id)
  graph.start_spinner()

  local function start_agent(base)
    node.base = base
    node.stat = "preparing worktree"
    save_node(node)
    render_if_current(node)

    git.worktree_add_async(root, base, function(worktree, wt_err)
      if not worktree then
        fail_node(node, "worktree: " .. (wt_err or "?"))
        return
      end

      node.stat = "running"
      save_node(node)
      render_if_current(node)

      agents.run(agent, build_prompt(parent_id, prompt), worktree, function(response, agent_err)
        if agent_err then
          git.worktree_remove_async(root, worktree)
          fail_node(node, agent_err)
          return
        end

        node.stat = "saving snapshot"
        save_node(node)
        render_if_current(node)

        git.snapshot_async(worktree, base, function(sha, snap_err)
          git.worktree_remove_async(root, worktree)

          if not sha then
            fail_node(node, "snapshot: " .. (snap_err or "?"))
            return
          end

          finish_worktree_snapshot(node, root, base, ref_name, response, sha)
        end)
      end)
    end)
  end

  if parent then
    start_agent(parent.snapshot)
    return
  end

  git.snapshot_async(root, nil, function(base, base_err)
    if not base then
      fail_node(node, "snapshot: " .. (base_err or "?"))
      return
    end

    start_agent(base)
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
  for _, name in ipairs({ "claude", "antigravity", "codex", "aider" }) do
    if available[name] then
      table.insert(names, name)
    end
  end

  return names
end

local function prompt_for_session_agent(on_choice)
  local names = session_agent_choices()

  if #names == 0 then
    vim.notify("exocortex: no agent CLI found (looked for: claude, agy, codex, aider)", vim.log.levels.ERROR)
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
  if state.is_read_only_session() then
    vim.notify("exocortex: obsidian session is read-only", vim.log.levels.WARN)
    return
  end

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

  if (state.is_empty() or state.has_only_src()) and not current then
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

local function open_ai_view_from_terminal()
  vim.schedule(function()
    if vim.api.nvim_get_mode().mode == "t" then
      vim.cmd("stopinsert")
    end
    require("exocortex").open()
  end)
end

local function set_terminal_keymaps(buf)
  local keys = config_loader.keys("editor")
  keymaps.set("t", keys.terminal_open_graph, open_ai_view_from_terminal, {
    buffer = buf,
    silent = true,
    nowait = true,
    desc = "Open AI view",
  })
end

local function bring_window_left()
  vim.schedule(function()
    local win = vim.api.nvim_get_current_win()
    if not (win and vim.api.nvim_win_is_valid(win)) then
      return
    end

    if vim.api.nvim_win_get_config(win).relative ~= "" then
      return
    end

    pcall(vim.cmd, "wincmd H")
  end)
end

local open_same_file_right

local function set_file_keymaps(buf)
  if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and not vim.bo[buf].filetype:match("^exocortex") then
    local keys = config_loader.keys("editor")
    keymaps.set("n", keys.open_same_file_right, open_same_file_right, { buffer = buf, silent = true, nowait = true, desc = "Open same file to the right" })
    keymaps.set("n", keys.function_to_top, function() review.function_to_top(vim.api.nvim_get_current_win()) end, { buffer = buf, silent = true, nowait = true, desc = "Put function at top" })
  end
end

open_same_file_right = function()
  local win = vim.api.nvim_get_current_win()
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype:match("^exocortex") then
    return
  end

  local view = vim.fn.winsaveview()
  vim.cmd("rightbelow vsplit")
  local right = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right, buf)
  pcall(vim.fn.winrestview, view)
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

local function capture_workspace_tab(tab)
  if not (tab and vim.api.nvim_tabpage_is_valid(tab)) then
    return nil
  end

  local current = vim.api.nvim_get_current_tabpage()
  if tab ~= current then
    vim.api.nvim_set_current_tabpage(tab)
  end

  local target = nil
  local target_key = nil

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if is_workspace_win(win) then
      local pos = vim.api.nvim_win_get_position(win)
      local key = pos[2] * 1000 + pos[1]

      if not target_key or key < target_key then
        target = win
        target_key = key
      end
    end
  end

  if tab ~= current then
    vim.api.nvim_set_current_tabpage(current)
  end

  if not target then
    return nil
  end

  return { tab = tab, target = target }
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

  add(graph.return_tab)
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

local function open_response_tab(buf)
  local captured = find_workspace_tab()

  if not captured then
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, buf)
    return
  end

  vim.api.nvim_set_current_tabpage(captured.tab)

  if vim.api.nvim_win_is_valid(captured.target) then
    vim.api.nvim_set_current_win(captured.target)
  end

  vim.api.nvim_win_set_buf(0, buf)
end

function M.read_selected()
  local node = selected_node()
  if not node then return end

  if not node.response or node.response == "" then
    vim.notify("exocortex: node has no response yet", vim.log.levels.WARN)
    return
  end

  graph.mark_read(node.id)

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

  local function close_read_view()
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.cmd, "bdelete " .. buf)
    end
  end

  local read_keys = config_loader.keys("node_view")
  keymaps.set("n", read_keys.close, close_read_view, { buffer = buf, silent = true, nowait = true })
  keymaps.set("n", read_keys.return_to_code, close_read_view, { buffer = buf, silent = true, nowait = true })

  open_response_tab(buf)

  vim.wo[0].wrap = true
  vim.wo[0].linebreak = true
  vim.wo[0].conceallevel = 2
end

function M.view_selected()
  local node = selected_node()

  if node then
    graph.mark_read(node.id)
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

  if state.is_protected_session(sid) then
    vim.notify("exocortex: session " .. sid .. " cannot be deleted", vim.log.levels.WARN)
    return
  end

  if vim.fn.confirm('Close session "' .. sid .. '" and delete its nodes?', "&Yes\n&No", 2) ~= 1 then
    return
  end

  -- Unpin this session's snapshots so git can eventually gc them.
  for _, id in ipairs(state.order) do
    git.delete_ref(state.root_dir, state.ref_name(id))
  end

  local deleted, delete_err = state.delete_session(sid)
  if not deleted then
    vim.notify("exocortex: " .. (delete_err or "could not delete session"), vim.log.levels.WARN)
    return
  end

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
  M.create_src_node()
end

function M.create_src_node()
  local root = state.root_dir
  if not root then return end

  local node, node_err = state.new_src_node()
  if not node then
    vim.notify("exocortex: " .. (node_err or "could not create source node"), vim.log.levels.WARN)
    return
  end

  local ref_name = state.ref_name(node.id)
  graph.render()
  graph.select(node.id)
  graph.start_spinner()

  git.snapshot_async(root, nil, function(sha, snap_err)
    if not sha then
      node.status = "error"
      node.stat = snap_err and snap_err:gsub("\n.*", ""):sub(1, 60) or "snapshot failed"
    else
      node.snapshot = sha
      node.status = "done"
      node.stat = sha:sub(1, 7)
      git.update_ref_async(root, ref_name, sha, function() end)
    end
    save_node(node)
    render_if_current(node)
  end)
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

  if state.is_empty() and not state.is_read_only_session() then
    M.create_src_node()
  end
end

-- Colors match the VSCode-dark palette; reapplied on :colorscheme changes.
local function set_highlights()
  vim.api.nvim_set_hl(0, "ExocortexCard", { fg = "#8b919c", bg = "#1f1f1f" })
  vim.api.nvim_set_hl(0, "ExocortexTitle", { fg = "#e5e5e5", bg = "#1f1f1f", bold = true })
  vim.api.nvim_set_hl(0, "ExocortexRunning", { fg = "#dcdcaa", bg = "#1f1f1f" })
  vim.api.nvim_set_hl(0, "ExocortexError", { fg = "#f44747", bg = "#1f1f1f" })
  vim.api.nvim_set_hl(0, "ExocortexSelected", { fg = "#ffffff", bg = "#264f78", bold = true })
  vim.api.nvim_set_hl(0, "ExocortexSession", { fg = "#8b919c", bg = "#1e1e1e" })
  vim.api.nvim_set_hl(0, "ExocortexSessionActive", { fg = "#ffffff", bg = "#264f78", bold = true })
  vim.api.nvim_set_hl(0, "ExocortexFlash", { fg = "#1e1e1e", bg = "#ffcc00", bold = true })
  vim.api.nvim_set_hl(0, "ExocortexSrc", { fg = "#4ec9b0", bg = "#1f1f1f" })
  vim.api.nvim_set_hl(0, "ExocortexSrcTitle", { fg = "#4ec9b0", bg = "#1f1f1f", bold = true })
  vim.api.nvim_set_hl(0, "ExocortexUnread", { fg = "#ff9900", bold = true })
end

function M.setup(opts)
  opts = opts or {}

  if opts.adapters then
    agents.adapters = vim.tbl_deep_extend("force", agents.adapters, opts.adapters)
    opts.adapters = nil
  end

  M.config = vim.tbl_deep_extend("force", M.config, config_loader.load().exocortex or {}, opts)

  set_highlights()

  local augroup = vim.api.nvim_create_augroup("exocortex", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = set_highlights,
  })

  vim.api.nvim_create_autocmd("TermOpen", {
    group = augroup,
    callback = function(args)
      set_terminal_keymaps(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = augroup,
    callback = function(args)
      set_file_keymaps(args.buf)
    end,
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
      set_terminal_keymaps(buf)
    else
      set_file_keymaps(buf)
    end
  end

  vim.api.nvim_create_user_command("Exocortex", M.open, { desc = "Open the exocortex agent graph" })

  keymaps.set({ "n", "t" }, config_loader.keys("editor").move_window_left, bring_window_left, { silent = true, nowait = true, desc = "Move window left" })
end

return M
