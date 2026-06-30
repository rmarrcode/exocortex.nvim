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

local function run_async(dir, args, env, on_done)
  local cmd = { "git", "-C", dir }
  vim.list_extend(cmd, args)
  on_done = on_done or function() end

  vim.system(cmd, { text = true, env = env }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        on_done(nil, vim.trim(result.stderr ~= "" and result.stderr or (result.stdout or "git failed")))
        return
      end

      on_done(vim.trim(result.stdout or ""))
    end)
  end)
end

local function run_raw_async(dir, args, env, on_done)
  local cmd = { "git", "-C", dir }
  vim.list_extend(cmd, args)
  on_done = on_done or function() end

  vim.system(cmd, { text = true, env = env }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        on_done(nil, vim.trim(result.stderr ~= "" and result.stderr or (result.stdout or "git failed")))
        return
      end

      on_done(result.stdout or "")
    end)
  end)
end

local function split_nul(out)
  local items = {}
  local start = 1

  while start <= #(out or "") do
    local finish = out:find(string.char(0), start, true)
    if not finish then
      local tail = out:sub(start)
      if tail ~= "" then table.insert(items, tail) end
      break
    end

    if finish > start then
      table.insert(items, out:sub(start, finish - 1))
    end
    start = finish + 1
  end

  return items
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

function M.snapshot_async(dir, parent_sha, on_done)
  local index = vim.fn.tempname()
  local env = { GIT_INDEX_FILE = index }

  run_async(dir, { "add", "-A", "." }, env, function(_, add_err)
    if add_err then
      os.remove(index)
      on_done(nil, add_err)
      return
    end

    run_async(dir, { "write-tree" }, env, function(tree, tree_err)
      os.remove(index)

      if not tree then
        on_done(nil, tree_err)
        return
      end

      local args = { "commit-tree", tree, "-m", "exocortex snapshot" }

      if parent_sha then
        vim.list_extend(args, { "-p", parent_sha })
      end

      run_async(dir, args, nil, on_done)
    end)
  end)
end

-- Keep node snapshots reachable so gc never prunes them.
function M.update_ref(root, ref_id, sha)
  return run(root, { "update-ref", "refs/exocortex/" .. ref_id, sha })
end

function M.update_ref_async(root, ref_id, sha, on_done)
  run_async(root, { "update-ref", "refs/exocortex/" .. ref_id, sha }, nil, on_done)
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

function M.worktree_add_async(root, sha, on_done)
  local dir = vim.fn.tempname()

  run_async(root, { "worktree", "add", "--detach", dir, sha }, nil, function(_, err)
    if err then
      on_done(nil, err)
      return
    end

    on_done(dir)
  end)
end

function M.worktree_remove(root, dir)
  run(root, { "worktree", "remove", "--force", dir })
end

function M.worktree_remove_async(root, dir, on_done)
  run_async(root, { "worktree", "remove", "--force", dir }, nil, on_done)
end

local OVERLAY_COPY_CHUNK = 200
local OVERLAY_MAX_FILE_BYTES = 256 * 1024
local OVERLAY_SUMMARY_NAME = "EXOCORTEX_IGNORED_INDEX.txt"
local OVERLAY_SUMMARY_SAMPLE = 32

local TEXT_EXTENSIONS = {
  [".c"] = true,
  [".cc"] = true,
  [".cfg"] = true,
  [".conf"] = true,
  [".cpp"] = true,
  [".csv"] = true,
  [".env"] = true,
  [".h"] = true,
  [".hpp"] = true,
  [".ini"] = true,
  [".ipynb"] = true,
  [".json"] = true,
  [".jsonl"] = true,
  [".log"] = true,
  [".lua"] = true,
  [".md"] = true,
  [".out"] = true,
  [".py"] = true,
  [".pyi"] = true,
  [".r"] = true,
  [".rst"] = true,
  [".sh"] = true,
  [".sql"] = true,
  [".text"] = true,
  [".tex"] = true,
  [".toml"] = true,
  [".tsv"] = true,
  [".txt"] = true,
  [".xml"] = true,
  [".yaml"] = true,
  [".yml"] = true,
}

local BINARY_EXTENSIONS = {
  [".7z"] = true,
  [".bin"] = true,
  [".bmp"] = true,
  [".ckpt"] = true,
  [".gif"] = true,
  [".jpeg"] = true,
  [".jpg"] = true,
  [".mp3"] = true,
  [".mp4"] = true,
  [".npy"] = true,
  [".npz"] = true,
  [".onnx"] = true,
  [".parquet"] = true,
  [".pdf"] = true,
  [".pickle"] = true,
  [".png"] = true,
  [".pt"] = true,
  [".pth"] = true,
  [".tar"] = true,
  [".tif"] = true,
  [".tiff"] = true,
  [".wav"] = true,
  [".webp"] = true,
  [".zip"] = true,
}

local TEXT_FILENAMES = {
  [".gitignore"] = true,
  [".python-version"] = true,
  ["LICENSE"] = true,
  ["Makefile"] = true,
  ["meta.yaml"] = true,
  ["pyproject.toml"] = true,
  ["requirements.txt"] = true,
}

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function dirname(path)
  return path:match("^(.+)/[^/]+$") or ""
end

local function path_ext(path)
  local ext = path:match("%.[^./]+$")
  return ext and ext:lower() or nil
end

local function is_probably_text(path)
  local name = basename(path)
  if TEXT_FILENAMES[name] then
    return true
  end

  local ext = path_ext(path)
  if ext and BINARY_EXTENSIONS[ext] then
    return false
  end

  return ext ~= nil and TEXT_EXTENSIONS[ext] or false
end

local function ensure_dir(path)
  if path and path ~= "" then
    vim.fn.mkdir(path, "p")
  end
end

local function add_summary(summary_by_dir, path, reason)
  local dir = dirname(path)
  local entry = summary_by_dir[dir]

  if not entry then
    entry = { count = 0, samples = {}, reasons = {} }
    summary_by_dir[dir] = entry
  end

  entry.count = entry.count + 1
  entry.reasons[reason] = (entry.reasons[reason] or 0) + 1

  if #entry.samples < OVERLAY_SUMMARY_SAMPLE then
    table.insert(entry.samples, basename(path))
  end
end

local function write_summary_files(dest, summary_by_dir)
  local dirs = {}
  for dir in pairs(summary_by_dir) do
    table.insert(dirs, dir)
  end
  table.sort(dirs)

  for _, dir in ipairs(dirs) do
    local entry = summary_by_dir[dir]
    local target_dir = dir ~= "" and (dest .. "/" .. dir) or dest
    ensure_dir(target_dir)

    local lines = {
      "This ignored directory was only partially mirrored into the Exocortex proposal worktree.",
      "Small text-like files were copied directly; large or binary entries were summarized instead.",
      string.format("Skipped entries: %d", entry.count),
      "",
      "Reason counts:",
    }

    local reasons = {}
    for reason in pairs(entry.reasons) do
      table.insert(reasons, reason)
    end
    table.sort(reasons)

    for _, reason in ipairs(reasons) do
      table.insert(lines, string.format("- %s: %d", reason, entry.reasons[reason]))
    end

    if #entry.samples > 0 then
      table.sort(entry.samples)
      table.insert(lines, "")
      table.insert(lines, "Sample skipped entries:")
      for _, sample in ipairs(entry.samples) do
        table.insert(lines, "- " .. sample)
      end
    end

    local f, err = io.open(target_dir .. "/" .. OVERLAY_SUMMARY_NAME, "w")
    if not f then
      return nil, err or "failed to write ignored summary"
    end

    f:write(table.concat(lines, "\n"))
    f:write("\n")
    f:close()
  end

  return true
end

local function copy_ignored_chunk(root, dest, files, index, on_done)
  if index > #files then
    on_done(#files)
    return
  end

  local args = { "cp", "-a", "--parents", "-t", dest, "--" }
  local copied = 0

  while index <= #files and copied < OVERLAY_COPY_CHUNK do
    table.insert(args, files[index])
    index = index + 1
    copied = copied + 1
  end

  vim.system(args, { text = true, cwd = root }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        on_done(nil, vim.trim(result.stderr ~= "" and result.stderr or (result.stdout or "copy failed")))
        return
      end

      copy_ignored_chunk(root, dest, files, index, on_done)
    end)
  end)
end

function M.copy_ignored_files_async(root, dest, on_done)
  on_done = on_done or function() end
  local uv = vim.uv or vim.loop

  run_raw_async(root, { "ls-files", "--others", "--ignored", "--exclude-standard", "-z" }, nil, function(out, err)
    if err then
      on_done(nil, err)
      return
    end

    local files = split_nul(out)
    if #files == 0 then
      on_done(0)
      return
    end

    local copy_files = {}
    local summary_by_dir = {}

    for _, path in ipairs(files) do
      local full = root .. "/" .. path
      local stat = uv.fs_stat(full)
      local parent = dirname(path)
      if parent ~= "" then
        ensure_dir(dest .. "/" .. parent)
      end

      if not stat or stat.type ~= "file" then
        add_summary(summary_by_dir, path, "unreadable")
      elseif stat.size > OVERLAY_MAX_FILE_BYTES then
        add_summary(summary_by_dir, path, "large")
      elseif not is_probably_text(path) then
        add_summary(summary_by_dir, path, "binary-or-unknown")
      else
        table.insert(copy_files, path)
      end
    end

    local ok, write_err = write_summary_files(dest, summary_by_dir)
    if not ok then
      on_done(nil, write_err)
      return
    end

    if #copy_files == 0 then
      on_done(0)
      return
    end

    copy_ignored_chunk(root, dest, copy_files, 1, on_done)
  end)
end

local function parse_changed_files(out)
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

local function parse_shortstat(out)
  if not out or out == "" then
    return "no file changes"
  end

  local files = out:match("(%d+) files? changed") or "0"
  local plus = out:match("(%d+) insertion") or "0"
  local minus = out:match("(%d+) deletion") or "0"

  return string.format("%s file%s  +%s -%s", files, files == "1" and "" or "s", plus, minus)
end

function M.changed_files(root, base, sha)
  local out = run(root, { "diff", "--name-status", base, sha })
  return parse_changed_files(out)
end

function M.changed_files_async(root, base, sha, on_done)
  run_async(root, { "diff", "--name-status", base, sha }, nil, function(out, err)
    if err then
      on_done(nil, err)
      return
    end

    on_done(parse_changed_files(out))
  end)
end

function M.shortstat(root, base, sha)
  local out = run(root, { "diff", "--shortstat", base, sha })
  return parse_shortstat(out)
end

function M.shortstat_async(root, base, sha, on_done)
  run_async(root, { "diff", "--shortstat", base, sha }, nil, function(out, err)
    if err then
      on_done(nil, err)
      return
    end

    on_done(parse_shortstat(out))
  end)
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
