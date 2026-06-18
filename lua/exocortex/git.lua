-- Git plumbing: tree snapshots on hidden refs, throwaway worktrees, diffs.
-- Snapshots are real commits, so nodes can be diffed/checked out with plain
-- git (or Diffview) and per-hunk accept can use native diff mode.

local M = {}

local function run(dir, args, env)
  local cmd = { "git", "-C", dir }
  vim.list_extend(cmd, args)

  local result = vim.system(cmd, { text = true, env = env }):wait()

  if result.code ~= 0 then
    return nil, vim.trim(result.stderr ~= "" and result.stderr or (result.stdout or "git failed"))
  end

  return vim.trim(result.stdout or "")
end

function M.repo_root(dir)
  return run(dir or assert(vim.uv.cwd()), { "rev-parse", "--show-toplevel" })
end

-- Commit the full contents of `dir` (tracked + untracked, minus ignored)
-- without touching HEAD, the index, or the user's working tree.
function M.snapshot(dir, parent_sha)
  local index = vim.fn.tempname()
  local env = { GIT_INDEX_FILE = index }

  local _, add_err = run(dir, { "add", "-A", "." }, env)

  if add_err then
    os.remove(index)
    return nil, add_err
  end

  local tree, tree_err = run(dir, { "write-tree" }, env)
  os.remove(index)

  if not tree then
    return nil, tree_err
  end

  local args = { "commit-tree", tree, "-m", "exocortex snapshot" }

  if parent_sha then
    vim.list_extend(args, { "-p", parent_sha })
  end

  return run(dir, args)
end

-- Keep node snapshots reachable so gc never prunes them.
function M.update_ref(root, ref_id, sha)
  return run(root, { "update-ref", "refs/exocortex/" .. ref_id, sha })
end

function M.delete_ref(root, ref_id)
  return run(root, { "update-ref", "-d", "refs/exocortex/" .. ref_id })
end

function M.worktree_add(root, sha)
  local dir = vim.fn.tempname()
  local _, err = run(root, { "worktree", "add", "--detach", dir, sha })

  if err then
    return nil, err
  end

  return dir
end

function M.worktree_remove(root, dir)
  run(root, { "worktree", "remove", "--force", dir })
end

function M.changed_files(root, base, sha)
  local out = run(root, { "diff", "--name-status", base, sha })
  local files = {}

  for line in (out or ""):gmatch("[^\n]+") do
    local fields = vim.split(line, "\t")
    local status = (fields[1] or ""):sub(1, 1)
    local path = fields[#fields]

    if status ~= "" and path and path ~= "" then
      table.insert(files, { status = status, path = path })
    end
  end

  return files
end

function M.shortstat(root, base, sha)
  local out = run(root, { "diff", "--shortstat", base, sha })

  if not out or out == "" then
    return "no file changes"
  end

  local files = out:match("(%d+) files? changed") or "0"
  local plus = out:match("(%d+) insertion") or "0"
  local minus = out:match("(%d+) deletion") or "0"

  return string.format("%s file%s  +%s -%s", files, files == "1" and "" or "s", plus, minus)
end

function M.file_at(root, sha, path)
  local result = vim.system({ "git", "-C", root, "show", sha .. ":" .. path }, { text = true }):wait()

  if result.code ~= 0 then
    return {}
  end

  local lines = vim.split(result.stdout or "", "\n")

  if lines[#lines] == "" then
    table.remove(lines)
  end

  return lines
end

return M
