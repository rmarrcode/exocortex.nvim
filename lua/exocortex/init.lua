-- exocortex: talk to coding agents in a DAG. Each node is one prompt/response
-- turn. Branching keeps the conversation path, while each run starts from a
-- fresh snapshot of the live checkout and stores its proposal as a hidden git
-- commit.

local state = require("exocortex.state")
local git = require("exocortex.git")
local agents = require("exocortex.agents")
local graph = require("exocortex.graph")
local view = require("exocortex.view")
local review = require("exocortex.review")
local copilot = require("exocortex.copilot")
local obsidian = require("exocortex.obsidian")
local config_loader = require("exocortex.config_loader")
local keymaps = require("exocortex.keymaps")

local M = {}

M.config = vim.tbl_deep_extend("force", {
  agent = nil,
  model = nil,
  copilot_model = nil,
  context_chars = 4000,
  terminal_lines = 50,
  copy_ignored_files = true,
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

local function literal_pattern(text)
  return (text or ""):gsub("(%W)", "%%%1")
end

local function sanitize_context_paths(text, proposal_root)
  if not text or text == "" then return text end

  local sanitized = text

  if state.root_dir and state.root_dir ~= "" then
    sanitized = sanitized:gsub(literal_pattern(state.root_dir), "<live-checkout-forbidden>")
  end

  if proposal_root and proposal_root ~= "" then
    sanitized = sanitized:gsub(literal_pattern(proposal_root), "<proposal-worktree>")
  end

  return sanitized
end

-- ---------------------------------------------------------------------------
-- Prompt running
-- ---------------------------------------------------------------------------

-- Agents are stateless across nodes in v1: branching replays the path-to-root
-- transcript as context, which works identically for every CLI.
local function build_prompt(parent_id, prompt, proposal_root)
  local parts = {
    "You are running in an isolated proposal worktree.",
    "The only writable project root is: " .. (proposal_root or "<current working directory>"),
    "Use relative paths, or absolute paths under that proposal root only.",
    "Never edit the original checkout path from terminal history or prior context.",
    "The user will review and explicitly accept proposed hunks later.",
  }

  if M.config.copy_ignored_files ~= false then
    table.insert(parts, "Gitignored files from the live checkout are selectively overlaid into this worktree before you run: small text-like files are copied at their normal relative paths, while large or binary ignored directories may instead contain `EXOCORTEX_IGNORED_INDEX.txt` summary files.")
    table.insert(parts, "Treat copied gitignored files and generated ignored-directory summaries as read-only reference material unless the user explicitly asks to modify them; ignored-file edits are not part of proposal review.")
  end

  if parent_id then
    table.insert(parts, "You are continuing an existing conversation. Earlier turns, oldest first:")
    table.insert(parts, "The code files come from the current checkout snapshot, not from an earlier node snapshot.")

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

  local term = sanitize_context_paths(get_terminal_context(), proposal_root)
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

local function fail_node(node, err, response)
  node.status = "error"
  node.stat = (err or "unknown error"):gsub("\n.*", ""):sub(1, 80)
  if response and response ~= "" then
    node.response = err .. "\n\n--- agent response ---\n" .. response
  else
    node.response = err
  end
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

local function format_changed_file_summary(files)
  if not files or #files == 0 then return "" end

  local parts = {}
  local limit = math.min(#files, 8)

  for i = 1, limit do
    local file = files[i]
    parts[#parts + 1] = (file.status or "?") .. " " .. (file.path or "?")
  end

  if #files > limit then
    parts[#parts + 1] = string.format("...and %d more", #files - limit)
  end

  return table.concat(parts, ", ")
end

local function guard_live_worktree(node, root, live_start_sha, response, on_clean)
  node.stat = "checking live worktree"
  save_node(node)
  render_if_current(node)

  git.snapshot_async(root, nil, function(live_sha, live_err)
    if not live_sha then
      fail_node(node, "live-worktree guard: " .. (live_err or "?"), response)
      return
    end

    git.changed_files_async(root, live_start_sha, live_sha, function(files, files_err)
      if files_err then
        fail_node(node, "live-worktree guard diff: " .. files_err, response)
        return
      end

      if files and #files > 0 then
        node.workspace_snapshot = live_sha
        node.live_start_snapshot = live_start_sha
        node.workspace_files = files

        local detail = format_changed_file_summary(files)
        local message = "agent modified the live worktree outside the proposal"
        if detail ~= "" then
          message = message .. ": " .. detail
        end
        message = message .. ". The node was stopped so those changes are not mistaken for a reviewable proposal."

        fail_node(node, message, response)
        return
      end

      on_clean()
    end)
  end)
end

function M.run_prompt(parent_id, prompt)
  local root = state.root_dir
  local agent = state.session_agent() or M.config.agent
  local model = state.session_model() or M.config.model

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
      model = nil
      M.config.agent = fallback
      M.config.model = nil
      state.set_session_agent(fallback)
      state.set_session_model(nil)
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

  if parent and parent.status == "running" then
    vim.notify("exocortex: wait for the parent node to finish", vim.log.levels.WARN)
    return
  end

  local node, node_err = state.new_node(parent_id, prompt, agent)
  if not node then
    vim.notify("exocortex: " .. (node_err or "could not create node"), vim.log.levels.WARN)
    return
  end

  local ref_name = state.ref_name(node.id)
  node.stat = "snapshotting current code"
  if graph.bar_nodes then
    graph.bar_nodes[(node.session_id or "default") .. ":" .. node.id] = true
  end
  graph.select(node.id)
  graph.start_spinner()

  local function start_agent(base, live_start_sha)
    node.base = base
    node.live_start_snapshot = live_start_sha
    node.stat = "preparing worktree"
    save_node(node)
    render_if_current(node)

    git.worktree_add_async(root, base, function(worktree, wt_err)
      if not worktree then
        fail_node(node, "worktree: " .. (wt_err or "?"))
        return
      end

      local function run_agent_in_worktree()
        node.stat = "running"
        save_node(node)
        render_if_current(node)

        agents.run(agent, model, build_prompt(parent_id, prompt, worktree), worktree, function(response, agent_err)
          if agent_err then
            git.worktree_remove_async(root, worktree)
            fail_node(node, agent_err)
            return
          end

          guard_live_worktree(node, root, live_start_sha, response, function()
            node.stat = "saving snapshot"
            save_node(node)
            render_if_current(node)

            git.snapshot_async(worktree, base, function(sha, snap_err)
              git.worktree_remove_async(root, worktree)

              if not sha then
                fail_node(node, "snapshot: " .. (snap_err or "?"), response)
                return
              end

              finish_worktree_snapshot(node, root, base, ref_name, response, sha)
            end)
          end)
        end)
      end

      if M.config.copy_ignored_files == false then
        run_agent_in_worktree()
        return
      end

      node.stat = "copying ignored files"
      save_node(node)
      render_if_current(node)

      git.copy_ignored_files_async(root, worktree, function(copied, copy_err)
        if copied == nil then
          git.worktree_remove_async(root, worktree)
          fail_node(node, "ignored-file overlay: " .. (copy_err or "?"))
          return
        end

        run_agent_in_worktree()
      end)
    end)
  end

  git.snapshot_async(root, nil, function(live_start_sha, live_err)
    if not live_start_sha then
      fail_node(node, "snapshot: " .. (live_err or "?"))
      return
    end

    start_agent(live_start_sha, live_start_sha)
  end)
end

-- ---------------------------------------------------------------------------
-- Commands invoked from the graph
-- ---------------------------------------------------------------------------

local function apply_session_choice(agent_name, model_name)
  M.config.agent = agent_name
  M.config.model = model_name
  state.set_session_agent(agent_name)
  state.set_session_model(model_name)
end

local function session_agent_choices()
  local available = {}
  for _, name in ipairs(agents.available()) do
    available[name] = true
  end

  local names = {}
  for _, name in ipairs({ "codex", "claude", "antigravity", "aider" }) do
    if available[name] then
      table.insert(names, name)
    end
  end

  return names
end

-- Model lists match what each CLI shows in its own interactive picker.
-- Effort levels are encoded into the model string as "model|effort" and
-- split back out by each adapter's cmd() function.
local AGENT_MODELS = {
  claude = {
    { id = nil,                  label = "Default (recommended)  Sonnet 4.6 · Efficient for routine tasks" },
    { id = "claude-sonnet-4-6",  label = "Sonnet                Sonnet 4.6 · Efficient for routine tasks" },
    { id = "claude-opus-4-8",    label = "Opus                  Opus 4.8 · Best for everyday, complex tasks" },
    { id = "claude-haiku-4-5",   label = "Haiku                 Haiku 4.5 · Fastest for quick answers" },
  },
  codex = {
    { id = "gpt-5.5",      label = "gpt-5.5 (default)   Frontier model for complex coding, research, and real-world work" },
    { id = "gpt-5.4",      label = "gpt-5.4             Strong model for everyday coding" },
    { id = "gpt-5.4-mini", label = "gpt-5.4-mini        Small, fast, and cost-efficient model for simpler coding tasks" },
  },
  antigravity = {
    { id = "gpt-5.5",      label = "gpt-5.5 (default)   Frontier model for complex coding, research, and real-world work" },
    { id = "gpt-5.4",      label = "gpt-5.4             Strong model for everyday coding" },
    { id = "gpt-5.4-mini", label = "gpt-5.4-mini        Small, fast, and cost-efficient model for simpler coding tasks" },
  },
  aider = {
    { id = nil,                label = "(default)" },
    { id = "ollama/codellama", label = "codellama (local)" },
    { id = "ollama/llama3.2",  label = "llama3.2 (local)" },
  },
}

-- Agents whose models support a reasoning / effort level as a second step.
local AGENT_EFFORTS = {
  codex = nil,
  antigravity = {
    { id = "low",        label = "Low         Fast responses with lighter reasoning" },
    { id = "medium",     label = "Medium      Balances speed and reasoning depth for everyday tasks (default)" },
    { id = "high",       label = "High        Greater reasoning depth for complex problems" },
    { id = "extra-high", label = "Extra high  Extra high reasoning depth for complex problems" },
  },
}

local CUSTOM_LABEL = "other (type model id)..."

local function prompt_for_session_model(agent_name, on_choice)
  local options = AGENT_MODELS[agent_name] or {}
  local items = vim.list_extend({ unpack(options) }, { { id = nil, label = CUSTOM_LABEL } })

  vim.ui.select(items, {
    prompt = "exocortex: model for " .. agent_name,
    format_item = function(m) return m.label end,
  }, function(model_choice)
    if model_choice == nil then return end

    if model_choice.label == CUSTOM_LABEL then
      vim.ui.input({
        prompt = "exocortex model id > ",
        default = state.session_model() or M.config.model or "",
      }, function(input)
        if input == nil then return end
        local m = vim.trim(input)
        on_choice(m ~= "" and m or nil)
      end)
      return
    end

    local efforts = AGENT_EFFORTS[agent_name]
    if efforts and model_choice.id ~= nil then
      vim.ui.select(efforts, {
        prompt = "exocortex: reasoning level for " .. model_choice.id,
        format_item = function(e) return e.label end,
      }, function(effort_choice)
        if effort_choice == nil then return end
        -- Encode as "model|effort" so the adapter can split them apart.
        on_choice(model_choice.id .. "|" .. effort_choice.id)
      end)
    else
      on_choice(model_choice.id)
    end
  end)
end

local function prompt_for_session_agent(on_choice)
  local names = session_agent_choices()

  if #names == 0 then
    vim.notify("exocortex: no agent CLI found (looked for: claude, agy, codex, aider)", vim.log.levels.ERROR)
    return
  end

  vim.ui.select(names, {
    prompt = "exocortex: choose agent for this session",
    format_item = function(name) return name end,
  }, function(choice)
    if choice then
      prompt_for_session_model(choice, function(model)
        apply_session_choice(choice, model)
        local suffix = model and (" / " .. model) or ""
        vim.notify("exocortex: agent set to " .. choice .. suffix, vim.log.levels.INFO)
        if on_choice then
          on_choice(choice, model)
        end
      end)
    end
  end)
end

local function open_prompt_editor(parent_id, agent_name, model_name)
  local suffix = model_name and (agent_name .. "/" .. model_name) or agent_name
  local title = parent_id and (" exocortex from " .. parent_id .. " ") or " exocortex new root "
  local footer = "  Ctrl-s submit  Ctrl-q/Esc cancel  "
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].swapfile = false

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })

  local width = math.min(100, math.max(48, vim.o.columns - 12))
  local height = math.min(18, math.max(8, vim.o.lines - 8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title .. "[" .. suffix .. "] ",
    title_pos = "center",
    footer = footer,
    footer_pos = "right",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = true
  vim.wo[win].relativenumber = true

  local closed = false

  local function close()
    if closed then
      return
    end

    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    elseif vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function submit()
    if closed or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local prompt = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
    if prompt == "" then
      vim.notify("exocortex: prompt is empty", vim.log.levels.WARN)
      return
    end

    close()
    apply_session_choice(agent_name, model_name)
    M.run_prompt(parent_id, prompt)
  end

  keymaps.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, silent = true, nowait = true, desc = "Submit prompt" })
  keymaps.set({ "n", "i" }, "<C-q>", close, { buffer = buf, silent = true, nowait = true, desc = "Cancel prompt" })
  keymaps.set("n", "<Esc>", close, { buffer = buf, silent = true, nowait = true, desc = "Cancel prompt" })

  vim.cmd("startinsert")
end

function M.prompt(parent_id)
  if state.is_read_only_session() then
    vim.notify("exocortex: obsidian session is read-only", vim.log.levels.WARN)
    return
  end

  local function do_input(agent_name, model_name)
    open_prompt_editor(parent_id, agent_name, model_name)
  end

  local current = state.session_agent() or M.config.agent
  local current_model = state.session_model() or M.config.model

  if not current then
    prompt_for_session_agent(do_input)
    return
  end

  if not current_model then
    prompt_for_session_model(current, function(model)
      do_input(current, model)
    end)
    return
  end

  do_input(current, current_model)
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

local function open_copilot_from_terminal()
  vim.schedule(function()
    if vim.api.nvim_get_mode().mode == "t" then
      vim.cmd("stopinsert")
    end
    require("exocortex").open_copilot()
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
  keymaps.set("t", keys.terminal_open_copilot, open_copilot_from_terminal, {
    buffer = buf,
    silent = true,
    nowait = true,
    desc = "Open Copilot settings",
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
  return bt == ""
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
    if node.workspace_snapshot and not node.snapshot then
      vim.notify("exocortex: live worktree was modified; use D to inspect the leaked diff, then restore or keep it manually", vim.log.levels.WARN)
      return
    end

    review.start(node, state.root_dir)
  end
end

function M.diffview_selected()
  local node = selected_node()

  if not node then
    return
  end

  local snapshot = node.snapshot
  if not snapshot and node.workspace_snapshot then
    snapshot = node.workspace_snapshot
    vim.notify("exocortex: showing leaked live-worktree diff; changes already touched the real checkout", vim.log.levels.WARN)
  end

  if not (node.base and snapshot) then
    vim.notify("exocortex: node has no snapshot yet", vim.log.levels.WARN)
    return
  end

  vim.cmd(string.format("DiffviewOpen %s..%s", node.base, snapshot))
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
  prompt_for_session_agent(function() end)
end

function M.open_copilot()
  copilot.open()
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
  vim.api.nvim_set_hl(0, "ExocortexUsageTitle", { fg = "#ffffff", bg = "#1e1e1e", bold = true })
  vim.api.nvim_set_hl(0, "ExocortexUsageMuted", { fg = "#8b919c", bg = "#1e1e1e" })
  vim.api.nvim_set_hl(0, "ExocortexUsageValue", { fg = "#dcdcaa", bg = "#1e1e1e", bold = true })
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
  if M.config.copilot_model ~= nil then
    vim.g.copilot_model = M.config.copilot_model
  end

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
