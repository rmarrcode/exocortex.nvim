-- ~/.config/nvim/init.lua

vim.g.mapleader = ","

-- Notification history so messages can be copied.
local _notify_history = {}
local _base_notify = vim.notify
vim.notify = function(msg, level, opts)
  table.insert(_notify_history, { msg = msg, level = level, time = os.date("%H:%M:%S") })
  _base_notify(msg, level, opts)
end

vim.api.nvim_create_user_command("Messages", function()
  local lines = {}
  for _, entry in ipairs(_notify_history) do
    local prefix = entry.level == vim.log.levels.ERROR and "[E] "
      or entry.level == vim.log.levels.WARN and "[W] "
      or "[I] "
    for _, line in ipairs(vim.split(entry.msg, "\n")) do
      table.insert(lines, entry.time .. " " .. prefix .. line)
    end
  end

  if #lines == 0 then
    lines = { "(no messages)" }
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  vim.cmd("split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
end, { desc = "Show copyable notification history" })
vim.g.maplocalleader = ","

-- Dedicated venv for the Python provider (pynvim + jupyter_client for molten).
vim.g.python3_host_prog = vim.fn.expand("~/.local/share/nvim/venv/bin/python")

if not vim.pack then
  vim.notify("This config requires Neovim 0.12+", vim.log.levels.ERROR)
  return
end

-- ============================================================================
-- PLUGINS
-- ============================================================================

if not vim.g.pack_bootstrapped then
  vim.g.pack_bootstrapped = true

  vim.pack.add({
  { src = "https://github.com/nvim-lua/plenary.nvim" },
  { src = "https://github.com/nvim-tree/nvim-web-devicons" },
  { src = "https://github.com/nvim-tree/nvim-tree.lua" },
  { src = "https://github.com/nvim-telescope/telescope.nvim" },
  { src = "https://github.com/mfussenegger/nvim-dap" },
  { src = "https://github.com/nvim-neotest/nvim-nio" },
  { src = "https://github.com/rcarriga/nvim-dap-ui" },
  { src = "https://github.com/neovim/nvim-lspconfig" },
  { src = "https://github.com/GCBallesteros/jupytext.nvim" },
  { src = "https://github.com/benlubas/molten-nvim" },
  { src = "https://github.com/nvim-mini/mini.nvim" },
  { src = "https://github.com/mg979/vim-visual-multi" },
  { src = "https://github.com/sindrets/diffview.nvim" },

  -- CODEX
  { src = "https://github.com/johnseth97/codex.nvim" },
})

vim.cmd("packadd plenary.nvim")
vim.cmd("packadd nvim-web-devicons")
vim.cmd("packadd nvim-tree.lua")
vim.cmd("packadd telescope.nvim")
vim.cmd("packadd nvim-dap")
vim.cmd("packadd nvim-nio")
vim.cmd("packadd nvim-dap-ui")
vim.cmd("packadd nvim-lspconfig")
vim.cmd("packadd jupytext.nvim")
vim.cmd("packadd molten-nvim")
vim.cmd("packadd mini.nvim")
vim.cmd("packadd vim-visual-multi")
vim.cmd("packadd diffview.nvim")
vim.cmd("packadd codex.nvim")
end

-- ============================================================================
-- BASIC SETTINGS
-- ============================================================================

-- All autocmds live in this group so re-sourcing the config replaces them
-- instead of stacking duplicates.
local augroup = vim.api.nvim_create_augroup("user-config", { clear = true })

vim.o.number = true
vim.o.relativenumber = true
vim.o.termguicolors = true
vim.o.mouse = "a"
vim.o.hidden = true
vim.o.showtabline = 1 -- native tabline only when there are 2+ tabpages
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.timeoutlen = 300
vim.o.ttimeoutlen = 10
vim.o.updatetime = 200
vim.o.background = "dark"
vim.o.cursorline = true
vim.o.signcolumn = "yes"
vim.o.virtualedit = "block"
vim.opt.fillchars:append({ eob = " " })

vim.keymap.set({ "n", "x", "o" }, "<Space>", "<Nop>", {
  silent = true,
  desc = "Keep Space free in normal modes",
})

-- Turn a visual selection, including a blockwise one, into live multi-cursors.
vim.keymap.set("x", "<leader>m", ":<C-u>VMFromVisual<CR>", {
  silent = true,
  desc = "Edit selection with multiple cursors",
})

-- ============================================================================
-- COLORSCHEME
-- ============================================================================

local vscode_dark = {
  base00 = "#1e1e1e",
  base01 = "#252526",
  base02 = "#2d2d30",
  base03 = "#3e3e42",
  base04 = "#808080",
  base05 = "#d4d4d4",
  base06 = "#e5e5e5",
  base07 = "#ffffff",
  base08 = "#f44747",
  base09 = "#ce9178",
  base0A = "#dcdcaa",
  base0B = "#6a9955",
  base0C = "#4ec9b0",
  base0D = "#569cd6",
  base0E = "#c586c0",
  base0F = "#d7ba7d",
}

require("mini.base16").setup({
  palette = vscode_dark,
  use_cterm = true,
})

local colors = {
  bg = vscode_dark.base00,
  panel = vscode_dark.base01,
  surface = vscode_dark.base02,
  gutter = vscode_dark.base03,
  muted = vscode_dark.base04,
  fg = vscode_dark.base05,
  accent = vscode_dark.base0D,
  green = vscode_dark.base0B,
  orange = vscode_dark.base09,
  red = vscode_dark.base08,
  selection = "#264f78",
  tab_active = "#0e639c",
  tab_visible = "#21344a",
  tab_inactive = "#2a2d2e",
  winbar = "#2d3137",
  winbar_nc = "#1f2227",
}

local function apply_vscode_dark_highlights()
  vim.api.nvim_set_hl(0, "Normal", { fg = colors.fg, bg = colors.bg })
  vim.api.nvim_set_hl(0, "NormalNC", { fg = colors.fg, bg = colors.bg })
  vim.api.nvim_set_hl(0, "CursorLine", { bg = colors.panel })
  vim.api.nvim_set_hl(0, "ColorColumn", { bg = colors.panel })
  vim.api.nvim_set_hl(0, "SignColumn", { bg = colors.bg })
  vim.api.nvim_set_hl(0, "EndOfBuffer", { fg = colors.bg, bg = colors.bg })
  vim.api.nvim_set_hl(0, "LineNr", { fg = colors.muted, bg = colors.bg })
  vim.api.nvim_set_hl(0, "CursorLineNr", { fg = colors.accent, bg = colors.bg, bold = true })
  vim.api.nvim_set_hl(0, "Visual", { bg = colors.selection })
  vim.api.nvim_set_hl(0, "NormalFloat", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "FloatBorder", { fg = colors.gutter, bg = colors.panel })
  vim.api.nvim_set_hl(0, "Pmenu", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "PmenuSel", { fg = colors.fg, bg = colors.selection })
  vim.api.nvim_set_hl(0, "StatusLine", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "StatusLineNC", { fg = colors.muted, bg = colors.panel })
  vim.api.nvim_set_hl(0, "TabLine", { fg = colors.fg, bg = colors.tab_inactive })
  vim.api.nvim_set_hl(0, "TabLineSel", { fg = "#ffffff", bg = colors.tab_active, bold = true })
  vim.api.nvim_set_hl(0, "TabLineFill", { bg = colors.panel })
  vim.api.nvim_set_hl(0, "WinBar", { fg = "#ffffff", bg = colors.winbar, bold = true })
  vim.api.nvim_set_hl(0, "WinBarNC", { fg = colors.fg, bg = colors.winbar_nc })
  vim.api.nvim_set_hl(0, "WinSeparator", { fg = colors.gutter, bg = colors.bg })
  vim.api.nvim_set_hl(0, "NvimTreeNormal", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { fg = colors.panel, bg = colors.panel })
  vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { fg = colors.gutter, bg = colors.panel })
  vim.api.nvim_set_hl(0, "NvimTreeRootFolder", { fg = colors.accent, bg = colors.panel, bold = true })
end

apply_vscode_dark_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
  group = augroup,
  callback = apply_vscode_dark_highlights,
})

-- ============================================================================
-- SAVE FILE
-- ============================================================================

vim.keymap.set("n", "<C-s>", ":w<CR>", {
  noremap = true,
  silent = true,
})

vim.keymap.set("i", "<C-s>", "<Esc>:w<CR>a", {
  noremap = true,
  silent = true,
})

-- ============================================================================
-- NVIM TREE
-- ============================================================================

require("nvim-tree").setup({
  view = {
    side = "left",
    adaptive_size = true,
  },
  git = {
    enable = true,
    ignore = false,
  },
  filters = {
    dotfiles = false,
  },
})

vim.keymap.set("n", "<C-e>", ":NvimTreeToggle<CR>", {
  noremap = true,
  silent = true,
})

-- ============================================================================
-- TELESCOPE
-- ============================================================================

require("telescope").setup({
  defaults = {
    mappings = {
      i = {
        ["<C-g>"] = function(prompt_bufnr)
          local text = require("telescope.actions.state").get_current_line()
          require("telescope.actions").close(prompt_bufnr)
          require("telescope.builtin").live_grep({ default_text = text })
        end,
      },
    },
  },
})

local builtin = require("telescope.builtin")

local function run_telescope(picker, opts)
  local ok, err = pcall(picker, opts or {})

  if ok then
    return
  end

  vim.notify("Telescope failed: " .. tostring(err), vim.log.levels.ERROR)
end

local function project_search()
  local cwd = vim.uv.cwd() or vim.fn.getcwd()

  if vim.fn.isdirectory(cwd .. "/.git") == 1 then
    -- git ls-files cannot combine --others (untracked) with --recurse-submodules,
    -- and telescope rejects the pair outright.
    run_telescope(builtin.git_files, {
      show_untracked = true,
    })
    return
  end

  run_telescope(builtin.find_files, {
    hidden = true,
    no_ignore = false,
  })
end

vim.keymap.set("n", "<C-p>", project_search, {
  silent = true,
  desc = "Search project files",
})
vim.keymap.set("n", "<leader>ff", builtin.find_files)
vim.keymap.set("n", "<leader>fg", builtin.live_grep)
vim.keymap.set("n", "<leader>fb", builtin.buffers)
vim.keymap.set("n", "<leader>fh", builtin.help_tags)

-- ============================================================================
-- LSP
-- ============================================================================

local function lsp_client_supports(bufnr, method)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client:supports_method(method) then
      return true
    end
  end

  return false
end

-- F12 = VSCode's "Go to Definition": definition first (jumps to a class or
-- function body across files), implementation only as a fallback — pyright
-- advertises implementation support but returns nothing useful for classes.
local function jump_to_definition()
  local bufnr = vim.api.nvim_get_current_buf()

  if lsp_client_supports(bufnr, "textDocument/definition") then
    vim.lsp.buf.definition()
    return
  end

  if lsp_client_supports(bufnr, "textDocument/implementation") then
    vim.lsp.buf.implementation()
    return
  end

  vim.notify("No LSP definition provider attached to this buffer", vim.log.levels.WARN)
end

vim.keymap.set("n", "<F12>", jump_to_definition, {
  silent = true,
  desc = "Go to definition",
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup,
  callback = function(args)
    local opts = { buffer = args.buf, silent = true }

    vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
    vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "List references" }))
    vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover documentation" }))
    vim.keymap.set("n", "<F12>", jump_to_definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
  end,
})

-- Server definitions come from nvim-lspconfig's lsp/ directory; vim.lsp.config
-- merges our overrides on top and vim.lsp.enable activates the server.
local function setup_server_if_available(server_name, executable, opts)
  if vim.fn.executable(executable) ~= 1 then
    return false
  end

  if opts then
    vim.lsp.config(server_name, opts)
  end

  vim.lsp.enable(server_name)
  return true
end

setup_server_if_available("lua_ls", "lua-language-server", {
  settings = {
    Lua = {
      diagnostics = { globals = { "vim" } },
      telemetry = { enable = false },
      workspace = { checkThirdParty = false },
    },
  },
})

-- Python: basedpyright from PATH if present, else the copy installed in the
-- nvim venv (pip install basedpyright). before_init points the server at the
-- project's virtualenv so site-packages imports resolve.
local function python_venv_settings(_, config)
  local root = config.root_dir

  if not root then
    return
  end

  for _, venv in ipairs({ root .. "/.venv", root .. "/../.venv", root .. "/venv" }) do
    local python = venv .. "/bin/python"

    if vim.fn.executable(python) == 1 then
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
        python = { pythonPath = vim.fn.fnamemodify(python, ":p") },
      })
      return
    end
  end
end

local venv_basedpyright = vim.fn.expand("~/.local/share/nvim/venv/bin/basedpyright-langserver")

if vim.fn.executable("basedpyright-langserver") == 1 then
  setup_server_if_available("basedpyright", "basedpyright-langserver", {
    before_init = python_venv_settings,
  })
elseif vim.fn.executable(venv_basedpyright) == 1 then
  setup_server_if_available("basedpyright", venv_basedpyright, {
    cmd = { venv_basedpyright, "--stdio" },
    before_init = python_venv_settings,
  })
else
  setup_server_if_available("pyright", "pyright-langserver", {
    before_init = python_venv_settings,
  })
end

setup_server_if_available("ts_ls", "typescript-language-server")
setup_server_if_available("rust_analyzer", "rust-analyzer")
setup_server_if_available("gopls", "gopls")
setup_server_if_available("clangd", "clangd")
setup_server_if_available("bashls", "bash-language-server")

-- Per-window editor tabs (VSCode editor groups): every editor window keeps
-- its own tab strip in the winbar, listing the file buffers that have been
-- shown in that window. Bringing a buffer to another window (<C-Right>,
-- <C-\>, :edit, ...) adds its tab above that window. Tabs are clickable.

local window_tabs = {} -- winid -> ordered bufnr list

local function is_file_buffer(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buflisted
    and vim.bo[buf].buftype == ""
end

local function window_tab_list(win)
  local alive = {}

  for _, buf in ipairs(window_tabs[win] or {}) do
    if is_file_buffer(buf) then
      table.insert(alive, buf)
    end
  end

  window_tabs[win] = alive
  return alive
end

local function buffer_in_any_window_tabs(buf)
  for win, tabs in pairs(window_tabs) do
    if vim.api.nvim_win_is_valid(win) then
      for _, b in ipairs(tabs) do
        if b == buf then
          return true
        end
      end
    end
  end

  return false
end

local function render_editor_tabs(win, current_buf)
  local parts = {}

  for _, buf in ipairs(window_tab_list(win)) do
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")

    if name == "" then
      name = "[No Name]"
    end

    name = name:gsub("%%", "%%%%")

    if vim.bo[buf].modified then
      name = name .. " +"
    end

    local hl = buf == current_buf and "%#TabLineSel#" or "%#TabLine#"
    table.insert(parts, string.format("%%%d@v:lua.EditorWinTabClick@%s %s %%X", buf, hl, name))
  end

  table.insert(parts, "%#WinBar#")
  return table.concat(parts, "")
end

local function render_window_header(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return -- leave floats alone
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local bo = vim.bo[buf]

  if bo.buftype == "terminal" then
    vim.wo[win].winbar = "  terminal  "
    return
  end

  if bo.filetype == "NvimTree" then
    vim.wo[win].winbar = "  explorer  "
    return
  end

  if bo.filetype == "exocortex" then
    return -- the graph window renders its own session winbar
  end

  if is_file_buffer(buf) then
    local tabs = window_tab_list(win)
    local known = false

    for _, b in ipairs(tabs) do
      if b == buf then
        known = true
        break
      end
    end

    if not known then
      table.insert(tabs, buf)
    end

    vim.wo[win].winbar = render_editor_tabs(win, buf)
    return
  end

  -- non-file windows (help, scratch): plain name header
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")

  if name == "" then
    name = "[No Name]"
  end

  local flags = {}

  if bo.modified then
    table.insert(flags, "+")
  end

  if bo.readonly then
    table.insert(flags, "RO")
  end

  local suffix = #flags > 0 and (" [" .. table.concat(flags, ",") .. "]") or ""
  vim.wo[win].winbar = "  " .. name .. suffix .. "  "
end

function _G.EditorWinTabClick(bufnr)
  local win = vim.fn.getmousepos().winid

  if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_win_set_buf(win, bufnr)
    render_window_header(win)
  end
end

-- A buffer moved to another window takes its tab along: drop it from the
-- source window, show that window's nearest remaining tab, and close the
-- window when its last tab left (unless it's the only normal window).
local function leave_window_tab(win, buf)
  local tabs = window_tab_list(win)
  local index

  for i, b in ipairs(tabs) do
    if b == buf then
      index = i
      break
    end
  end

  if index then
    table.remove(tabs, index)
  end

  if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf) then
    render_window_header(win)
    return
  end

  if #tabs > 0 then
    vim.api.nvim_win_set_buf(win, tabs[math.min(index or #tabs, #tabs)])
    render_window_header(win)
    return
  end

  local normal_wins = 0

  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      normal_wins = normal_wins + 1
    end
  end

  if normal_wins > 1 then
    pcall(vim.api.nvim_win_close, win, false)
  else
    vim.api.nvim_win_call(win, function()
      vim.cmd("enew")
    end)
    render_window_header(win)
  end
end

local function refresh_window_headers()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    render_window_header(win)
  end
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufModifiedSet", "TermOpen", "VimEnter", "WinEnter" }, {
  group = augroup,
  callback = refresh_window_headers,
})

vim.api.nvim_create_autocmd("WinClosed", {
  group = augroup,
  callback = function(ev)
    window_tabs[tonumber(ev.match)] = nil
  end,
})

-- ============================================================================
-- EDITOR TAB CYCLING (within the focused window's winbar tabs)
-- ============================================================================

local function ctrl_digit_lhses(index)
  local code = string.byte(tostring(index))

  return {
    "<C-" .. index .. ">",
    string.format("\27[27;5;%d~", code),
    string.format("\27[%d;5u", code),
  }
end

local function ctrl_tab_lhses()
  return {
    "<C-Tab>",
    string.char(27) .. "[27;5;9~",
    string.char(27) .. "[9;5u",
    string.char(27) .. "[1;5I",
  }
end

local function ctrl_shift_tab_lhses()
  return {
    "<C-S-Tab>",
    string.char(27) .. "[27;6;9~",
    string.char(27) .. "[9;6u",
    string.char(27) .. "[1;6I",
    string.char(27) .. "[1;6Z",
  }
end

local function find_editor_window()
  local current_win = vim.api.nvim_get_current_win()

  local function is_editor_window(win)
    local buf = vim.api.nvim_win_get_buf(win)

    return vim.bo[buf].buftype ~= "terminal" and vim.bo[buf].filetype ~= "NvimTree"
  end

  if is_editor_window(current_win) then
    return current_win
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_window(win) then
      return win
    end
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)

    if vim.bo[buf].buftype ~= "terminal" then
      return win
    end
  end
end

local function with_editor_window(fn)
  vim.schedule(function()
    if vim.api.nvim_get_mode().mode == "t" then
      vim.cmd("stopinsert")
    end

    local target_win = find_editor_window()

    if not target_win or not vim.api.nvim_win_is_valid(target_win) then
      return
    end

    vim.api.nvim_set_current_win(target_win)
    fn()
  end)
end

local function cycle_editor_tab(delta)
  with_editor_window(function()
    local win = vim.api.nvim_get_current_win()
    local tabs = window_tab_list(win)

    if #tabs < 2 then
      return
    end

    local current = vim.api.nvim_win_get_buf(win)
    local index = 1

    for i, buf in ipairs(tabs) do
      if buf == current then
        index = i
        break
      end
    end

    vim.api.nvim_win_set_buf(win, tabs[(index - 1 + delta) % #tabs + 1])
  end)
end

vim.keymap.set("n", "<Tab>", function()
  cycle_editor_tab(1)
end, {
  silent = true,
  desc = "Next editor tab",
})

vim.keymap.set("n", "<S-Tab>", function()
  cycle_editor_tab(-1)
end, {
  silent = true,
  desc = "Previous editor tab",
})

for _, lhs in ipairs(ctrl_tab_lhses()) do
  vim.keymap.set("n", lhs, function()
    cycle_editor_tab(1)
  end, {
    silent = true,
    desc = "Next editor tab",
  })
end

for _, lhs in ipairs(ctrl_shift_tab_lhses()) do
  vim.keymap.set("n", lhs, function()
    cycle_editor_tab(-1)
  end, {
    silent = true,
    desc = "Previous editor tab",
  })
end

local close_current_terminal
local capture_terminal_output

-- VSCode's Ctrl+W: close the current window's tab. The window shows its next
-- tab (or closes when that was its last one), and the buffer is only deleted
-- once no other window's tab strip still holds it.
local function close_current_tab()
  local current_buf = vim.api.nvim_get_current_buf()

  if vim.bo[current_buf].buftype == "terminal" then
    if close_current_terminal then
      close_current_terminal()
    end
    return
  end

  if vim.bo[current_buf].filetype == "NvimTree" then
    return
  end

  local win = vim.api.nvim_get_current_win()

  if is_file_buffer(current_buf) then
    leave_window_tab(win, current_buf)

    if buffer_in_any_window_tabs(current_buf) then
      return -- still open as a tab elsewhere; keep the buffer alive
    end
  end

  -- "confirm" prompts to save modified buffers instead of failing with E89.
  local ok, err = pcall(vim.cmd, "confirm bdelete " .. current_buf)

  if not ok then
    vim.notify("Could not close buffer: " .. tostring(err), vim.log.levels.WARN)
  end
end

vim.keymap.set("n", "<leader>x", close_current_tab, {
  silent = true,
  desc = "Close editor tab",
})

-- This shadows Vim's <C-w> window-command prefix in normal mode. Window
-- management stays available via <C-h/j/k/l>, <leader>v/<leader>s and
-- :wincmd. Terminal-mode Ctrl-W is untouched (delete-previous-word).
vim.keymap.set("n", "<C-w>", close_current_tab, {
  silent = true,
  desc = "Close editor tab",
})

-- ============================================================================
-- NOTEBOOKS
-- ============================================================================

require("jupytext").setup({
  style = "markdown",
  output_extension = "md",
  force_ft = "markdown",
})

vim.g.molten_auto_open_output = false
vim.g.molten_image_provider = "none"
vim.g.molten_output_win_max_height = 20
vim.g.molten_wrap_output = true

-- jupytext.nvim registers its own BufReadCmd/BufWriteCmd for *.ipynb in setup().

vim.keymap.set("n", "<leader>ji", ":MoltenInit<CR>", {
  noremap = true,
  silent = true,
  desc = "Start notebook kernel",
})

vim.keymap.set("n", "<leader>jr", ":MoltenEvaluateOperator<CR>", {
  noremap = true,
  silent = true,
  desc = "Run notebook cell or motion",
})

vim.keymap.set("v", "<leader>jr", ":<C-u>MoltenEvaluateVisual<CR>", {
  noremap = true,
  silent = true,
  desc = "Run selected notebook code",
})

vim.keymap.set("n", "<leader>jl", ":MoltenEvaluateLine<CR>", {
  noremap = true,
  silent = true,
  desc = "Run current line",
})

vim.keymap.set("n", "<leader>jo", ":MoltenShowOutput<CR>", {
  noremap = true,
  silent = true,
  desc = "Show cell output",
})

vim.keymap.set("n", "<leader>jh", ":MoltenHideOutput<CR>", {
  noremap = true,
  silent = true,
  desc = "Hide cell output",
})

-- ============================================================================
-- SPLITS
-- ============================================================================

local function current_window_buffer()
  local buf = vim.api.nvim_get_current_buf()

  if vim.bo[buf].buftype == "terminal" or vim.bo[buf].filetype == "NvimTree" then
    return nil
  end

  return buf
end

local function is_editor_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local config = vim.api.nvim_win_get_config(win)

  if config.relative ~= "" then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)

  return vim.bo[buf].buftype ~= "terminal" and vim.bo[buf].filetype ~= "NvimTree"
end

local function open_buffer_in_right_split(buf)
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
end

local function editor_window_to_the_right()
  local right = vim.fn.win_getid(vim.fn.winnr("l"))

  if right ~= 0 and right ~= vim.api.nvim_get_current_win() and is_editor_window(right) then
    return right
  end

  return nil
end

-- VSCode's "move editor to next group": join the window to the right when one
-- exists, otherwise split one off.
local function move_current_buffer_to_right_split()
  local buf = current_window_buffer()

  if not buf then
    return
  end

  local source_win = vim.api.nvim_get_current_win()
  local target_win = editor_window_to_the_right()

  if target_win then
    vim.api.nvim_set_current_win(target_win)
    vim.api.nvim_win_set_buf(target_win, buf)
  else
    open_buffer_in_right_split(buf)
  end

  leave_window_tab(source_win, buf)
end

local function move_current_buffer_to_next_window()
  local buf = current_window_buffer()

  if not buf then
    return
  end

  local wins = vim.api.nvim_tabpage_list_wins(0)
  local current_win = vim.api.nvim_get_current_win()
  local current_index = nil

  for index, win in ipairs(wins) do
    if win == current_win then
      current_index = index
      break
    end
  end

  if current_index then
    for offset = 1, #wins - 1 do
      local win = wins[((current_index - 1 + offset) % #wins) + 1]

      if is_editor_window(win) then
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_buf(win, buf)
        leave_window_tab(current_win, buf)
        return
      end
    end
  end

  open_buffer_in_right_split(buf)
  leave_window_tab(current_win, buf)
end

vim.keymap.set("n", "<leader>v", ":vsplit<CR>", {
  silent = true,
  desc = "Vertical split",
})
vim.keymap.set("n", "<leader>s", ":split<CR>", {
  silent = true,
  desc = "Horizontal split",
})
vim.keymap.set("n", "<leader>wr", move_current_buffer_to_right_split, {
  silent = true,
  desc = "Move current tab to right split",
})
vim.keymap.set("n", "<leader>w\\", move_current_buffer_to_next_window, {
  silent = true,
  desc = "Move current tab to next window",
})
vim.keymap.set("n", "<C-\\>", move_current_buffer_to_next_window, {
  silent = true,
  desc = "Move current tab to next window",
})
vim.keymap.set("n", "<D-C-Right>", move_current_buffer_to_right_split, {
  silent = true,
  desc = "Move current tab to right split",
})
vim.keymap.set("n", "<C-Right>", move_current_buffer_to_right_split, {
  silent = true,
  desc = "Move current tab to right split",
})

-- ============================================================================
-- TERMINAL
-- ============================================================================

local terminal_state = {
  buffers = {},
  current = nil,
  win = nil,
  height = 12,
}

local set_terminal_buffer_keymaps
local new_terminal_tab

local function map_terminal_shortcut(buf, lhses, rhs, desc)
  for _, lhs in ipairs(lhses) do
    vim.keymap.set({ "n", "t" }, lhs, rhs, {
      buffer = buf,
      silent = true,
      desc = desc,
    })
  end
end

local function is_valid_terminal_buffer(buf)
  return buf
    and vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == "terminal"
end

local function prune_terminal_buffers()
  local current_buf = terminal_state.current and terminal_state.buffers[terminal_state.current]
    or nil
  local buffers = {}
  local current_index = nil

  for _, buf in ipairs(terminal_state.buffers) do
    if is_valid_terminal_buffer(buf) then
      table.insert(buffers, buf)

      if buf == current_buf then
        current_index = #buffers
      end
    end
  end

  terminal_state.buffers = buffers

  if #buffers == 0 then
    terminal_state.current = nil
  elseif current_index then
    terminal_state.current = current_index
  else
    terminal_state.current = math.min(terminal_state.current or 1, #buffers)
  end
end

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

local function set_terminal_label(buf, label)
  vim.api.nvim_buf_set_var(buf, "bottom_terminal_label", label)
end

local function render_terminal_tabs()
  local parts = {}

  for index, buf in ipairs(terminal_state.buffers) do
    local label = get_terminal_label(buf)
      :gsub("%%", "%%%%")
      :gsub("[\r\n]", " ")
    local highlight = index == terminal_state.current and "%#TabLineSel#" or "%#TabLine#"

    table.insert(parts, string.format("%s %d: %s ", highlight, index, label))
  end

  table.insert(parts, "%#WinBar#")
  table.insert(parts, "  Ctrl-1..9 jump  ,tn new  ,th/,tl nav  ,tr rename  ,tx close")

  return table.concat(parts, "")
end

local function configure_terminal_window(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winfixheight = true
end

local function update_terminal_winbar()
  if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
    vim.wo[terminal_state.win].winbar = render_terminal_tabs()
  end
end

local function ensure_terminal_window()
  if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
    return terminal_state.win
  end

  vim.cmd("botright " .. terminal_state.height .. "split")
  terminal_state.win = vim.api.nvim_get_current_win()
  configure_terminal_window(terminal_state.win)

  return terminal_state.win
end

local function show_current_terminal()
  prune_terminal_buffers()

  if #terminal_state.buffers == 0 then
    local win = ensure_terminal_window()
    vim.api.nvim_set_current_win(win)
    vim.cmd("terminal")

    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].bufhidden = "hide"
    set_terminal_buffer_keymaps(buf)
    table.insert(terminal_state.buffers, buf)
    terminal_state.current = #terminal_state.buffers
  else
    local win = ensure_terminal_window()
    vim.api.nvim_set_current_win(win)
    local buf = terminal_state.buffers[terminal_state.current]
    set_terminal_buffer_keymaps(buf)
    vim.api.nvim_win_set_buf(win, buf)
  end

  configure_terminal_window(terminal_state.win)
  update_terminal_winbar()
  vim.cmd("startinsert")
end

vim.api.nvim_create_autocmd("WinClosed", {
  group = augroup,
  callback = function(args)
    if terminal_state.win and tostring(terminal_state.win) == args.match then
      terminal_state.win = nil
    end
  end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
  group = augroup,
  callback = function(args)
    local removed = false

    for index, buf in ipairs(terminal_state.buffers) do
      if buf == args.buf then
        table.remove(terminal_state.buffers, index)
        removed = true
        break
      end
    end

    if not removed then
      return
    end

    prune_terminal_buffers()

    if #terminal_state.buffers == 0 then
      if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
        vim.api.nvim_win_hide(terminal_state.win)
        terminal_state.win = nil
      end
      return
    end

    if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
      vim.api.nvim_win_set_buf(terminal_state.win, terminal_state.buffers[terminal_state.current])
      update_terminal_winbar()
    end
  end,
})

_G.bottom_terminal_show = show_current_terminal

local function toggle_bottom_terminal()
  if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
    local buf = terminal_state.current and terminal_state.buffers[terminal_state.current]
    if buf then
      capture_terminal_output(buf)
    end
    vim.api.nvim_win_hide(terminal_state.win)
    terminal_state.win = nil
    return
  end

  show_current_terminal()
end

new_terminal_tab = function()
  local win = ensure_terminal_window()
  vim.api.nvim_set_current_win(win)
  vim.cmd("terminal")

  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = "hide"
  set_terminal_buffer_keymaps(buf)
  table.insert(terminal_state.buffers, buf)
  terminal_state.current = #terminal_state.buffers

  configure_terminal_window(win)
  update_terminal_winbar()
  vim.cmd("startinsert")
end

local function cycle_terminal(delta)
  prune_terminal_buffers()

  if #terminal_state.buffers == 0 then
    show_current_terminal()
    return
  end

  terminal_state.current = ((terminal_state.current or 1) - 1 + delta) % #terminal_state.buffers + 1
  show_current_terminal()
end

local function jump_to_terminal(index)
  prune_terminal_buffers()

  if #terminal_state.buffers == 0 then
    show_current_terminal()
    return
  end

  if index < 1 or index > #terminal_state.buffers then
    return
  end

  terminal_state.current = index
  show_current_terminal()
end

close_current_terminal = function()
  prune_terminal_buffers()

  if #terminal_state.buffers == 0 then
    return
  end

  local index = terminal_state.current or 1
  local buf = terminal_state.buffers[index]

  table.remove(terminal_state.buffers, index)

  if #terminal_state.buffers == 0 then
    terminal_state.current = nil

    if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
      vim.api.nvim_win_hide(terminal_state.win)
      terminal_state.win = nil
    end
  else
    terminal_state.current = math.min(index, #terminal_state.buffers)

    if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
      vim.api.nvim_win_set_buf(terminal_state.win, terminal_state.buffers[terminal_state.current])
      configure_terminal_window(terminal_state.win)
      update_terminal_winbar()
      vim.api.nvim_set_current_win(terminal_state.win)
      vim.cmd("startinsert")
    end
  end

  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

local function rename_current_terminal()
  prune_terminal_buffers()

  if #terminal_state.buffers == 0 then
    return
  end

  local index = terminal_state.current or 1
  local buf = terminal_state.buffers[index]

  vim.ui.input({
    prompt = "Terminal name: ",
    default = get_terminal_label(buf, index),
  }, function(input)
    local label = input and vim.trim(input) or ""

    if label == "" then
      return
    end

    set_terminal_label(buf, label)
    update_terminal_winbar()
  end)
end

-- Deliberately no terminal-mode <C-w> mapping here: in a shell Ctrl-W is
-- delete-previous-word. Normal-mode <C-w> closes the tab; ,tx also works.
set_terminal_buffer_keymaps = function(buf)
  map_terminal_shortcut(buf, { "<C-t>" }, new_terminal_tab, "New terminal tab")
end

vim.keymap.set({ "n", "t" }, "<F4>", toggle_bottom_terminal, {
  desc = "Toggle terminal panel",
})
for index = 1, 9 do
  for _, lhs in ipairs(ctrl_digit_lhses(index)) do
    vim.keymap.set({ "n", "t" }, lhs, function()
      jump_to_terminal(index)
    end, {
      silent = true,
      desc = "Go to terminal " .. index,
    })
  end
end
vim.keymap.set({ "n", "t" }, "<leader>tt", toggle_bottom_terminal, {
  desc = "Toggle terminal panel",
})
vim.keymap.set({ "n", "t" }, "<leader>tn", new_terminal_tab, {
  desc = "New terminal tab",
})
vim.keymap.set({ "n", "t" }, "<leader>th", function()
  cycle_terminal(-1)
end, {
  desc = "Previous terminal tab",
})
vim.keymap.set({ "n", "t" }, "<leader>tl", function()
  cycle_terminal(1)
end, {
  desc = "Next terminal tab",
})
vim.keymap.set({ "n", "t" }, "<leader>tx", close_current_terminal, {
  desc = "Close terminal tab",
})
vim.keymap.set({ "n", "t" }, "<leader>tr", rename_current_terminal, {
  desc = "Rename terminal tab",
})

-- ============================================================================
-- TERMINAL OUTPUT CAPTURE
-- ============================================================================

local last_output_file = "/tmp/nvim_last_terminal_output"

capture_terminal_output = function(buf)
  if not is_valid_terminal_buffer(buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local last_nonempty = #lines
  while last_nonempty > 0 and vim.trim(lines[last_nonempty]) == "" do
    last_nonempty = last_nonempty - 1
  end

  -- Find prompt boundaries: lines ending with common shell prompt chars.
  -- Walk backward to locate the last prompt (current prompt) and the one
  -- before it (end of the previous command's output).
  local prompt_pat = "[%%$#>]%s*$"
  local last_prompt = 0
  local prev_prompt = 0

  for i = last_nonempty, 1, -1 do
    local stripped = lines[i]:gsub("\27%[[%d;]*m", ""):gsub("\27%[[%d;]*[A-Za-z]", "")
    if stripped:match(prompt_pat) then
      if last_prompt == 0 then
        last_prompt = i
      else
        prev_prompt = i
        break
      end
    end
  end

  local output_lines
  if prev_prompt > 0 and last_prompt > prev_prompt + 1 then
    output_lines = vim.list_slice(lines, prev_prompt + 1, last_prompt - 1)
  else
    output_lines = vim.list_slice(lines, math.max(1, last_nonempty - 49), last_nonempty)
  end

  -- Strip ANSI escape sequences from saved output
  for i, line in ipairs(output_lines) do
    output_lines[i] = line:gsub("\27%[[%d;]*m", ""):gsub("\27%[[%d;]*[A-Za-z]", "")
  end

  vim.fn.writefile(output_lines, last_output_file)
  vim.env.NVIM_LAST_OUTPUT = last_output_file
end

vim.api.nvim_create_autocmd("BufLeave", {
  group = augroup,
  callback = function(args)
    if is_valid_terminal_buffer(args.buf) then
      capture_terminal_output(args.buf)
    end
  end,
})

vim.keymap.set({ "n", "t" }, "<leader>ty", function()
  local buf = terminal_state.current and terminal_state.buffers[terminal_state.current]
  capture_terminal_output(buf)
  if vim.fn.filereadable(last_output_file) == 1 then
    local content = table.concat(vim.fn.readfile(last_output_file), "\n")
    vim.fn.setreg("+", content)
    vim.fn.setreg('"', content)
    vim.notify("Captured to clipboard + " .. last_output_file, vim.log.levels.INFO)
  else
    vim.notify("No terminal output captured", vim.log.levels.WARN)
  end
end, {
  silent = true,
  desc = "Capture terminal output to clipboard and $NVIM_LAST_OUTPUT",
})

-- ============================================================================
-- DEBUGGING
-- ============================================================================

local dap = require("dap")
local dapui = require("dapui")

dapui.setup({})

-- dapui.open() carves its panels out of the existing windows, which shrinks the
-- bottom terminal and widens nvim-tree; closing it never restores them. Snapshot
-- every window's size before opening and replay it after closing so the IDE
-- layout is exactly where you left it.
local dap_saved_layout = nil

local function dapui_open_keep_layout()
  if not dap_saved_layout then
    dap_saved_layout = vim.fn.winrestcmd()
  end
  dapui.open()
end

local function dapui_close_restore_layout()
  dapui.close()

  if dap_saved_layout then
    local restore = dap_saved_layout
    dap_saved_layout = nil
    -- Defer so dapui's windows are fully gone before we resize the survivors.
    vim.schedule(function()
      pcall(vim.cmd, restore)
    end)
  end
end

dap.listeners.before.attach.dapui_auto_open = dapui_open_keep_layout
dap.listeners.before.launch.dapui_auto_open = dapui_open_keep_layout
dap.listeners.before.event_terminated.dapui_auto_close = dapui_close_restore_layout
dap.listeners.before.event_exited.dapui_auto_close = dapui_close_restore_layout

-- ── debug keybinding hint window ─────────────────────────────────────────────

local debug_hint_win = nil

local function open_debug_hint()
  if debug_hint_win and vim.api.nvim_win_is_valid(debug_hint_win) then
    return
  end

  local lines = {
    "  DEBUG  ",
    " F5  ,dc  Continue  ",
    " F6  ,db  Breakpoint",
    " F7  ,di  Step Into ",
    " F8  ,dn  Step Over ",
    " F9  ,do  Step Out  ",
    " F10 ,dx  Stop      ",
    " F11 ,du  Toggle UI ",
  }

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, #l)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)

  debug_hint_win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 1,
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 50,
  })

  vim.wo[debug_hint_win].winblend = 15
end

local function close_debug_hint()
  if debug_hint_win and vim.api.nvim_win_is_valid(debug_hint_win) then
    vim.api.nvim_win_close(debug_hint_win, true)
  end
  debug_hint_win = nil
end

dap.listeners.after.attach.debug_hint_open = function()
  vim.schedule(open_debug_hint)
end

dap.listeners.after.launch.debug_hint_open = function()
  vim.schedule(open_debug_hint)
end

dap.listeners.before.event_terminated.debug_hint_close = function()
  vim.schedule(close_debug_hint)
end

dap.listeners.before.event_exited.debug_hint_close = function()
  vim.schedule(close_debug_hint)
end

-- Stopped-line visuals: amber gutter arrow + persistent line tint.
-- nvim-dap places the DapStopped sign automatically on every pause.
vim.api.nvim_set_hl(0, "DapStoppedLine",  { bg = "#2a2000" })
vim.api.nvim_set_hl(0, "DapStoppedFlash", { bg = "#665500", bold = true })

vim.fn.sign_define("DapStopped", {
  text    = "▶",
  texthl  = "DiagnosticWarn",
  linehl  = "DapStoppedLine",
  numhl   = "DiagnosticWarn",
})

local dap_label_ns = vim.api.nvim_create_namespace("dap_stopped_label")
local dap_flash_ns = vim.api.nvim_create_namespace("dap_stopped_flash")
local dap_last_buf = nil

local function clear_dap_stopped_marks()
  if dap_last_buf and vim.api.nvim_buf_is_valid(dap_last_buf) then
    vim.api.nvim_buf_clear_namespace(dap_last_buf, dap_label_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(dap_last_buf, dap_flash_ns, 0, -1)
  end
  dap_last_buf = nil
end

-- On any pause (breakpoint, step, exception), jump the cursor to the stopped
-- line in the nearest editor window so the source is always in focus.
dap.listeners.after.event_stopped["jump_to_source"] = function(session, body)
  if not body.threadId then
    return
  end

  session:request("stackTrace", { threadId = body.threadId, startFrame = 0, levels = 1 }, function(err, response)
    if err or not response or not response.stackFrames or #response.stackFrames == 0 then
      return
    end

    local frame = response.stackFrames[1]

    if not frame.source or not frame.source.path then
      return
    end

    local path = frame.source.path
    local line = frame.line

    vim.schedule(function()
      local bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(bufnr)

      local target_win = nil

      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
          local wbuf = vim.api.nvim_win_get_buf(win)
          if vim.bo[wbuf].buftype == "" and vim.bo[wbuf].filetype ~= "NvimTree" then
            target_win = win
            break
          end
        end
      end

      if not target_win then
        return
      end

      vim.api.nvim_win_set_buf(target_win, bufnr)
      vim.api.nvim_set_current_win(target_win)
      vim.api.nvim_win_set_cursor(target_win, { line, 0 })
      vim.cmd("normal! zz")

      -- Clear any previous stop markers, then mark the new stopped line.
      clear_dap_stopped_marks()
      dap_last_buf = bufnr

      local reason = body.reason or "stopped"
      local label = reason == "exception" and "  ✗ exception"
        or reason == "breakpoint"         and "  ◆ breakpoint"
        or                                    "  ◆ " .. reason

      -- Persistent end-of-line label (stays until continue/terminate).
      vim.api.nvim_buf_set_extmark(bufnr, dap_label_ns, line - 1, 0, {
        virt_text     = { { label, "DiagnosticWarn" } },
        virt_text_pos = "eol",
        priority      = 200,
      })

      -- Bright flash that fades after 500 ms, leaving the sign's linehl.
      vim.api.nvim_buf_set_extmark(bufnr, dap_flash_ns, line - 1, 0, {
        line_hl_group = "DapStoppedFlash",
        priority      = 210,
      })
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_clear_namespace(bufnr, dap_flash_ns, 0, -1)
        end
      end, 500)
    end)
  end)
end

-- Remove the label when execution resumes or the session ends.
local function on_dap_continue()
  vim.schedule(clear_dap_stopped_marks)
end

dap.listeners.before.event_continued.clear_stopped  = on_dap_continue
dap.listeners.before.event_terminated.clear_stopped = on_dap_continue
dap.listeners.before.event_exited.clear_stopped     = on_dap_continue

-- Pause on errors instead of letting the process exit. "uncaught" catches
-- exceptions that crash the program; "userUnhandled" also catches the common
-- case where a launcher/framework swallows the exception or calls sys.exit()
-- after printing a traceback — debugpy breaks at the point it leaves your code.
-- Set via defaults so nvim-dap sends it during the configuration phase (before
-- configurationDone), which debugpy requires.
dap.defaults.fallback.exception_breakpoints = { "uncaught", "userUnhandled" }

-- Toggle breaking on EVERY raised exception (even ones caught internally by
-- libraries). Useful when a framework swallows the error so deeply that even
-- userUnhandled misses it; noisy otherwise, so it's opt-in.
vim.keymap.set("n", "<leader>de", function()
  local current = dap.defaults.fallback.exception_breakpoints
  local on = type(current) == "table" and vim.tbl_contains(current, "raised")

  if on then
    dap.defaults.fallback.exception_breakpoints = { "uncaught", "userUnhandled" }
    vim.notify("DAP: break on uncaught/userUnhandled exceptions", vim.log.levels.INFO)
  else
    dap.defaults.fallback.exception_breakpoints = { "raised", "uncaught", "userUnhandled" }
    vim.notify("DAP: break on ALL raised exceptions", vim.log.levels.INFO)
  end

  -- Apply live if a session is already running.
  local session = dap.session()
  if session then
    session:set_exception_breakpoints(dap.defaults.fallback.exception_breakpoints)
  end
end, {
  silent = true,
  desc = "Toggle break on all raised exceptions",
})

local function file_exists(path)
  return path ~= nil and vim.fn.filereadable(path) == 1
end

local function read_file_lines(path)
  if not file_exists(path) then
    return nil
  end

  return vim.fn.readfile(path)
end

local function parse_shell_words(text)
  local words = {}

  for word in text:gmatch("%S+") do
    table.insert(words, word)
  end

  return words
end

local function normalize_script_path(path)
  if path and vim.trim(path) ~= "" then
    return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  end

  -- No argument: nearest training_run.sh upward from the current file (or
  -- cwd), falling back to the FM-RTDETR checkout.
  local found = vim.fs.find("training_run.sh", {
    upward = true,
    path = vim.fn.expand("%:p:h"),
  })[1]

  return found or vim.fn.expand("~/Documents/fm-rtdetr-env/FM-RTDETR/training_run.sh")
end

local function parse_training_run(script_path)
  local lines = read_file_lines(script_path)

  if not lines then
    return nil, "Unable to read " .. script_path
  end

  local root = vim.fn.fnamemodify(script_path, ":p:h")
  local python_path
  local args = {}
  local collecting_args = false

  for _, raw_line in ipairs(lines) do
    local line = vim.trim(raw_line)

    if not python_path then
      local root_relative = line:match('MLFLOW_PYTHON:%-$ROOT/(.-)}')

      if root_relative then
        python_path = vim.fn.fnamemodify(root .. "/" .. root_relative, ":p")
      else
        local direct_relative = line:match('^([.%/%w_%-]+/python)%s+tools/train%.py')

        if direct_relative then
          python_path = vim.fn.fnamemodify(root .. "/" .. direct_relative, ":p")
        end
      end
    end

    local train_args = line:match('tools/train%.py%s+(.*)$') or line:match('"[^"]*"%s+train%.py%s+(.*)$')

    if train_args then
      collecting_args = true
      line = train_args
    elseif not collecting_args then
      goto continue
    end

    local has_continuation = line:sub(-1) == "\\"
    local cleaned = has_continuation and vim.trim(line:sub(1, -2)) or line

    vim.list_extend(args, parse_shell_words(cleaned))

    if not has_continuation then
      break
    end

    ::continue::
  end

  python_path = python_path or vim.env.MLFLOW_PYTHON

  if not python_path or python_path == "" then
    return nil, "Unable to determine the Python interpreter from " .. script_path
  end

  local train_program
  for _, candidate in ipairs({ root .. "/tools/train.py", root .. "/train.py" }) do
    if file_exists(candidate) then
      train_program = candidate
      break
    end
  end

  if not file_exists(python_path) then
    return nil, "Python interpreter not found: " .. python_path
  end

  if not train_program then
    return nil, "Training entrypoint not found: expected train.py or tools/train.py under " .. root
  end

  if #args == 0 then
    return nil, "Unable to parse training arguments from " .. script_path
  end

  return {
    cwd = root,
    program = train_program,
    python = python_path,
    args = args,
  }
end

local function debugpy_available(python_path)
  local result = vim.system({
    python_path,
    "-c",
    "import debugpy",
  }, { text = true }):wait()

  return result.code == 0
end

local function ensure_debugpy(python_path)
  if debugpy_available(python_path) then
    return true
  end

  vim.notify(
    "debugpy is not installed for " .. python_path .. ". Run: " .. python_path .. " -m pip install debugpy",
    vim.log.levels.ERROR
  )
  return false
end

dap.adapters.python = function(callback, config)
  local python_path = config.pythonPath

  if type(python_path) == "function" then
    python_path = python_path()
  end

  if not python_path or python_path == "" then
    python_path = vim.fn.exepath("python3")
  end

  callback({
    type = "executable",
    command = python_path,
    args = { "-m", "debugpy.adapter" },
  })
end

dap.configurations.python = {
  {
    type = "python",
    request = "launch",
    name = "Current file",
    program = "${file}",
    cwd = "${workspaceFolder}",
    pythonPath = function()
      return vim.fn.exepath("python3")
    end,
    justMyCode = false,
    console = "integratedTerminal",
  },
}

local mlflow_jobs = {}
local mlflow_log_file = "/tmp/fm-rtdetr-mlflow.log"

local function ensure_mlflow_ui(root, python_path)
  local existing = mlflow_jobs[root]

  if existing and vim.fn.jobwait({ existing }, 0)[1] == -1 then
    return
  end

  local mlflow_cmd = table.concat(vim.tbl_map(vim.fn.shellescape, {
    python_path,
    "-m",
    "mlflow",
    "ui",
    "--host",
    "127.0.0.1",
    "--port",
    "5000",
  }), " ")

  local job_id = vim.fn.jobstart({
    "sh",
    "-c",
    mlflow_cmd .. " >> " .. mlflow_log_file .. " 2>&1",
  }, {
    cwd = root,
    detach = true,
    on_exit = function()
      mlflow_jobs[root] = nil
    end,
  })

  if job_id <= 0 then
    vim.notify("Failed to start MLflow UI", vim.log.levels.WARN)
    return
  end

  mlflow_jobs[root] = job_id
  vim.notify("MLflow UI started on http://127.0.0.1:5000. Log: " .. mlflow_log_file, vim.log.levels.INFO)
end

local function run_training_debug(script_path)
  local config, err = parse_training_run(normalize_script_path(script_path))

  if not config then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if not ensure_debugpy(config.python) then
    return
  end

  ensure_mlflow_ui(config.cwd, config.python)

  dap.run({
    type = "python",
    request = "launch",
    name = "Training run",
    cwd = config.cwd,
    program = config.program,
    args = config.args,
    pythonPath = config.python,
    justMyCode = false,
    subProcess = true,
    console = "integratedTerminal",
  })
end

vim.api.nvim_create_user_command("DebugTrainingRun", function(opts)
  run_training_debug(opts.args)
end, {
  nargs = "?",
  complete = "file",
  desc = "Debug a FM-RTDETR training_run.sh wrapper",
})

vim.keymap.set("n", "<leader>dr", function()
  run_training_debug()
end, {
  silent = true,
  desc = "Debug default training run",
})
local function read_exocortex_config()
  local path = vim.fs.find("exocortex.config", {
    upward = true,
    path = vim.fn.expand("%:p:h"),
  })[1]

  if not path then return {} end

  local file = io.open(path, "r")
  if not file then return {} end

  local cfg, section = { _dir = vim.fn.fnamemodify(path, ":h") }, nil
  for line in file:lines() do
    local s = line:match("^%[(.-)%]$")
    if s then
      section = s
      cfg[section] = cfg[section] or {}
    elseif section then
      local k, v = line:match("^(%w+)%s*=%s*(.+)$")
      if k then cfg[section][k] = vim.trim(v) end
    end
  end
  file:close()
  return cfg
end

-- Resolve a path from exocortex.config relative to `base` (absolute passes through).
local function resolve_config_path(base, p)
  if p:find("^/") then
    return vim.fn.fnamemodify(vim.fn.expand(p), ":p")
  end
  return vim.fn.fnamemodify(base .. "/" .. p, ":p"):gsub("/$", "")
end

-- Launch debugpy straight from explicit [debug] keys in exocortex.config
-- (python/cwd/program/args) instead of parsing a shell script.
local function run_training_debug_explicit(cfg)
  local d = cfg.debug or {}
  local base = cfg._dir

  local cwd = d.cwd and resolve_config_path(base, d.cwd) or base
  local python = d.python and resolve_config_path(base, d.python) or vim.fn.exepath("python3")
  local program = resolve_config_path(cwd, d.program or "train.py")
  local args = d.args and parse_shell_words(d.args) or {}

  if not file_exists(python) then
    vim.notify("Python interpreter not found: " .. python, vim.log.levels.ERROR)
    return
  end

  if not file_exists(program) then
    vim.notify("Training entrypoint not found: " .. program, vim.log.levels.ERROR)
    return
  end

  if not ensure_debugpy(python) then
    return
  end

  ensure_mlflow_ui(cwd, python)

  dap.run({
    type = "python",
    request = "launch",
    name = "Training run",
    cwd = cwd,
    program = program,
    args = args,
    pythonPath = python,
    justMyCode = false,
    subProcess = true,
    console = "integratedTerminal",
  })
end

vim.keymap.set("n", "<F5>", function()
  if dap.session() then
    dap.continue()
    return
  end

  local cfg = read_exocortex_config()
  local d = cfg.debug or {}

  -- Explicit interpreter/cwd/args take precedence over script parsing.
  if cfg._dir and (d.python or d.cwd or d.program or d.args) then
    run_training_debug_explicit(cfg)
    return
  end

  local run_file = d.run_file

  if run_file and cfg._dir and not run_file:find("^/") then
    run_file = cfg._dir .. "/" .. run_file
  end

  run_training_debug(run_file)
end, {
  silent = true,
  desc = "Start or continue debug session",
})
vim.keymap.set("n", "<F6>", dap.toggle_breakpoint, {
  silent = true,
  desc = "Toggle breakpoint",
})
vim.keymap.set("n", "<F7>", dap.step_into, {
  silent = true,
  desc = "Step into",
})
vim.keymap.set("n", "<F8>", dap.step_over, {
  silent = true,
  desc = "Step over",
})
vim.keymap.set("n", "<F9>", dap.step_out, {
  silent = true,
  desc = "Step out",
})
vim.keymap.set("n", "<F10>", dap.terminate, {
  silent = true,
  desc = "Stop debug session",
})
vim.keymap.set("n", "<F11>", dapui.toggle, {
  silent = true,
  desc = "Toggle debug UI",
})
vim.keymap.set("n", "<leader>db", dap.toggle_breakpoint, {
  silent = true,
  desc = "Toggle breakpoint",
})
vim.keymap.set("n", "<leader>dc", dap.continue, {
  silent = true,
  desc = "Start or continue debug session",
})
vim.keymap.set("n", "<leader>dn", dap.step_over, {
  silent = true,
  desc = "Step over",
})
vim.keymap.set("n", "<leader>di", dap.step_into, {
  silent = true,
  desc = "Step into",
})
vim.keymap.set("n", "<leader>do", dap.step_out, {
  silent = true,
  desc = "Step out",
})
vim.keymap.set("n", "<leader>du", dapui.toggle, {
  silent = true,
  desc = "Toggle debug UI",
})
vim.keymap.set("n", "<leader>dx", dap.terminate, {
  silent = true,
  desc = "Stop debug session",
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = augroup,
  callback = function()
    for _, job_id in pairs(mlflow_jobs) do
      pcall(vim.fn.jobstop, job_id)
    end
  end,
})

-- ============================================================================
-- STARTUP LAYOUT
-- ============================================================================

local started_with_stdin = false

vim.api.nvim_create_autocmd("StdinReadPre", {
  group = augroup,
  callback = function()
    started_with_stdin = true
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup,
  callback = function()
    -- Skip the IDE layout when nvim is a throwaway editor: piped input,
    -- diff mode, or commit/rebase messages spawned by git.
    if started_with_stdin or vim.o.diff then
      return
    end

    local ft = vim.bo.filetype

    if ft == "gitcommit" or ft == "gitrebase" then
      return
    end

    vim.cmd("NvimTreeOpen")

    vim.defer_fn(function()
      toggle_bottom_terminal()
    end, 50)
  end,
})

-- ============================================================================
-- WINDOW NAVIGATION
-- ============================================================================

vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-l>", "<C-w>l")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")

vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]])
vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]])
vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]])
vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]])

-- ============================================================================
-- CODEX
-- ============================================================================

require("codex").setup({
  autoinstall = false,
})

-- ============================================================================
-- GIT DIFF REVIEW
-- ============================================================================

vim.keymap.set("n", "<leader>go", ":DiffviewOpen<CR>", {
  noremap = true,
  silent = true,
  desc = "Open repo diff view",
})

vim.keymap.set("n", "<leader>gh", ":DiffviewFileHistory %<CR>", {
  noremap = true,
  silent = true,
  desc = "Open file history",
})

vim.keymap.set("n", "<leader>gq", ":DiffviewClose<CR>", {
  noremap = true,
  silent = true,
  desc = "Close diff view",
})

-- Codex edits land in the git working tree. Review them with Diffview.
-- ============================================================================
-- CODEX KEYBINDS
-- ============================================================================

-- Main Codex UI
vim.keymap.set(
  { "n", "v" },
  "<F3>",
  ":Codex<CR>",
  { noremap = true, silent = true }
)

-- Quick prompts
vim.keymap.set(
  "n",
  "<leader>cc",
  ":Codex<CR>",
  { noremap = true, silent = true }
)

-- Ask about selected code
vim.keymap.set(
  "v",
  "<leader>ce",
  ":Codex explain this code<CR>",
  { noremap = true, silent = true }
)

-- Refactor selected code
vim.keymap.set(
  "v",
  "<leader>cr",
  ":Codex refactor this code<CR>",
  { noremap = true, silent = true }
)

-- Generate tests
vim.keymap.set(
  "v",
  "<leader>ct",
  ":Codex generate tests for this code<CR>",
  { noremap = true, silent = true }
)

-- ============================================================================
-- EXOCORTEX (talk to coding agents in a DAG)
-- ============================================================================

require("exocortex").setup({})

-- Ctrl-A then i. With Ctrl held through both keys the terminal encodes
-- Ctrl-I as Tab, so map that variant too.
for _, lhs in ipairs({ "<C-a>i", "<C-a><Tab>" }) do
  vim.keymap.set("n", lhs, ":Exocortex<CR>", {
    silent = true,
    desc = "Open agent DAG",
  })
end

-- Ctrl+Shift+A then i: open the graph and start a fresh session. Depending
-- on when Ctrl/Shift are released, the second key arrives as i, I, C-S-i,
-- C-i, or Tab — map them all. Telling Ctrl+Shift+A apart from Ctrl+A needs
-- the kitty keyboard protocol (enabled in ~/.config/wezterm/wezterm.lua).
for _, second in ipairs({ "i", "I", "<C-S-i>", "<C-i>", "<Tab>" }) do
  vim.keymap.set("n", "<C-S-a>" .. second, function()
    require("exocortex").open()
    require("exocortex.graph").create_new_session()
  end, {
    silent = true,
    desc = "New exocortex session",
  })
end

-- ============================================================================
-- RELOAD CONFIG
-- ============================================================================

vim.keymap.set("n", "<F2>", function()
  for key in pairs(package.loaded) do
    if key:match("^exocortex") then
      package.loaded[key] = nil
    end
  end
  vim.cmd("source ~/.config/nvim/init.lua")
  print("Neovim config reloaded")
end)

-- ============================================================================
-- QUIT
-- ============================================================================

vim.keymap.set("n", "<leader>q", ":qa<CR>")
vim.keymap.set("n", "<leader>Q", ":qa!<CR>")
