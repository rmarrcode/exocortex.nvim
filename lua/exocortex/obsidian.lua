-- Mirror finished chats into an Obsidian vault. Each agent node becomes one
-- markdown note; nodes that are connected in the graph view become [[wiki-links]]
-- between the notes, so Obsidian and exocortex can show the same DAG.

local config_loader = require("exocortex.config_loader")
local state = require("exocortex.state")

local M = {}

local function load_config()
  return config_loader.load()
end

function M.obsidian_dir()
  local dir = load_config().OBSIDIAN_DIR
  if not dir or dir == "" then
    return nil
  end
  return vim.fn.expand(dir)
end

function M.session_id()
  local cfg = load_config()
  return (cfg.graph and cfg.graph.obsidian_session) or "obsidian"
end

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
    label = vim.fn.strcharpart(label, 0, 59) .. "..."
  end
  return label
end

local function link(node)
  return string.format("[[%s|%s]]", note_key(node), display_label(node))
end

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
  add("agent: " .. state.format_agent(node.agent, node.model))
  add("status: " .. (node.status or "?"))
  add("created: " .. os.date("%Y-%m-%d %H:%M:%S", node.created or os.time()))
  if node.snapshot then add("snapshot: " .. node.snapshot) end
  add("---")
  add("")
  add("# " .. display_label(node))
  add("")

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

local function parse_frontmatter(lines)
  if lines[1] ~= "---" then
    return {}
  end

  local data = {}
  for i = 2, #lines do
    local line = lines[i]
    if line == "---" then
      break
    end

    local key, value = line:match("^([%w_%-]+):%s*(.*)$")
    if key then
      data[key] = value
    end
  end

  return data
end

local function markdown_title(lines)
  for _, line in ipairs(lines) do
    local title = line:match("^#%s+(.+)$")
    if title then
      return vim.trim(title)
    end
  end
end

local function markdown_section(lines, heading)
  local start_idx

  for i, line in ipairs(lines) do
    if line == "## " .. heading then
      start_idx = i + 1
      break
    end
  end

  if not start_idx then
    return ""
  end

  while start_idx <= #lines and lines[start_idx] == "" do
    start_idx = start_idx + 1
  end

  local out = {}
  for i = start_idx, #lines do
    if lines[i]:match("^##%s+") then
      break
    end
    out[#out + 1] = lines[i]
  end

  while #out > 0 and vim.trim(out[#out]) == "" do
    table.remove(out)
  end

  return table.concat(out, "\n")
end

local function parent_key(lines)
  for _, line in ipairs(lines) do
    if line:match("^%*%*Parent:%*%*") then
      return line:match("%[%[([^%]|#]+)")
    end
  end
end

local function parse_time(value)
  if not value or value == "" then
    return os.time()
  end

  local ok, parsed = pcall(vim.fn.strptime, "%Y-%m-%d %H:%M:%S", value)
  if ok and parsed and parsed > 0 then
    return parsed
  end

  return os.time()
end

function M.load_session_nodes()
  local dir = M.obsidian_dir()
  if not dir then
    return { nodes = {}, order = {}, next_id = 1 }
  end

  local files = vim.fn.globpath(dir, "exocortex-*.md", false, true)
  table.sort(files)

  local nodes = {}
  local by_key = {}
  local parsed = {}

  for _, path in ipairs(files) do
    local lines = vim.fn.readfile(path)
    local frontmatter = parse_frontmatter(lines)
    local key = vim.fn.fnamemodify(path, ":t:r")
    local prompt = markdown_section(lines, "Prompt")
    if prompt == "" then
      prompt = markdown_title(lines) or key
    end

    local node = {
      id = key,
      parent = nil,
      prompt = prompt,
      response = markdown_section(lines, "Response"),
      agent = frontmatter.agent or "?",
      status = frontmatter.status or "done",
      stat = "obsidian " .. (frontmatter.session or "vault"),
      created = parse_time(frontmatter.created),
      session_id = M.session_id(),
      obsidian_key = key,
      obsidian_source_session = frontmatter.session,
      obsidian_source_id = frontmatter.exocortex_id,
      files = {},
    }

    nodes[node.id] = node
    by_key[key] = node
    parsed[#parsed + 1] = { node = node, parent_key = parent_key(lines) }
  end

  for _, item in ipairs(parsed) do
    local parent = item.parent_key and by_key[item.parent_key]
    if parent then
      item.node.parent = parent.id
    end
  end

  table.sort(parsed, function(a, b)
    if a.node.created ~= b.node.created then
      return a.node.created < b.node.created
    end
    return a.node.id < b.node.id
  end)

  local order = {}
  for _, item in ipairs(parsed) do
    order[#order + 1] = item.node.id
  end

  return { nodes = nodes, order = order, next_id = #order + 1 }
end

return M
