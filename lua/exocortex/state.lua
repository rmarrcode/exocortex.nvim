-- Node store for one project, persisted as JSON under stdpath("data")/exocortex.
-- A node is one prompt/response turn: { id, parent, prompt, response, agent,
-- status, base, snapshot, files, stat, created }.

local M = {}
local next_seq

M.nodes = {}
M.order = {}
M.next_id = 1
M.root_dir = nil
M.current_session = nil
M.sessions = {} -- session_id -> metadata (name, created, etc)

local function store_path(session_id)
  local base = vim.fn.stdpath("data") .. "/exocortex/" .. vim.fn.sha256(M.root_dir)

  -- The default session lives at the pre-session path so existing graphs
  -- keep working; extra sessions get their own file under <sha>/.
  if not session_id or session_id == "default" then
    return base .. ".json"
  end

  return base .. "/" .. session_id .. ".json"
end

local function sessions_index_path()
  return vim.fn.stdpath("data") .. "/exocortex/" .. vim.fn.sha256(M.root_dir) .. "_sessions.json"
end

local function load_sessions_index()
  local file = io.open(sessions_index_path(), "r")
  if not file then
    M.sessions = {}
    return
  end

  local ok, data = pcall(vim.json.decode, file:read("*a"))
  file:close()

  if ok and type(data) == "table" then
    M.sessions = data
  else
    M.sessions = {}
  end
end

local function save_sessions_index()
  local path = sessions_index_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  local file = io.open(path, "w")
  if not file then
    return
  end

  file:write(vim.json.encode(M.sessions))
  file:close()
end

function M.load(root_dir, session_id)
  M.root_dir = root_dir
  M.nodes, M.order, M.next_id = {}, {}, 1
  M.current_session = session_id or "default"

  load_sessions_index()

  if not M.sessions[M.current_session] then
    M.sessions[M.current_session] = { created = os.time(), seq = next_seq() }
    save_sessions_index()
  end

  local file = io.open(store_path(M.current_session), "r")
  if not file then
    return
  end

  local ok, data = pcall(vim.json.decode, file:read("*a"))
  file:close()

  if not ok or type(data) ~= "table" then
    return
  end

  M.nodes = data.nodes or {}
  M.order = data.order or {}
  M.next_id = data.next_id or (#M.order + 1)

  -- Nodes that were running when nvim exited can never finish.
  for _, node in pairs(M.nodes) do
    if node.status == "running" then
      node.status = "error"
      node.stat = "interrupted"
    end
  end
end

function M.save()
  local path = store_path(M.current_session)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  local file = io.open(path, "w")
  if not file then
    return
  end

  file:write(vim.json.encode({ nodes = M.nodes, order = M.order, next_id = M.next_id }))
  file:close()
end

-- Session-scoped ref id: node ids (n1, n2, ...) restart per session, so
-- without a prefix two sessions would pin the same refs/exocortex/<id> and
-- unpinned snapshots could be gc'd. The default session keeps bare ids so
-- pre-session refs stay valid.
function M.ref_name(node_id)
  if not M.current_session or M.current_session == "default" then
    return node_id
  end

  return M.current_session .. "/" .. node_id
end

function M.delete_session(session_id)
  os.remove(store_path(session_id))
  M.sessions[session_id] = nil
  save_sessions_index()
end

next_seq = function()
  local max = 0
  for _, s in pairs(M.sessions) do
    if type(s.seq) == "number" and s.seq > max then max = s.seq end
  end
  return max + 1
end

function M.list_sessions()
  load_sessions_index()
  local result = {}
  for session_id in pairs(M.sessions) do
    table.insert(result, session_id)
  end
  table.sort(result, function(a, b)
    local sa = (M.sessions[a] or {}).seq or 0
    local sb = (M.sessions[b] or {}).seq or 0
    if sa ~= sb then return sa < sb end
    return a < b
  end)
  return result
end

function M.new_session()
  local session_id = "session_" .. os.time()
  M.sessions[session_id] = { created = os.time(), seq = next_seq() }
  save_sessions_index()
  M.load(M.root_dir, session_id)
  return session_id
end

function M.switch_session(session_id)
  if not M.sessions[session_id] then
    vim.notify("exocortex: session not found: " .. session_id, vim.log.levels.ERROR)
    return false
  end
  M.load(M.root_dir, session_id)
  return true
end

function M.new_node(parent_id, prompt, agent)
  local id = "n" .. M.next_id
  M.next_id = M.next_id + 1

  local node = {
    id = id,
    parent = parent_id,
    prompt = prompt,
    agent = agent,
    status = "running",
    created = os.time(),
  }

  M.nodes[id] = node
  table.insert(M.order, id)
  M.save()

  return node
end

function M.children(id)
  local kids = {}

  for _, node_id in ipairs(M.order) do
    local node = M.nodes[node_id]

    if node and node.parent == id then
      table.insert(kids, node)
    end
  end

  return kids
end

function M.roots()
  local result = {}

  for _, node_id in ipairs(M.order) do
    local node = M.nodes[node_id]

    if node and not node.parent then
      table.insert(result, node)
    end
  end

  return result
end

function M.path_to_root(id)
  local path = {}
  local node = M.nodes[id]

  while node do
    table.insert(path, 1, node)
    node = node.parent and M.nodes[node.parent] or nil
  end

  return path
end

function M.is_empty()
  return #M.order == 0
end

function M.session_agent()
  local s = M.sessions[M.current_session]
  return s and s.agent
end

function M.set_session_agent(agent)
  local s = M.sessions[M.current_session]
  if not s and M.current_session then
    s = { created = os.time(), seq = next_seq() }
    M.sessions[M.current_session] = s
  end

  if s then
    s.agent = agent
    save_sessions_index()
  end
end

return M
