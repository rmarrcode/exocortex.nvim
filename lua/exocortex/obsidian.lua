-- Mirror finished chats into an Obsidian vault. Each agent node becomes one
-- markdown note; nodes that are connected in the graph view (parent/child)
-- become [[wiki-links]] between the notes, so Obsidian's graph view mirrors
-- the exocortex DAG. The target vault comes from OBSIDIAN_DIR in config.lua.

local state = require("exocortex.state")

local M = {}

local function load_config()
  local ok, cfg = pcall(require, "exocortex.config")
  if ok and type(cfg) == "table" then
    return cfg
  end
  return {}
end

-- Resolved on every call so reloading config.lua (e.g. via <F2>, which clears
-- package.loaded.exocortex*) is picked up without restarting nvim.
function M.obsidian_dir()
  local dir = load_config().OBSIDIAN_DIR
  if not dir or dir == "" then
    return nil
  end
  return vim.fn.expand(dir)
end

-- Stable, unique note name for a node so links between notes resolve. Node ids
-- (n1, n2, ...) restart per session, so the session id is part of the key.
local function note_key(node)
  local session = node.session_id or state.current_session or "default"
  return string.format("exocortex-%s-%s", session, node.id)
end

local function display_label(node)
  local label = (node.prompt or node.id):gsub("[%[%]|\r\n]", " "):gsub("%s+", " ")
  label = vim.trim(label)
  if label == "" then
    label = node.id
  end
  if vim.fn.strchars(label) > 60 then
    label = vim.fn.strcharpart(label, 0, 59) .. "…"
  end
  return label
end

local function link(node)
  return string.format("[[%s|%s]]", note_key(node), display_label(node))
end

-- Agent turns only: src nodes carry no prompt/response and are not chats.
local function is_chat(node)
  return node and node.kind ~= "src"
end

local function build_markdown(node)
  local session = node.session_id or state.current_session or "default"
  local lines = {}
  local function add(s) lines[#lines + 1] = s end

  add("---")
  add("exocortex_id: " .. node.id)
  add("session: " .. session)
  add("agent: " .. (node.agent or "?"))
  add("status: " .. (node.status or "?"))
  add("created: " .. os.date("%Y-%m-%d %H:%M:%S", node.created or os.time()))
  if node.snapshot then add("snapshot: " .. node.snapshot) end
  add("---")
  add("")
  add("# " .. display_label(node))
  add("")

  -- Graph links: connect this note to the notes of adjacent graph nodes.
  local parent = node.parent and state.nodes[node.parent]
  if is_chat(parent) then
    add("**Parent:** " .. link(parent))
    add("")
  end

  local kids = {}
  for _, kid in ipairs(state.children(node.id)) do
    if is_chat(kid) then
      kids[#kids + 1] = kid
    end
  end
  if #kids > 0 then
    add("**Children:**")
    for _, kid in ipairs(kids) do
      add("- " .. link(kid))
    end
    add("")
  end

  add("## Prompt")
  add("")
  vim.list_extend(lines, vim.split(node.prompt or "", "\n", { plain = true }))
  add("")
  add("## Response")
  add("")
  vim.list_extend(lines, vim.split(node.response or "", "\n", { plain = true }))
  add("")

  return lines
end

function M.save_node(node)
  if not is_chat(node) then
    return
  end

  local dir = M.obsidian_dir()
  if not dir then
    return
  end

  vim.fn.mkdir(dir, "p")
  vim.fn.writefile(build_markdown(node), dir .. "/" .. note_key(node) .. ".md")
end

-- Called when a node finishes: write the node, and re-write its parent so the
-- parent note gains a child link to this newly-completed node.
function M.on_done(node)
  if not M.obsidian_dir() then
    return
  end

  M.save_node(node)

  local parent = node.parent and state.nodes[node.parent]
  if is_chat(parent) then
    M.save_node(parent)
  end
end

return M

