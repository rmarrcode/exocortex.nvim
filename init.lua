-- ~/.config/nvim/init.lua

vim.g.mapleader = ","

-- Notification and command-line message history so errors can be copied.
local _notify_history = {}
local _base_notify = vim.notify
local new_terminal_tab
local render_window_header
local find_editor_window
local is_file_buffer
local move_buffers_to_editor_window
local last_editor_window = nil

local function message_level_prefix(level)
  return level == vim.log.levels.ERROR and "[E] "
    or level == vim.log.levels.WARN and "[W] "
    or "[I] "
end

vim.notify = function(msg, level, opts)
  table.insert(_notify_history, {
    msg = tostring(msg),
    level = level,
    time = os.date("%H:%M:%S"),
  })
  _base_notify(msg, level, opts)
end

local function get_command_messages()
  if vim.api.nvim_exec2 then
    local ok, result = pcall(vim.api.nvim_exec2, "messages", { output = true })

    if ok and result and result.output then
      return result.output
    end
  end

  local ok, output = pcall(vim.api.nvim_exec, "messages", true)
  return ok and output or ""
end

vim.api.nvim_create_user_command("Messages", function()
  local lines = {
    "Neovim messages",
    "Y copies this whole buffer. L copies the latest message. q closes it.",
    "",
  }

  local native_messages = vim.trim(get_command_messages())

  if native_messages ~= "" then
    table.insert(lines, "--- :messages ---")
    vim.list_extend(lines, vim.split(native_messages, "\n", { plain = true }))
    table.insert(lines, "")
  end

  if #_notify_history > 0 then
    table.insert(lines, "--- vim.notify history ---")
    for _, entry in ipairs(_notify_history) do
      for _, line in ipairs(vim.split(entry.msg, "\n", { plain = true })) do
        table.insert(lines, entry.time .. " " .. message_level_prefix(entry.level) .. line)
      end
    end
  end

  if #lines == 3 then
    table.insert(lines, "(no messages)")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "messages"

  vim.cmd("botright 14split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })

  vim.keymap.set({ "n" }, "q", "<cmd>close<CR>", { buffer = buf, silent = true, desc = "Close messages" })
  vim.keymap.set({ "n" }, "<C-q>", "<cmd>close<CR>", { buffer = buf, silent = true, desc = "Close messages" })
  vim.keymap.set("n", "Y", function()
    local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    vim.fn.setreg("+", content)
    vim.fn.setreg("\"", content)
    vim.notify("Copied messages to clipboard", vim.log.levels.INFO)
  end, { buffer = buf, silent = true, desc = "Copy all messages" })
  vim.keymap.set("n", "L", function()
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local latest = nil

    for i = #all_lines, 1, -1 do
      local line = all_lines[i]
      if vim.trim(line) ~= "" and not line:match("^%-%-%-") then
        latest = line
        break
      end
    end

    if latest then
      vim.fn.setreg("+", latest)
      vim.fn.setreg("\"", latest)
      vim.notify("Copied latest message to clipboard", vim.log.levels.INFO)
    end
  end, { buffer = buf, silent = true, desc = "Copy latest message" })
end, { desc = "Show copyable Neovim messages and notifications" })

vim.keymap.set("n", "<leader>mm", "<cmd>Messages<CR>", {
  silent = true,
  desc = "Open copyable messages",
})
vim.keymap.set("n", "<leader>me", "<cmd>Messages<CR>", {
  silent = true,
  desc = "Open copyable errors",
})
vim.g.maplocalleader = ","

-- Dedicated venv for the Python provider (pynvim + jupyter_client for molten).
vim.g.python3_host_prog = vim.fn.expand("~/.local/share/nvim/venv/bin/python")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local result = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })

  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to install lazy.nvim:\n" .. result, vim.log.levels.ERROR)
    return
  end
end
vim.opt.rtp:prepend(lazypath)

local ok_lazy, lazy = pcall(require, "lazy")
if not ok_lazy then
  vim.notify("lazy.nvim is not available", vim.log.levels.ERROR)
  return
end

-- ============================================================================
-- PLUGINS
-- ============================================================================

lazy.setup({
  { "nvim-lua/plenary.nvim", lazy = false },
  { "nvim-tree/nvim-web-devicons", lazy = false },
  { "nvim-tree/nvim-tree.lua", lazy = false },
  { "nvim-telescope/telescope.nvim", lazy = false },
  { "mfussenegger/nvim-dap", lazy = false },
  { "nvim-neotest/nvim-nio", lazy = false },
  { "rcarriga/nvim-dap-ui", lazy = false },
  { "neovim/nvim-lspconfig", lazy = false },
  { "GCBallesteros/jupytext.nvim", lazy = false },
  { "benlubas/molten-nvim", lazy = false },
  { "nvim-mini/mini.nvim", lazy = false },
  { "mg979/vim-visual-multi", lazy = false },
  { "sindrets/diffview.nvim", lazy = false },
  { "johnseth97/codex.nvim", lazy = false },
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")
      ts.install({ "bash", "json", "latex", "markdown", "markdown_inline", "yaml" })
      pcall(vim.treesitter.language.register, "bash", { "sh", "zsh" })

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user-treesitter", { clear = true }),
        pattern = { "bash", "json", "jsonc", "latex", "markdown", "sh", "yaml", "zsh" },
        callback = function()
          local ok = pcall(vim.treesitter.start)
          if not ok then
            vim.cmd("syntax enable")
          end
        end,
      })
    end,
  },
  { "jbyuki/nabla.nvim", ft = { "markdown" } },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.nvim", "jbyuki/nabla.nvim" },
    config = function()
      require("render-markdown").setup({
        latex = { enabled = false },
        win_options = { conceallevel = { rendered = 2 } },
        on = {
          render = function()
            require("nabla").enable_virt({ autogen = true })
          end,
          clear = function()
            require("nabla").disable_virt()
          end,
        },
      })
    end,
  },
}, {
  root = vim.fn.stdpath("data") .. "/lazy",
  lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
  change_detection = { notify = false },
  install = { missing = true },
})
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
vim.opt.clipboard = "unnamedplus"
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  vim.g.clipboard = "osc52"
end
vim.o.showtabline = 2 -- always show (used for AI node status bar)
vim.o.tabline = "%!v:lua.ExocortexTabLine()"
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
vim.g.sh_no_error = 1

vim.filetype.add({
  extension = {
    sh = "sh",
    bash = "bash",
    zsh = "zsh",
  },
  filename = {
    [".bashrc"] = "bash",
    [".bash_profile"] = "bash",
    [".bash_aliases"] = "bash",
    [".zshrc"] = "zsh",
    [".envrc"] = "sh",
  },
  pattern = {
    [".*/Dockerfile%..*"] = "dockerfile",
    [".*%.env%..*"] = "sh",
  },
})

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
  active_border = "#6a9955",
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
  vim.api.nvim_set_hl(0, "NormalFloat", { fg = colors.fg, bg = colors.bg })
  vim.api.nvim_set_hl(0, "FloatBorder", { fg = colors.gutter, bg = colors.bg })
  vim.api.nvim_set_hl(0, "FloatTitle", { fg = colors.fg, bg = colors.bg, bold = true })
  vim.api.nvim_set_hl(0, "LspReferenceText", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "LspReferenceRead", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "LspReferenceWrite", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "Pmenu", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "PmenuSel", { fg = colors.fg, bg = colors.selection })
  vim.api.nvim_set_hl(0, "StatusLine", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "StatusLineNC", { fg = colors.muted, bg = colors.panel })
  vim.api.nvim_set_hl(0, "TabLine", { fg = colors.fg, bg = colors.tab_inactive })
  vim.api.nvim_set_hl(0, "TabLineSel", { fg = "#ffffff", bg = colors.tab_active, bold = true })
  vim.api.nvim_set_hl(0, "TabLineFill", { bg = colors.panel })
  vim.api.nvim_set_hl(0, "EditorTabUnsaved", { fg = "#1e1e1e", bg = "#ffcc00", bold = true })
  vim.api.nvim_set_hl(0, "EditorHeaderUnsaved", { fg = "#1e1e1e", bg = "#ffcc00", bold = true })
  vim.api.nvim_set_hl(0, "WinBar", { fg = "#ffffff", bg = colors.winbar, bold = true })
  vim.api.nvim_set_hl(0, "WinBarNC", { fg = colors.fg, bg = colors.winbar_nc })
  vim.api.nvim_set_hl(0, "WinSeparator", { fg = colors.gutter, bg = colors.bg })
  vim.api.nvim_set_hl(0, "ActiveWindowBorder", { fg = colors.active_border, bg = colors.bg })
  vim.api.nvim_set_hl(0, "ActiveWindowStatusLine", { fg = colors.fg, bg = "#243326" })
  vim.api.nvim_set_hl(0, "ActiveWindowWinBar", { fg = "#ffffff", bg = "#263a2a", bold = true })
  vim.api.nvim_set_hl(0, "NvimTreeNormal", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { fg = colors.panel, bg = colors.panel })
  vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { fg = colors.gutter, bg = colors.panel })
  vim.api.nvim_set_hl(0, "NvimTreeRootFolder", { fg = colors.accent, bg = colors.panel, bold = true })
  vim.api.nvim_set_hl(0, "DapUIScope", { fg = colors.accent, bg = colors.panel, bold = true })
  vim.api.nvim_set_hl(0, "DapUIType", { fg = colors.orange, bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUIValue", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUIVariable", { fg = "#ffffff", bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUIModifiedValue", { fg = colors.orange, bg = colors.panel, bold = true })
  vim.api.nvim_set_hl(0, "DapUIDecoration", { fg = colors.gutter, bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUIThread", { fg = colors.green, bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUIStoppedThread", { fg = colors.orange, bg = colors.panel, bold = true })
  vim.api.nvim_set_hl(0, "DapUIFrameName", { fg = colors.fg, bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUISource", { fg = colors.accent, bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUILineNumber", { fg = colors.orange, bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUIFloatBorder", { fg = colors.accent, bg = colors.panel })
  vim.api.nvim_set_hl(0, "DapUIWinSelect", { fg = colors.accent, bg = colors.panel, bold = true })
  vim.api.nvim_set_hl(0, "DapUIBreakpointsCurrentLine", { fg = colors.orange, bg = colors.panel, bold = true })
  vim.api.nvim_set_hl(0, "yamlMappingKey", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "yamlBlockMappingKey", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "yamlBlockMappingDelimiter", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "yamlKeyValueDelimiter", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "jsonKeyword", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "jsonKeywordMatch", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "jsonQuote", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "@property.json", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "@property.jsonc", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "@punctuation.delimiter.json", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "@punctuation.delimiter.jsonc", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "@property.yaml", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "@punctuation.delimiter.yaml", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "@punctuation.special.yaml", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "@function.call.bash", { fg = colors.fg })
  vim.api.nvim_set_hl(0, "@operator.bash", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "@punctuation.special.bash", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "@variable.bash", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "shDeref", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "shDerefSimple", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "shDerefVar", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "shOption", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "ExocortexStatusRunning", { fg = "#dcdcaa", bg = colors.tab_inactive, bold = true })
  vim.api.nvim_set_hl(0, "ExocortexStatusDone",    { fg = "#6a9955", bg = colors.tab_inactive })
  vim.api.nvim_set_hl(0, "ExocortexStatusError",   { fg = "#f44747", bg = colors.tab_inactive })
end

apply_vscode_dark_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
  group = augroup,
  callback = apply_vscode_dark_highlights,
})

local active_window_border_keys = {
  WinSeparator = true,
  StatusLine = true,
  WinBar = true,
}

local function parse_winhighlight(value)
  local mappings = {}
  local order = {}

  for entry in tostring(value or ""):gmatch("[^,]+") do
    local key, group = entry:match("^%s*([^:]+):([^:]+)%s*$")
    if key and group then
      key = vim.trim(key)
      group = vim.trim(group)
      if not mappings[key] then
        order[#order + 1] = key
      end
      mappings[key] = group
    end
  end

  return mappings, order
end

local function build_winhighlight(mappings, order)
  local parts = {}

  for _, key in ipairs(order) do
    if mappings[key] then
      parts[#parts + 1] = key .. ":" .. mappings[key]
    end
  end

  for key, group in pairs(mappings) do
    if not vim.tbl_contains(order, key) then
      parts[#parts + 1] = key .. ":" .. group
    end
  end

  return table.concat(parts, ",")
end

local function current_winhighlight(win)
  local ok, value = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
  return ok and value or ""
end

local function set_winhighlight(win, value)
  pcall(vim.api.nvim_set_option_value, "winhighlight", value, { win = win })
end

local function restorable_winhighlight(win)
  local saved = vim.w[win].exocortex_base_winhighlight
  if saved ~= nil then
    return saved
  end

  local current = current_winhighlight(win)
  local mappings, order = parse_winhighlight(current)
  for key in pairs(active_window_border_keys) do
    mappings[key] = nil
  end

  saved = build_winhighlight(mappings, order)
  vim.w[win].exocortex_base_winhighlight = saved
  return saved
end

local function is_normal_layout_window(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
end

local function restore_window_border(win)
  local saved = vim.w[win].exocortex_base_winhighlight
  if saved ~= nil then
    set_winhighlight(win, saved)
    vim.w[win].exocortex_base_winhighlight = nil
  end
end

local function update_active_window_border()
  local wins = vim.tbl_filter(is_normal_layout_window, vim.api.nvim_tabpage_list_wins(0))
  local active_win = vim.api.nvim_get_current_win()

  if #wins <= 1 then
    for _, win in ipairs(wins) do
      restore_window_border(win)
    end
    return
  end

  for _, win in ipairs(wins) do
    if win == active_win then
      local base = restorable_winhighlight(win)
      local mappings, order = parse_winhighlight(base)

      mappings.WinSeparator = "ActiveWindowBorder"
      mappings.StatusLine = "ActiveWindowStatusLine"
      mappings.WinBar = "ActiveWindowWinBar"

      set_winhighlight(win, build_winhighlight(mappings, order))
    else
      restore_window_border(win)
    end
  end
end

vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "WinNew", "WinClosed", "TabEnter", "VimResized" }, {
  group = augroup,
  callback = function()
    vim.schedule(update_active_window_border)
  end,
})

vim.schedule(update_active_window_border)

-- ============================================================================
-- JSON
-- ============================================================================

local function format_json_buffer(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = opts or {}

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")

  if vim.trim(text) == "" then
    return true
  end

  local commands = {}
  local filetype = vim.bo[bufnr].filetype

  if vim.fn.executable("prettier") == 1 then
    table.insert(commands, { "prettier", "--parser", filetype == "jsonc" and "jsonc" or "json" })
  end

  if filetype == "json" and vim.fn.executable("jq") == 1 then
    table.insert(commands, { "jq", "." })
  end

  if filetype == "json" then
    if vim.fn.executable("python3") == 1 then
      table.insert(commands, { "python3", "-m", "json.tool" })
    elseif vim.fn.executable("python") == 1 then
      table.insert(commands, { "python", "-m", "json.tool" })
    end
  end

  local last_error = filetype == "jsonc" and "no JSONC formatter found: install prettier" or "no JSON formatter found: install jq, python3, or prettier"

  for _, command in ipairs(commands) do
    local output = vim.fn.system(command, text)

    if vim.v.shell_error == 0 and vim.trim(output) ~= "" then
      local view = vim.fn.winsaveview()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(vim.trim(output), "\n", { plain = true }))
      vim.fn.winrestview(view)
      return true
    end

    last_error = vim.trim(output)
  end

  if not opts.silent then
    vim.notify(last_error, vim.log.levels.ERROR)
  end

  return false
end

vim.api.nvim_create_user_command("JsonFormat", format_json_buffer, {
  desc = "Pretty-print the current JSON buffer",
})

vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "json", "jsonc" },
  callback = function(args)
    vim.bo[args.buf].shiftwidth = 2
    vim.bo[args.buf].tabstop = 2
    vim.bo[args.buf].softtabstop = 2
    vim.bo[args.buf].expandtab = true
    vim.wo.conceallevel = 0
    vim.wo.wrap = false

    if vim.fn.executable("prettier") == 1 then
      local parser = vim.bo[args.buf].filetype == "jsonc" and "jsonc" or "json"
      vim.bo[args.buf].formatprg = "prettier --parser " .. parser
      vim.bo[args.buf].equalprg = "prettier --parser " .. parser
    elseif vim.bo[args.buf].filetype == "json" and vim.fn.executable("jq") == 1 then
      vim.bo[args.buf].formatprg = "jq ."
      vim.bo[args.buf].equalprg = "jq ."
    end

    vim.keymap.set("n", "<leader>jf", function()
      format_json_buffer(args.buf)
    end, {
      buffer = args.buf,
      silent = true,
      desc = "Pretty-print JSON",
    })
  end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup,
  pattern = { "*.json", "*.jsonc" },
  callback = function(args)
    format_json_buffer(args.buf, { silent = true })
  end,
})

-- ============================================================================
-- SHELL SCRIPTS
-- ============================================================================

vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "sh", "bash", "zsh" },
  callback = function(args)
    vim.bo[args.buf].shiftwidth = 2
    vim.bo[args.buf].tabstop = 2
    vim.bo[args.buf].softtabstop = 2
    vim.bo[args.buf].expandtab = true
    vim.bo[args.buf].textwidth = 0
    vim.bo[args.buf].formatoptions = vim.bo[args.buf].formatoptions:gsub("[t]", "")
    vim.wo.conceallevel = 0
    vim.wo.concealcursor = ""
    vim.wo.wrap = false

    if vim.fn.executable("shfmt") == 1 then
      vim.bo[args.buf].formatprg = "shfmt -i 2 -ci -sr -"
      vim.bo[args.buf].equalprg = "shfmt -i 2 -ci -sr -"
    end
  end,
})

-- ============================================================================
-- NVIM TREE
-- ============================================================================

require("nvim-tree").setup({
  view = {
    side = "left",
    adaptive_size = true,
  },
  renderer = {
    hidden_display = function(hidden_stats)
      if hidden_stats and hidden_stats.limited_dir then
        return "(showing first 25 entries; more omitted)"
      end
    end,
  },
  git = {
    enable = true,
    ignore = false,
  },
  filters = {
    dotfiles = false,
  },
  filesystem_watchers = {
    enable = true,
    debounce_delay = 100,
  },
  actions = {
    expand_all = {
      max_folder_discovery = 25,
    },
  },
  on_attach = function(bufnr)
    local api = require("nvim-tree.api")
    api.config.mappings.default_on_attach(bufnr)

    local function opts(desc)
      return { buffer = bufnr, noremap = true, silent = true, nowait = true, desc = "NvimTree: " .. desc }
    end

    local dir_entry_limit = 25

    local function is_dir_node(node)
      return node and (node.type == "directory" or (node.fs_stat and node.fs_stat.type == "directory"))
    end

    local function read_dir_head(path, limit)
      local handle = path and vim.uv.fs_scandir(path)
      if not handle then
        return nil, false
      end

      local names = {}
      while true do
        local name = vim.uv.fs_scandir_next(handle)
        if not name then
          break
        end

        if #names >= limit then
          return names, true
        end

        names[#names + 1] = name
      end

      return names, false
    end

    local function draw_limited_dir(node, names)
      local ok_core, core = pcall(require, "nvim-tree.core")
      local ok_factory, node_factory = pcall(require, "nvim-tree.node.factory")
      local ok_utils, tree_utils = pcall(require, "nvim-tree.utils")
      if not (ok_core and ok_factory and ok_utils) then
        api.node.open.edit(node)
        return
      end

      local explorer = core.get_explorer()
      if not explorer then
        api.node.open.edit(node)
        return
      end

      if node.nodes then
        for _, child in ipairs(node.nodes) do
          if child.destroy then
            child:destroy()
          end
        end
      end

      local parent_path = node.link_to or node.absolute_path
      node.nodes = {}
      node.has_children = false
      node.hidden_stats = { limited_dir = 1 }

      for _, name in ipairs(names) do
        local abs = tree_utils.path_join({ parent_path, name })
        local stat = vim.uv.fs_lstat(abs)
        local child = node_factory.create({
          explorer = explorer,
          parent = node,
          absolute_path = abs,
          name = name,
          fs_stat = stat,
        })
        if child then
          node.nodes[#node.nodes + 1] = child
        end
      end

      table.sort(node.nodes, function(a, b)
        if a.type ~= b.type then
          return a.type == "directory"
        end
        return a.name:lower() < b.name:lower()
      end)

      node.open = true
      explorer.renderer:draw()
      vim.notify(
        string.format("NvimTree: showing first %d entries for large directory", dir_entry_limit),
        vim.log.levels.INFO
      )
    end

    local function open_with_dir_limit()
      local node = api.tree.get_node_under_cursor()
      if not is_dir_node(node) or node.open then
        api.node.open.edit(node)
        return
      end

      local names, overflow = read_dir_head(node.link_to or node.absolute_path, dir_entry_limit)
      if not names or not overflow then
        api.node.open.edit(node)
        return
      end

      draw_limited_dir(node, names)
    end

    -- Deletion requires a visual-block selection followed by dd.
    local cut_dir   = nil  -- temp dir holding cut files
    local cut_names = {}   -- basenames of files inside cut_dir
    local using_cut = false

    local function clear_cut()
      if cut_dir and vim.fn.isdirectory(cut_dir) == 1 then
        vim.fn.delete(cut_dir, "rf")
      end
      cut_dir   = nil
      cut_names = {}
      using_cut = false
    end

    local function selected_row_range()
      local mode = vim.fn.mode()
      local start_row
      local end_row

      if mode == "v" or mode == "V" or mode == "\22" then
        start_row = vim.fn.line("v")
        end_row = vim.fn.line(".")
        vim.cmd("normal! \27")
      else
        start_row = vim.fn.getpos("'<")[2]
        end_row = vim.fn.getpos("'>")[2]
      end

      if start_row <= 0 or end_row <= 0 then
        start_row = vim.fn.line(".")
        end_row = start_row
      else
        local a, b = start_row, end_row
        start_row = math.min(a, b)
        end_row = math.max(a, b)
      end

      return start_row, end_row
    end

    local function each_selected(fn)
      local start_row, end_row = selected_row_range()

      local saved = vim.api.nvim_win_get_cursor(0)
      for row = start_row, end_row do
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        local node = api.tree.get_node_under_cursor()
        if node and node.absolute_path and node.absolute_path ~= "" then
          fn(node)
        end
      end
      vim.api.nvim_win_set_cursor(0, saved)
    end

    local function selected_nodes()
      local nodes = {}
      local seen = {}

      each_selected(function(node)
        if not seen[node.absolute_path] then
          seen[node.absolute_path] = true
          nodes[#nodes + 1] = node
        end
      end)
      return nodes
    end

    local function move_selected_to_open_window()
      local target = find_editor_window and find_editor_window() or nil
      if not target then
        vim.notify("NvimTree: no editor window available", vim.log.levels.WARN)
        return
      end

      local buffers = {}
      local nodes = selected_nodes()

      for _, node in ipairs(nodes) do
        local path = node and node.absolute_path
        if not path or path == "" then
          goto continue_move
        end

        if node.type == "directory" then
          goto continue_move
        end

        local buf = vim.fn.bufadd(path)
        if buf < 0 then
          goto continue_move
        end

        pcall(vim.fn.bufload, buf)
        buffers[#buffers + 1] = buf
        ::continue_move::
      end

      if #buffers == 0 then
        vim.notify("NvimTree: no files selected", vim.log.levels.WARN)
        return
      end

      if move_buffers_to_editor_window then
        move_buffers_to_editor_window(target, buffers)
      else
        vim.api.nvim_set_current_win(target)
        vim.api.nvim_win_set_buf(target, buffers[1])
      end
    end

    local function delete_selected_nodes()
      if vim.fn.mode() ~= "\22" then
        vim.notify("NvimTree: use visual block selection (Ctrl-V) before dd", vim.log.levels.WARN)
        return
      end

      local nodes = selected_nodes()
      local deleted = 0

      for _, node in ipairs(nodes) do
        local path = node and node.absolute_path
        if path and path ~= "" then
          local is_dir = node.type == "directory" or (node.fs_stat and node.fs_stat.type == "directory")
          local ok = vim.fn.delete(path, is_dir and "rf" or "") == 0
          if ok then
            deleted = deleted + 1
          end
        end
      end

      clear_cut()
      api.tree.reload()

      if deleted == 0 then
        vim.notify("NvimTree: no files selected", vim.log.levels.WARN)
      end
    end

    -- y: copy into nvim-tree clipboard (non-destructive, no temp dir)
    pcall(vim.keymap.del, "n", "y", { buffer = bufnr })
    vim.keymap.set({ "n", "v" }, "y", function()
      clear_cut()
      each_selected(function(_) api.fs.copy.node() end)
    end, opts("Yank (copy) file(s)"))

    pcall(vim.keymap.del, "n", "d", { buffer = bufnr })
    vim.keymap.set("x", "dd", delete_selected_nodes, opts("Delete selected file(s)"))
    vim.keymap.set("n", "dd", function()
      vim.notify("NvimTree: use visual block selection (Ctrl-V) then dd to delete files", vim.log.levels.WARN)
    end, opts("Delete selected file(s)"))

    -- p pastes copied files, or moves temp-cut files if that legacy state exists.
    pcall(vim.keymap.del, "n", "p", { buffer = bufnr })
    vim.keymap.set("n", "p", function()
      if not using_cut then
        api.fs.paste()
        return
      end

      local node = api.tree.get_node_under_cursor()
      local dest_dir
      if node and node.absolute_path ~= "" then
        local is_dir = node.type == "directory"
          or (node.fs_stat and node.fs_stat.type == "directory")
        dest_dir = is_dir and node.absolute_path
          or vim.fn.fnamemodify(node.absolute_path, ":h")
      end

      if not dest_dir then
        vim.notify("NvimTree: cannot determine paste destination", vim.log.levels.WARN)
        return
      end

      for _, name in ipairs(cut_names) do
        vim.fn.rename(cut_dir .. "/" .. name, dest_dir .. "/" .. name)
      end

      pcall(vim.fn.delete, cut_dir, "d") -- remove now-empty temp dir
      cut_dir   = nil
      cut_names = {}
      using_cut = false
      api.tree.reload()
    end, opts("Paste file(s)"))

    vim.keymap.set({ "n", "v" }, "<D-C-Right>", move_selected_to_open_window, opts("Move file(s) to open window"))
    vim.keymap.set({ "n", "v" }, "<C-D-Right>", move_selected_to_open_window, opts("Move file(s) to open window"))
    vim.keymap.set({ "n", "v" }, "<C-Right>", move_selected_to_open_window, opts("Move file(s) to open window"))

    vim.keymap.set("n", "<CR>", open_with_dir_limit, opts("Open"))
    vim.keymap.set("n", "o", open_with_dir_limit, opts("Open"))
    vim.keymap.set("n", "<2-LeftMouse>", open_with_dir_limit, opts("Open"))

    pcall(vim.keymap.del, "n", "t", { buffer = bufnr })
    vim.keymap.set("n", "t", function()
      local node = api.tree.get_node_under_cursor()
      if not node or not node.absolute_path or node.absolute_path == "" then
        return
      end

      local is_dir = node.type == "directory" or (node.fs_stat and node.fs_stat.type == "directory")
      if not is_dir then
        return
      end

      if new_terminal_tab then
        new_terminal_tab(node.absolute_path)
      end
    end, opts("Open terminal in directory"))

    -- Leaving the sidebar: permanently delete anything still in the temp dir
    vim.api.nvim_create_autocmd("BufLeave", {
      buffer = bufnr,
      callback = clear_cut,
    })
  end,
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
        ["<Esc>"] = require("telescope.actions").close,
        ["<C-p>"] = require("telescope.actions").close,
        ["<C-q>"] = require("telescope.actions").close,
        ["<C-g>"] = function(prompt_bufnr)
          local text = require("telescope.actions.state").get_current_line()
          require("telescope.actions").close(prompt_bufnr)
          require("telescope.builtin").live_grep({ default_text = text })
        end,
        ["<C-s>"] = function(prompt_bufnr)
          local text = require("telescope.actions.state").get_current_line()
          require("telescope.actions").close(prompt_bufnr)
          require("telescope.builtin").lsp_dynamic_workspace_symbols({ default_text = text })
        end,
      },
      n = {
        ["<Esc>"] = require("telescope.actions").close,
        ["q"] = require("telescope.actions").close,
        ["<C-p>"] = require("telescope.actions").close,
        ["<C-q>"] = require("telescope.actions").close,
      },
    },
  },
})

local builtin = require("telescope.builtin")

local with_editor_window

local function run_telescope(picker, opts)
  local ok, err = pcall(picker, opts or {})

  if ok then
    return
  end

  vim.notify("Telescope failed: " .. tostring(err), vim.log.levels.ERROR)
end

local search_root_markers = {
  ".git",
  "pyproject.toml",
  "package.json",
  "Cargo.toml",
  "go.mod",
  "Makefile",
  "README.md",
}

local search_exclude_globs = {
  "!**/.git/**",
  "!**/node_modules/**",
  "!**/.venv/**",
  "!**/venv/**",
  "!**/__pycache__/**",
  "!**/.mypy_cache/**",
  "!**/.pytest_cache/**",
  "!**/.ruff_cache/**",
  "!**/dist/**",
  "!**/build/**",
  "!**/target/**",
  "!**/dataset/**",
  "!**/datasets/**",
  "!**/data/**",
  "!**/mlruns/**",
}

local function current_search_start()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" then
    return vim.fn.fnamemodify(name, ":p:h")
  end
  return vim.uv.cwd() or vim.fn.getcwd()
end

local function project_root_for_search()
  local start = current_search_start()
  local root = vim.fs.root(start, search_root_markers)
  return root or start
end

local function search_root_is_too_broad(root)
  local normalized = vim.fn.fnamemodify(root, ":p")
  local home = vim.fn.fnamemodify(vim.fn.expand("~"), ":p")
  return normalized == "/" or normalized == home
end

local function rg_file_command()
  local cmd = { "rg", "--files", "--hidden", "--color", "never" }

  for _, glob in ipairs(search_exclude_globs) do
    cmd[#cmd + 1] = "--glob"
    cmd[#cmd + 1] = glob
  end

  return cmd
end

local function project_search()
  local root = project_root_for_search()

  if search_root_is_too_broad(root) then
    vim.notify("Telescope: refusing to scan " .. root .. "; open a project file or cd into a project", vim.log.levels.WARN)
    return
  end

  if vim.fn.executable("rg") == 1 then
    run_telescope(builtin.find_files, require("telescope.themes").get_dropdown({
      cwd = root,
      find_command = rg_file_command(),
      prompt_title = "Project files: " .. vim.fn.fnamemodify(root, ":~"),
      previewer = false,
      layout_config = {
        width = 0.82,
        height = 0.55,
      },
    }))
    return
  end

  run_telescope(builtin.find_files, require("telescope.themes").get_dropdown({
    cwd = root,
    hidden = false,
    prompt_title = "Project files: " .. vim.fn.fnamemodify(root, ":~"),
    previewer = false,
    layout_config = {
      width = 0.82,
      height = 0.55,
    },
  }))
end

local function project_grep()
  local root = project_root_for_search()

  if search_root_is_too_broad(root) then
    vim.notify("Telescope: refusing to scan " .. root .. "; open a project file or cd into a project", vim.log.levels.WARN)
    return
  end

  run_telescope(builtin.live_grep, {
    cwd = root,
    hidden = true,
    additional_args = function()
      local args = {}
      for _, glob in ipairs(search_exclude_globs) do
        args[#args + 1] = "--glob"
        args[#args + 1] = glob
      end
      return args
    end,
  })
end

vim.keymap.set("n", "<C-p>", function() with_editor_window(project_search) end, {
  silent = true,
  desc = "Search project files",
})
vim.keymap.set("n", "<C-f>", function() with_editor_window(project_grep) end, {
  silent = true,
  desc = "Search project text",
})
vim.keymap.set("n", "<leader>ff", function() with_editor_window(function() builtin.find_files() end) end)
vim.keymap.set("n", "<leader>fg", function() with_editor_window(function() builtin.live_grep() end) end)
vim.keymap.set("n", "<leader>fb", function() with_editor_window(function() builtin.buffers() end) end)
vim.keymap.set("n", "<leader>fh", function() with_editor_window(function() builtin.help_tags() end) end)

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

local f12_reference_cycle = {
  key = nil,
  index = 0,
  locations = {},
}

local function location_path(location)
  local uri = location.uri or location.targetUri
  return uri and vim.uri_to_fname(uri) or ""
end

local function location_range(location)
  return location.range or location.targetSelectionRange or location.targetRange or {}
end

local function location_start(location)
  local range = location_range(location)
  return range.start or { line = 0, character = 0 }
end

local function location_key(location)
  local start = location_start(location)
  return table.concat({ location_path(location), start.line or 0, start.character or 0 }, ":")
end

local function sort_locations(locations)
  table.sort(locations, function(a, b)
    local a_path = location_path(a)
    local b_path = location_path(b)

    if a_path ~= b_path then
      return a_path < b_path
    end

    local a_start = location_start(a)
    local b_start = location_start(b)

    if a_start.line ~= b_start.line then
      return (a_start.line or 0) < (b_start.line or 0)
    end

    return (a_start.character or 0) < (b_start.character or 0)
  end)
end

local function location_is_after_cursor(location)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_path = vim.api.nvim_buf_get_name(0)
  local start = location_start(location)
  local path = location_path(location)

  if path ~= cursor_path then
    return path > cursor_path
  end

  if (start.line or 0) ~= cursor[1] - 1 then
    return (start.line or 0) > cursor[1] - 1
  end

  return (start.character or 0) > cursor[2]
end

local function symbol_cycle_key(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  return table.concat({ bufnr, vim.fn.expand("<cword>"), cursor[1] }, ":")
end

local function collect_reference_locations(bufnr)
  if not lsp_client_supports(bufnr, "textDocument/references") then
    return {}
  end

  local ok_params, params = pcall(vim.lsp.util.make_position_params)
  if not ok_params then
    params = vim.lsp.util.make_position_params(0, "utf-16")
  end
  params.context = { includeDeclaration = false }

  local responses = vim.lsp.buf_request_sync(bufnr, "textDocument/references", params, 1200)
  local locations = {}
  local seen = {}

  for client_id, response in pairs(responses or {}) do
    local client = vim.lsp.get_client_by_id(client_id)

    for _, location in ipairs(response.result or {}) do
      local key = location_key(location)

      if not seen[key] then
        seen[key] = true
        table.insert(locations, {
          uri = location.uri,
          range = location.range,
          targetUri = location.targetUri,
          targetSelectionRange = location.targetSelectionRange,
          targetRange = location.targetRange,
          offset_encoding = client and client.offset_encoding or "utf-16",
        })
      end
    end
  end

  sort_locations(locations)
  return locations
end

-- F12 cycles through usage sites for the symbol under the cursor. If the LSP
-- cannot provide references, it keeps the normal go-to-definition fallback.
local function cycle_symbol_references_or_definition()
  local bufnr = vim.api.nvim_get_current_buf()
  local locations = collect_reference_locations(bufnr)

  if #locations == 0 then
    f12_reference_cycle = { key = nil, index = 0, locations = {} }
    jump_to_definition()
    return
  end

  local cycle_key = symbol_cycle_key(bufnr)

  if f12_reference_cycle.key ~= cycle_key then
    f12_reference_cycle = {
      key = cycle_key,
      index = 0,
      locations = locations,
    }

    for index, location in ipairs(locations) do
      if location_is_after_cursor(location) then
        f12_reference_cycle.index = index - 1
        break
      end
    end
  else
    f12_reference_cycle.locations = locations
  end

  f12_reference_cycle.index = (f12_reference_cycle.index % #f12_reference_cycle.locations) + 1
  local location = f12_reference_cycle.locations[f12_reference_cycle.index]
  vim.lsp.util.jump_to_location(location, location.offset_encoding or "utf-16", true)
end

vim.keymap.set("n", "<F12>", cycle_symbol_references_or_definition, {
  silent = true,
  desc = "Cycle symbol references",
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup,
  callback = function(args)
    local opts = { buffer = args.buf, silent = true }

    vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
    vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "List references" }))
    vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover documentation" }))
    vim.keymap.set("n", "<F12>", cycle_symbol_references_or_definition, vim.tbl_extend("force", opts, { desc = "Cycle symbol references" }))
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
setup_server_if_available("jsonls", "vscode-json-language-server")

-- Per-window editor tabs (VSCode editor groups): every editor window keeps
-- its own tab strip in the winbar, listing the file buffers that have been
-- shown in that window. Bringing a buffer to another window (<C-Right>,
-- <C-\>, :edit, ...) adds its tab above that window. Tabs are clickable.

local window_tabs = {} -- winid -> ordered bufnr list

local _empty_buf = nil

local function get_empty_buf()
  if _empty_buf and vim.api.nvim_buf_is_valid(_empty_buf) then
    return _empty_buf
  end
  _empty_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_empty_buf].buftype = "nofile"
  vim.bo[_empty_buf].bufhidden = "hide"
  vim.bo[_empty_buf].swapfile = false
  vim.bo[_empty_buf].modifiable = false
  return _empty_buf
end

is_file_buffer = function(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buflisted
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
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

    local modified = vim.bo[buf].modified
    if modified then
      name = "UNSAVED " .. name
    end

    local hl = modified and "%#EditorTabUnsaved#"
      or buf == current_buf and "%#TabLineSel#"
      or "%#TabLine#"
    table.insert(parts, string.format("%%%d@v:lua.EditorWinTabClick@%s %s %%X", buf, hl, name))
  end

  table.insert(parts, "%#WinBar#")
  return table.concat(parts, "")
end

render_window_header = function(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return -- leave floats alone
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local bo = vim.bo[buf]

  if bo.buftype == "terminal" then
    return -- update_terminal_winbar() owns this winbar; don't overwrite with static text
  end

  if bo.filetype == "NvimTree" then
    vim.wo[win].winbar = "  explorer  "
    return
  end

  if bo.filetype == "exocortex" or bo.filetype == "exocortex-sessions" then
    return -- graph and session-sidebar manage their own winbar
  end

  if _empty_buf and buf == _empty_buf then
    vim.wo[win].winbar = ""
    return
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
    table.insert(flags, "UNSAVED")
  end

  if bo.readonly then
    table.insert(flags, "RO")
  end

  local suffix = #flags > 0 and (" [" .. table.concat(flags, ",") .. "]") or ""
  local hl = bo.modified and "%#EditorHeaderUnsaved#" or "%#WinBar#"
  vim.wo[win].winbar = hl .. "  " .. name .. suffix .. "  %*"
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

  local has_other_editor = false

  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= win and vim.api.nvim_win_get_config(w).relative == "" then
      local wbuf = vim.api.nvim_win_get_buf(w)
      local ft = vim.bo[wbuf].filetype
      if vim.bo[wbuf].buftype ~= "terminal" and ft ~= "NvimTree" and not ft:match("^exocortex") then
        has_other_editor = true
        break
      end
    end
  end

  if has_other_editor then
    pcall(vim.api.nvim_win_close, win, false)
  else
    vim.api.nvim_win_set_buf(win, get_empty_buf())
    render_window_header(win)
  end
end

function _G.ExocortexLeaveWindowTab(win, buf)
  leave_window_tab(win, buf)
end

local function register_window_tab(win, buf)
  if not (vim.api.nvim_win_is_valid(win) and is_file_buffer(buf)) then
    return
  end

  local tabs = window_tab_list(win)

  for _, known in ipairs(tabs) do
    if known == buf then
      return
    end
  end

  table.insert(tabs, buf)
  window_tabs[win] = tabs
end

local function tab_list_has(tabs, buf)
  for _, known in ipairs(tabs) do
    if known == buf then
      return true
    end
  end

  return false
end

move_buffers_to_editor_window = function(target_win, buffers)
  if not vim.api.nvim_win_is_valid(target_win) then
    return
  end

  local target_tabs = window_tab_list(target_win)
  local target_buf = vim.api.nvim_win_get_buf(target_win)

  if is_file_buffer(target_buf) and not tab_list_has(target_tabs, target_buf) then
    table.insert(target_tabs, target_buf)
  end

  local first_buf

  for _, buf in ipairs(buffers) do
    if is_file_buffer(buf) then
      local source_wins = {}
      local source_seen = {}

      local function add_source_win(win)
        if not source_seen[win] then
          source_seen[win] = true
          table.insert(source_wins, win)
        end
      end

      for win, tabs in pairs(window_tabs) do
        if win ~= target_win and vim.api.nvim_win_is_valid(win) and tab_list_has(tabs, buf) then
          add_source_win(win)
        end
      end

      local visible_win = vim.fn.bufwinid(buf)
      if visible_win > 0 and visible_win ~= target_win and vim.api.nvim_win_is_valid(visible_win) then
        add_source_win(visible_win)
      end

      for _, win in ipairs(source_wins) do
        leave_window_tab(win, buf)
      end

      if not tab_list_has(target_tabs, buf) then
        table.insert(target_tabs, buf)
      end

      first_buf = first_buf or buf
    end
  end

  window_tabs[target_win] = target_tabs

  if first_buf then
    vim.api.nvim_set_current_win(target_win)
    vim.api.nvim_win_set_buf(target_win, first_buf)
    render_window_header(target_win)
  end
end

function _G.ExocortexRegisterWindowTab(win, buf)
  register_window_tab(win, buf)
end

local move_file_buffer_out_of_terminal_window

local function refresh_window_headers()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    render_window_header(win)
  end
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufModifiedSet", "BufWritePost", "TermOpen", "VimEnter", "WinEnter" }, {
  group = augroup,
  callback = refresh_window_headers,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  group = augroup,
  callback = function()
    vim.schedule(move_file_buffer_out_of_terminal_window)
  end,
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

find_editor_window = function()
  local function is_editor_window_local(win)
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].buftype ~= "terminal" and vim.bo[buf].filetype ~= "NvimTree"
  end

  if last_editor_window and vim.api.nvim_win_is_valid(last_editor_window) and is_editor_window_local(last_editor_window) then
    return last_editor_window
  end

  local current_win = vim.api.nvim_get_current_win()

  if is_editor_window_local(current_win) then
    last_editor_window = current_win
    return current_win
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_window_local(win) then
      last_editor_window = win
      return win
    end
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)

    if vim.bo[buf].buftype ~= "terminal" then
      last_editor_window = win
      return win
    end
  end
end

do
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" and vim.bo[buf].filetype ~= "NvimTree" then
    last_editor_window = win
  end
end

with_editor_window = function(fn)
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

  if _empty_buf and current_buf == _empty_buf then
    return
  end

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
-- :wincmd. Bottom terminal buffers map Ctrl-W to close their terminal tab.
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

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  group = augroup,
  callback = function()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)

    if vim.bo[buf].buftype ~= "terminal" and vim.bo[buf].filetype ~= "NvimTree" then
      last_editor_window = win
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "yaml", "yml" },
  callback = function(args)
    vim.bo[args.buf].expandtab = true
    vim.bo[args.buf].shiftwidth = 2
    vim.bo[args.buf].softtabstop = 2
    vim.bo[args.buf].tabstop = 2

    for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
      if vim.api.nvim_win_is_valid(win) then
        vim.wo[win].cursorline = false
        vim.wo[win].conceallevel = 0
        vim.wo[win].concealcursor = ""
      end
    end
  end,
})

local function leftmost_editor_window()
  local best_win
  local best_row
  local best_col

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_window(win) then
      local pos = vim.fn.win_screenpos(win)
      local row = pos[1] or 0
      local col = pos[2] or 0

      if not best_win or col < best_col or (col == best_col and row < best_row) then
        best_win = win
        best_row = row
        best_col = col
      end
    end
  end

  return best_win
end

function _G.ExocortexLeftmostEditorWindow()
  return leftmost_editor_window()
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

local function move_current_buffer_to_new_right_split()
  local buf = current_window_buffer()

  if not buf then
    return
  end

  local source_win = vim.api.nvim_get_current_win()
  open_buffer_in_right_split(buf)
  leave_window_tab(source_win, buf)
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


local function map_terminal_shortcut(buf, lhses, rhs, desc)
  for _, lhs in ipairs(lhses) do
    vim.keymap.set({ "n", "t" }, lhs, rhs, {
      buffer = buf,
      silent = true,
      desc = desc,
    })
  end
end

_G.terminal_paste_text = _G.terminal_paste_text or ""

function _G.copy_to_system_clipboard(text)
  if text == "" then
    return
  end

  _G.terminal_paste_text = text
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
end

function _G.yank_terminal_selection()
  vim.cmd([[normal! "zy]])
  local text = vim.fn.getreg("z")
  if text == "" then
    return
  end

  _G.copy_to_system_clipboard(text)

  if vim.bo.buftype == "terminal" then
    vim.cmd("startinsert")
  end
end

function _G.paste_clipboard_into_terminal()
  local buf = vim.api.nvim_get_current_buf()
  local job_id = vim.b[buf].terminal_job_id

  if not job_id then
    return
  end

  local text = _G.terminal_paste_text or ""
  if text == "" then
    return
  end

  vim.api.nvim_chan_send(job_id, text)
  vim.cmd("startinsert")
end

function _G.apply_terminal_clipboard_keymaps(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal") then
    return
  end

  vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { buffer = buf, silent = true, desc = "Exit terminal mode" })
  vim.keymap.set("n", "Y", "ggVGy", { buffer = buf, silent = true, desc = "Yank entire terminal buffer" })
  vim.keymap.set("x", "y", _G.yank_terminal_selection, { buffer = buf, silent = true, desc = "Yank terminal selection" })
  vim.keymap.set("x", "Y", _G.yank_terminal_selection, { buffer = buf, silent = true, desc = "Yank terminal selection" })

  vim.keymap.set("n", "p", _G.paste_clipboard_into_terminal, {
    buffer = buf,
    silent = true,
    desc = "Paste clipboard into terminal",
  })

  for _, lhs in ipairs({ "<C-v>", "<C-S-v>", "<D-v>" }) do
    vim.keymap.set({ "n", "t" }, lhs, _G.paste_clipboard_into_terminal, {
      buffer = buf,
      silent = true,
      desc = "Paste clipboard into terminal",
    })
  end
end

function _G.handle_terminal_osc52(args)
  local data = args and args.data or {}
  local sequence = data.sequence or ""
  local encoded = sequence:match("\027%]52;[^;]*;([A-Za-z0-9+/=]+)")

  if not encoded or encoded == "" then
    return
  end

  local ok, decoded = pcall(vim.base64.decode, encoded)
  if not ok or not decoded or decoded == "" then
    return
  end

  _G.copy_to_system_clipboard(decoded)
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
  table.insert(parts, "  Ctrl-1..9 jump  F4+Up/Down resize  ,tn new  ,th/,tl nav  ,tr rename  Ctrl-w close  :copybot copy")

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

local function resize_bottom_terminal(delta)
  local max_height = math.max(4, vim.o.lines - 8)
  terminal_state.height = math.min(max_height, math.max(4, terminal_state.height + delta))

  if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
    pcall(vim.api.nvim_win_set_height, terminal_state.win, terminal_state.height)
    configure_terminal_window(terminal_state.win)
    update_terminal_winbar()
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

move_file_buffer_out_of_terminal_window = function()
  if not (terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win)) then
    return
  end

  local win = terminal_state.win
  local buf = vim.api.nvim_win_get_buf(win)

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if vim.bo[buf].buftype == "terminal" or vim.bo[buf].filetype == "NvimTree" or (_empty_buf and buf == _empty_buf) then
    return
  end

  local target_win = find_editor_window()

  if not target_win or not vim.api.nvim_win_is_valid(target_win) or target_win == win then
    vim.api.nvim_set_current_win(win)
    vim.cmd("aboveleft split")
    target_win = vim.api.nvim_get_current_win()
  end

  vim.api.nvim_win_set_buf(target_win, buf)
  render_window_header(target_win)

  local replacement = terminal_state.current and terminal_state.buffers[terminal_state.current] or nil
  if replacement and replacement ~= buf and vim.api.nvim_buf_is_valid(replacement) then
    set_terminal_buffer_keymaps(replacement)
    vim.api.nvim_win_set_buf(win, replacement)
  else
    vim.api.nvim_win_set_buf(win, get_empty_buf())
  end

  configure_terminal_window(win)
  update_terminal_winbar()
  vim.api.nvim_set_current_win(target_win)
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

new_terminal_tab = function(cwd)
  local win = ensure_terminal_window()
  vim.api.nvim_set_current_win(win)

  local restore_cwd
  if cwd and cwd ~= "" then
    restore_cwd = vim.fn.getcwd()
    if vim.fn.fnamemodify(restore_cwd, ":p") ~= vim.fn.fnamemodify(cwd, ":p") then
      vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
    else
      restore_cwd = nil
    end
  end

  vim.cmd("terminal")

  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = "hide"
  set_terminal_buffer_keymaps(buf)
  table.insert(terminal_state.buffers, buf)
  terminal_state.current = #terminal_state.buffers

  configure_terminal_window(win)
  update_terminal_winbar()

  if restore_cwd then
    pcall(vim.cmd, "lcd " .. vim.fn.fnameescape(restore_cwd))
  end

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

set_terminal_buffer_keymaps = function(buf)
  map_terminal_shortcut(buf, { "<C-t>" }, new_terminal_tab, "New terminal tab")
  map_terminal_shortcut(buf, { "<C-w>" }, close_current_terminal, "Close terminal tab")
  _G.apply_terminal_clipboard_keymaps(buf)
end

vim.api.nvim_create_autocmd("TermOpen", {
  group = augroup,
  callback = function(args)
    _G.apply_terminal_clipboard_keymaps(args.buf)
  end,
})

vim.api.nvim_create_autocmd("TermRequest", {
  group = augroup,
  callback = _G.handle_terminal_osc52,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup,
  callback = function()
    local event = vim.v.event or {}
    local contents = event.regcontents
    if not contents or vim.tbl_isempty(contents) then
      return
    end

    _G.terminal_paste_text = table.concat(contents, "\n")
  end,
})

vim.keymap.set({ "n", "t" }, "<F4>", toggle_bottom_terminal, {
  desc = "Toggle terminal panel",
})
vim.keymap.set({ "n", "t" }, "<F4><Up>", function()
  resize_bottom_terminal(2)
end, {
  silent = true,
  desc = "Raise terminal panel",
})
vim.keymap.set({ "n", "t" }, "<F4><Down>", function()
  resize_bottom_terminal(-2)
end, {
  silent = true,
  desc = "Lower terminal panel",
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

local function copybot_fn()
  local buf = terminal_state.current and terminal_state.buffers[terminal_state.current]
  capture_terminal_output(buf)
  if vim.fn.filereadable(last_output_file) == 1 then
    local content = table.concat(vim.fn.readfile(last_output_file), "\n")
    _G.copy_to_system_clipboard(content)
  else
    vim.notify("Copybot: no terminal output to copy", vim.log.levels.WARN)
  end
end

vim.keymap.set({ "n", "t" }, "<leader>ty", copybot_fn, {
  silent = true,
  desc = "Capture terminal output to clipboard and $NVIM_LAST_OUTPUT",
})

vim.api.nvim_create_user_command("Copybot", copybot_fn, {
  desc = "Copy last bottom terminal output to clipboard",
})
vim.cmd("cabbrev copybot Copybot")

-- ============================================================================
-- DEBUGGING
-- ============================================================================

local dap = require("dap")
local dapui = require("dapui")
local dapui_util = require("dapui.util")
local dapui_format_value = dapui_util.format_value
local inspect_debug_expression

vim.g.dapui_show_variable_values = true

local function tensor_shape_from_value(value)
  if type(value) ~= "string" then
    return nil
  end

  local text = vim.trim(value)
  if not (text:match("^tensor%(") or text:match("^Tensor%(") or text:match("^torch%.Tensor%(")) then
    return nil
  end

  local open = text:find("%[")
  if not open then
    return "()"
  end

  local function trim(s)
    return vim.trim(s or "")
  end

  local function parse_list(s, i)
    local items = {}
    local item_start = i + 1
    local depth = 0
    i = i + 1

    while i <= #s do
      local ch = s:sub(i, i)

      if ch == "[" then
        depth = depth + 1
      elseif ch == "]" then
        if depth == 0 then
          local item = trim(s:sub(item_start, i - 1))
          if item ~= "" then
            items[#items + 1] = item
          end
          return items, i + 1
        end
        depth = depth - 1
      elseif ch == "," and depth == 0 then
        local item = trim(s:sub(item_start, i - 1))
        if item ~= "" then
          items[#items + 1] = item
        end
        item_start = i + 1
      end

      i = i + 1
    end
  end

  local shape_from_repr

  local function shape_of_list(items)
    if #items == 0 then
      return { 0 }
    end

    local child_shape = nil
    for _, item in ipairs(items) do
      if item:sub(1, 1) ~= "[" then
        return { #items }
      end

      local child = shape_from_repr(item)
      if not child then
        return { #items }
      end

      if not child_shape then
        child_shape = child
      else
        if #child_shape ~= #child then
          return { #items }
        end
        for idx = 1, #child_shape do
          if child_shape[idx] ~= child[idx] then
            return { #items }
          end
        end
      end
    end

    local shape = { #items }
    if child_shape then
      for _, dim in ipairs(child_shape) do
        shape[#shape + 1] = dim
      end
    end
    return shape
  end

  shape_from_repr = function(s)
    local items = parse_list(s, 1)
    if not items then
      return nil
    end
    return shape_of_list(items)
  end

  local shape = shape_from_repr(text:sub(open))
  if not shape or #shape == 0 then
    return nil
  end

  return "(" .. table.concat(shape, ", ") .. ")"
end

local function tensor_summary_from_value(value)
  local shape = tensor_shape_from_value(value)
  if not shape then
    return nil
  end

  local dtype = value:match("dtype=([^,%)]*)")
  local device = value:match("device=([^,%)]*)")
  local parts = { "torch.Tensor(shape=" .. shape }

  if dtype and dtype ~= "" then
    parts[#parts + 1] = "dtype=" .. vim.trim(dtype)
  end

  if device and device ~= "" then
    parts[#parts + 1] = "device=" .. vim.trim(device)
  end

  return table.concat(parts, ", ") .. ")"
end

local function is_debug_dict(variable)
  local var_type = tostring(variable.type or ""):lower()
  local value = vim.trim(variable.value or "")
  return var_type == "dict" or value:match("^dict%s*=") or value:match("^%{.*%}$")
end

local function is_debug_tensor(variable)
  local var_type = tostring(variable.type or "")
  local value = vim.trim(variable.value or "")
  return var_type:match("Tensor") or value:match("^tensor%(") or value:match("^Tensor%(") or value:match("^torch%.Tensor%(")
end

function _G.is_debug_dataframe(variable)
  local var_type = tostring(variable.type or ""):lower()
  local value = vim.trim(variable.value or "")
  return var_type:match("dataframe")
    or var_type:match("series")
    or value:match("^['\"]DataFrame%s+`") ~= nil
    or value:match("^['\"]Series%s+`") ~= nil
    or value:match("%[%d+ rows x %d+ columns%]") ~= nil
end

local function tensor_summary_for_variable(variable)
  return tensor_summary_from_value(variable.value or "") or "torch.Tensor"
end

local function torch_summary_expression(expr)
  expr = vim.trim(expr):gsub("\n", " ")

  local template = [[(lambda __x: (("torch.Tensor(shape=%%s, dtype=%%s, device=%%s, requires_grad=%%s, numel=%%s)" %% (tuple(__x.shape), __x.dtype, __x.device, getattr(__x, "requires_grad", False), __x.numel())) if (__import__("sys").modules.get("torch") is not None and isinstance(__x, __import__("sys").modules["torch"].Tensor)) else __import__("pprint").pformat(__x, width=120, compact=False)))(%s)]]
  return template:format(expr)
end

function _G.dataframe_summary_expression(expr)
  expr = vim.trim(expr):gsub("\n", " ")

  local template = [[(lambda __x, __shape, __clean: ((("DataFrame `%s`\nshape=%%s index=%%s columns=%%s memory=%%s\n%%s") %% (tuple(__x.shape), type(__x.index).__name__, len(__x.columns), (str(int(__x.memory_usage(deep=True).sum())) + " bytes") if hasattr(__x, "memory_usage") else "?", "\n".join([("  %%2d. %%s: dtype=%%s series_shape=%%s cell_shape=%%s non_null=%%s nulls=%%s" %% (__i + 1, __clean(__c), str(__x[__c].dtype), tuple(__x[__c].shape), __shape(__x[__c].dropna().iloc[0]) if hasattr(__x[__c], "dropna") and len(__x[__c].dropna()) else "-", str(int(__x[__c].notna().sum())) if hasattr(__x[__c], "notna") else "?", str(int(__x[__c].isna().sum())) if hasattr(__x[__c], "isna") else "?")) for __i, __c in enumerate(__x.columns)]))) if hasattr(__x, "columns") and hasattr(__x, "dtypes") and hasattr(__x, "shape") else (("Series `%s`\nshape=%%s dtype=%%s name=%%s index=%%s non_null=%%s nulls=%%s memory=%%s") %% (tuple(__x.shape), getattr(__x, "dtype", "?"), getattr(__x, "name", None), type(__x.index).__name__ if hasattr(__x, "index") else "?", str(int(__x.notna().sum())) if hasattr(__x, "notna") else "?", str(int(__x.isna().sum())) if hasattr(__x, "isna") else "?", (str(int(__x.memory_usage(deep=True))) + " bytes") if hasattr(__x, "memory_usage") else "?")) if hasattr(__x, "dtype") and hasattr(__x, "shape") else ("Not a pandas DataFrame/Series: " + type(__x).__module__ + "." + type(__x).__name__)))(%s, lambda __v: str(tuple(__v.shape)) if hasattr(__v, "shape") else (str((len(__v),)) if isinstance(__v, (list, tuple)) else type(__v).__name__), lambda __v: str(__v).replace("\n", "\\n"))]]
  return template:format(expr, expr, expr)
end

function _G.decode_debugpy_string_result(value)
  value = tostring(value or "")

  if #value >= 2 then
    local quote = value:sub(1, 1)
    if (quote == "'" or quote == '"') and value:sub(-1) == quote then
      value = value:sub(2, -2)
    end
  end

  local escaped_backslash = string.char(31)
  value = value
    :gsub("\\\\", escaped_backslash)
    :gsub("\\n", "\n")
    :gsub("\\t", "\t")
    :gsub("\\r", "\r")
    :gsub("\\'", "'")
    :gsub('\\"', '"')
    :gsub(escaped_backslash, "\\")

  return value
end

function _G.evaluate_dataframe_summary(client, variable)
  if not variable.evaluateName then
    return { "pandas." .. tostring(variable.type or "DataFrame") }
  end

  local frame_id = client.session and client.session.current_frame and client.session.current_frame.id
  local ok, response = pcall(client.request.evaluate, {
    expression = _G.dataframe_summary_expression(variable.evaluateName),
    frameId = frame_id,
    context = "variables",
  })

  if ok and response and response.result and response.result ~= "" then
    return vim.split(_G.decode_debugpy_string_result(response.result), "\n", { plain = true })
  end

  return { "pandas." .. tostring(variable.type or "DataFrame") }
end

local function evaluate_tensor_summary(client, variable)
  if not variable.evaluateName then
    return tensor_summary_for_variable(variable)
  end

  local frame_id = client.session and client.session.current_frame and client.session.current_frame.id
  local ok, response = pcall(client.request.evaluate, {
    expression = torch_summary_expression(variable.evaluateName),
    frameId = frame_id,
    context = "variables",
  })

  if ok and response and response.result and response.result ~= "" then
    return response.result
  end

  return tensor_summary_for_variable(variable)
end

local function split_top_level_items(text, item_separator)
  local items = {}
  local depth = 0
  local quote = nil
  local escaped = false
  local start = 1

  for i = 1, #text do
    local ch = text:sub(i, i)

    if quote then
      if escaped then
        escaped = false
      elseif ch == "\\" then
        escaped = true
      elseif ch == quote then
        quote = nil
      end
    elseif ch == "'" or ch == '"' then
      quote = ch
    elseif ch == "{" or ch == "[" or ch == "(" then
      depth = depth + 1
    elseif ch == "}" or ch == "]" or ch == ")" then
      depth = math.max(depth - 1, 0)
    elseif ch == item_separator and depth == 0 then
      items[#items + 1] = vim.trim(text:sub(start, i - 1))
      start = i + 1
    end
  end

  local tail = vim.trim(text:sub(start))
  if tail ~= "" then
    items[#items + 1] = tail
  end

  return items
end

local function find_top_level_separator(text, separator)
  local depth = 0
  local quote = nil
  local escaped = false

  for i = 1, #text do
    local ch = text:sub(i, i)

    if quote then
      if escaped then
        escaped = false
      elseif ch == "\\" then
        escaped = true
      elseif ch == quote then
        quote = nil
      end
    elseif ch == "'" or ch == '"' then
      quote = ch
    elseif ch == "{" or ch == "[" or ch == "(" then
      depth = depth + 1
    elseif ch == "}" or ch == "]" or ch == ")" then
      depth = math.max(depth - 1, 0)
    elseif ch == separator and depth == 0 then
      return i
    end
  end

  return nil
end

local function summarize_nested_tensors(text)
  local result = {}
  local i = 1

  while i <= #text do
    local start_pos, open_pos = text:find("tensor%(", i)
    if not start_pos then
      result[#result + 1] = text:sub(i)
      break
    end

    result[#result + 1] = text:sub(i, start_pos - 1)

    local depth = 1
    local j = open_pos + 1
    while j <= #text and depth > 0 do
      local ch = text:sub(j, j)
      if ch == "(" then
        depth = depth + 1
      elseif ch == ")" then
        depth = depth - 1
      end
      j = j + 1
    end

    local tensor_text = text:sub(start_pos, j - 1)
    result[#result + 1] = tensor_summary_from_value(tensor_text) or "torch.Tensor(...)"
    i = j
  end

  return table.concat(result)
end

local function format_dict_value(value)
  if type(value) ~= "string" then
    return nil
  end

  local text = vim.trim(value)
  text = vim.trim(text:gsub("^dict%s*=%s*", "", 1))
  if not (text:sub(1, 1) == "{" and text:sub(-1) == "}") then
    return nil
  end

  local inner = vim.trim(text:sub(2, -2))
  if inner == "" then
    return { "{}" }
  end

  local items = split_top_level_items(inner, ",")
  if #items <= 1 then
    return nil
  end

  local lines = { "{" }
  for idx, item in ipairs(items) do
    local separator = find_top_level_separator(item, ":")
    local formatted = summarize_nested_tensors(item)

    if separator then
      local key = vim.trim(item:sub(1, separator - 1))
      local item_value = summarize_nested_tensors(vim.trim(item:sub(separator + 1)))
      formatted = key .. ": " .. item_value
    end

    local suffix = idx < #items and "," or ""
    lines[#lines + 1] = "  " .. formatted .. suffix
  end
  lines[#lines + 1] = "}"

  return lines
end

dapui_util.format_value = function(value_start, value)
  if not vim.g.dapui_show_variable_values then
    return { "<hidden>" }
  end

  local decoded_dataframe = _G.decode_debugpy_string_result(value)
  if decoded_dataframe:match("^DataFrame%s+`") or decoded_dataframe:match("^Series%s+`") then
    return vim.split(decoded_dataframe, "\n", { plain = true })
  end

  local tensor_summary = tensor_summary_from_value(value)
  if tensor_summary then
    return { tensor_summary }
  end

  return format_dict_value(value) or dapui_format_value(value_start, value)
end


package.loaded["dapui.components.variables"] = nil
package.preload["dapui.components.variables"] = function()
  local config = require("dapui.config")
  local util = require("dapui.util")
  local partial = util.partial
  local nio = require("nio")

  return function(client, send_ready)
    local expanded_children = {}
    local partial_loads = {}  -- var_path -> indexedVariables count when using truncated load
    local MAX_INDEXED = 100   -- threshold: more indexed children than this triggers partial load
    local prompt_func
    local prompt_fill
    local rendered_vars = {}

    local function reference_prefix(path, variable)
      if variable.variablesReference == 0 then
        return " "
      end
      return config.icons[expanded_children[path] and "expanded" or "collapsed"]
    end

    local function path_changed(path, value)
      return rendered_vars[path] and rendered_vars[path] ~= value
    end

    local function render(canvas, parent_path, parent_ref, indent, use_partial)
      if not canvas.prompt and prompt_func then
        canvas:set_prompt("> ", prompt_func, { fill = prompt_fill })
      end

      indent = indent or 0
      local req = { variablesReference = parent_ref }
      if use_partial then
        req.filter = "indexed"
        req.start = 0
        req.count = 1
      end
      local success, var_data = pcall(client.request.variables, req)
      local variables = success and var_data.variables or {}

      if config.render.sort_variables then
        table.sort(variables, config.render.sort_variables)
      end

      for _, variable in pairs(variables) do
        local var_path = parent_path .. "." .. variable.name

        canvas:write({
          string.rep(" ", indent),
          { reference_prefix(var_path, variable), group = "DapUIDecoration" },
          " ",
          { variable.name, group = "DapUIVariable" },
        })

        local var_type = util.render_type(variable.type)
        if #var_type > 0 then
          canvas:write({ " ", { var_type, group = "DapUIType" } })
        end

        local var_group
        if path_changed(var_path, variable.value) then
          var_group = "DapUIModifiedValue"
        else
          var_group = "DapUIValue"
        end
        rendered_vars[var_path] = variable.value

        local function add_var_line(line)
          if variable.variablesReference > 0 then
            canvas:add_mapping("expand", function()
              if not expanded_children[var_path] then
                expanded_children[var_path] = true
                local idx = variable.indexedVariables or 0
                if idx > MAX_INDEXED then
                  partial_loads[var_path] = idx
                end
              else
                expanded_children[var_path] = false
                partial_loads[var_path] = nil
              end
              send_ready()
            end)
            if variable.evaluateName then
              canvas:add_mapping("repl", partial(util.send_to_repl, variable.evaluateName))
              canvas:add_mapping("watch", partial(util.send_to_watches, variable.evaluateName))
            end
          end
          canvas:add_mapping("edit", function()
            prompt_func = function(new_value)
              nio.run(function()
                prompt_func = nil
                prompt_fill = nil
                client.lib.set_variable(parent_ref, variable, new_value)
                send_ready()
              end)
            end
            prompt_fill = variable.value
            send_ready()
          end)
          canvas:write(line .. "\n", { group = var_group })
        end

        local has_value = #(variable.value or "") > 0
        local show_value = has_value and (variable.variablesReference == 0 or expanded_children[var_path])
        local formatted_value_override = nil

        if is_debug_tensor(variable) then
          show_value = true
          formatted_value_override = { evaluate_tensor_summary(client, variable) }
        elseif _G.is_debug_dataframe(variable) then
          show_value = true
          formatted_value_override = _G.evaluate_dataframe_summary(client, variable)
        elseif is_debug_dict(variable) and variable.variablesReference > 0 then
          show_value = true
          formatted_value_override = { "{...}" }
        end

        if show_value then
          canvas:write(" = ")
          local value_start = #canvas.lines[canvas:length()]

          for _, line in ipairs(formatted_value_override or util.format_value(value_start, variable.value)) do
            add_var_line(line)
          end
        else
          add_var_line("")
        end

        if expanded_children[var_path] and variable.variablesReference ~= 0 then
          if partial_loads[var_path] then
            render(canvas, var_path, variable.variablesReference, indent + config.render.indent, true)
            canvas:write(
              string.rep(" ", indent + config.render.indent + 2) ..
              "(partial: [0] of " .. partial_loads[var_path] .. " — :DapInspectVariable for full view)\n",
              { group = "Comment" }
            )
          else
            render(canvas, var_path, variable.variablesReference, indent + config.render.indent)
          end
        end
      end
    end

    return {
      render = render,
    }
  end
end

dapui.setup({
  expand_lines = true,
  icons = {
    expanded = "▾",
    collapsed = "▸",
    current_frame = "▸",
  },
  mappings = {
    edit = "e",
    expand = { "<CR>", "<Space>", "l", "za", "<2-LeftMouse>" },
    open = "o",
    remove = "d",
    repl = "r",
    toggle = "t",
  },
  layouts = {
    {
      elements = {
        { id = "scopes", size = 0.55 },
        { id = "watches", size = 0.20 },
        { id = "stacks", size = 0.15 },
        { id = "breakpoints", size = 0.10 },
      },
      position = "left",
      size = math.floor(vim.o.columns * 0.25),
    },
    {
      elements = {
        { id = "repl", size = 0.35 },
        { id = "console", size = 0.65 },
      },
      position = "bottom",
      size = 12,
    },
  },
  render = {
    indent = 2,
    max_type_length = nil,
    max_value_lines = 20,
  },
  floating = {
    border = "rounded",
    mappings = {
      close = { "<C-q>", "q", "<Esc>" },
    },
  },
})

local dapui_readable_filetypes = {
  ["dap-repl"] = true,
  dapui_breakpoints = true,
  dapui_console = true,
  dapui_scopes = true,
  dapui_stacks = true,
  dapui_watches = true,
}

local dapui_left_filetypes = {
  dapui_breakpoints = true,
  dapui_scopes = true,
  dapui_stacks = true,
  dapui_watches = true,
}

function _G.enable_debug_source_line_numbers(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].number = true
    vim.wo[win].relativenumber = true
    vim.wo[win].signcolumn = "yes"
  end
end

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  group = augroup,
  callback = function(args)
    local win = vim.api.nvim_get_current_win()
    local buf = args.buf or vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    local ft = vim.bo[buf].filetype

    if name:match("^dap%-src://") or (ft ~= "" and not dapui_readable_filetypes[ft] and dap.session()) then
      _G.enable_debug_source_line_numbers(win)
    end
  end,
})

local function debug_sidebar_width()
  return math.max(1, math.floor(vim.o.columns * 0.25))
end

local function resize_debug_sidebar()
  local width = debug_sidebar_width()

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)

      if dapui_left_filetypes[vim.bo[buf].filetype] then
        pcall(vim.api.nvim_win_set_width, win, width)
      end
    end
  end
end

local function inspect_debug_word_under_cursor()
  local expr = vim.fn.expand("<cword>")

  vim.ui.input({ prompt = "DAP inspect expression: ", default = expr }, function(input)
    if inspect_debug_expression then
      inspect_debug_expression(input)
    end
  end)
end

local function configure_dapui_windows(buf)
  local wins = buf and vim.fn.win_findbuf(buf) or vim.api.nvim_tabpage_list_wins(0)

  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local wbuf = vim.api.nvim_win_get_buf(win)

      if dapui_readable_filetypes[vim.bo[wbuf].filetype] then
        vim.wo[win].number = false
        vim.wo[win].relativenumber = false
        vim.wo[win].signcolumn = "no"
        vim.wo[win].cursorline = true
        vim.wo[win].wrap = true
        vim.wo[win].linebreak = true
        vim.wo[win].breakindent = true

        if dapui_left_filetypes[vim.bo[wbuf].filetype] then
          pcall(vim.api.nvim_win_set_width, win, debug_sidebar_width())
        end

        if vim.bo[wbuf].filetype == "dapui_breakpoints" then
          vim.keymap.set("n", "<CR>", "o", { buffer = wbuf, remap = true, silent = true, desc = "Open breakpoint source" })
          vim.keymap.set("n", "x", "d", { buffer = wbuf, remap = true, silent = true, desc = "Remove breakpoint" })
          vim.keymap.set("n", "<Space>", "t", { buffer = wbuf, remap = true, silent = true, desc = "Toggle breakpoint" })
        end

        if vim.bo[wbuf].filetype == "dapui_scopes" or vim.bo[wbuf].filetype == "dapui_watches" then
          vim.keymap.set("n", "i", inspect_debug_word_under_cursor, { buffer = wbuf, silent = true, desc = "Inspect debug variable" })
        end
      end
    end
  end
end

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
  group = augroup,
  callback = function(args)
    if dapui_readable_filetypes[vim.bo[args.buf].filetype] then
      vim.schedule(function()
        configure_dapui_windows(args.buf)
      end)
    end
  end,
})

vim.api.nvim_create_autocmd("VimResized", {
  group = augroup,
  callback = function()
    vim.schedule(resize_debug_sidebar)
  end,
})

local pending_debug_source = nil

local function is_debug_source_window(win)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype

  return vim.bo[buf].buftype ~= "terminal" and ft ~= "NvimTree" and not dapui_readable_filetypes[ft]
end

local function focus_debug_source(path, line)
  if not path or path == "" then
    return
  end

  local expanded = vim.fn.fnamemodify(vim.fn.expand(path), ":p")

  if vim.fn.filereadable(expanded) ~= 1 then
    return
  end

  local bufnr = vim.fn.bufadd(expanded)
  vim.fn.bufload(bufnr)

  local target_win = nil
  local current_win = vim.api.nvim_get_current_win()
  local current_is_source = is_debug_source_window(current_win)

  if current_is_source then
    target_win = current_win
  else
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if is_debug_source_window(win) then
        target_win = win
        break
      end
    end
  end

  if not target_win then
    return
  end

  vim.api.nvim_win_set_buf(target_win, bufnr)
  _G.enable_debug_source_line_numbers(target_win)

  vim.api.nvim_set_current_win(target_win)
  pcall(vim.api.nvim_win_set_cursor, target_win, { math.max(line or 1, 1), 0 })
  vim.cmd("normal! zz")
end

local function set_debug_source(path, label)
  pending_debug_source = path
  focus_debug_source(path)

  local display = path and vim.fn.fnamemodify(path, ":~:.") or "remote attach"
  vim.notify("DAP: debugging " .. display, vim.log.levels.INFO, { title = label or "Debug" })
end

-- Entering debug mode should remove normal IDE furniture and keep crash output
-- visible until F11 explicitly closes the debug UI.
local set_debug_mode_keymaps

local dap_restore_state = {
  layout = nil,
  tree = false,
  terminal = false,
  tree_width = nil,
}

local function nvim_tree_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)

      if vim.bo[buf].filetype == "NvimTree" then
        return win
      end
    end
  end

  return nil
end

local function restore_bottom_terminal_window()
  prune_terminal_buffers()

  if #terminal_state.buffers == 0 then
    return
  end

  local previous_win = vim.api.nvim_get_current_win()
  local win = ensure_terminal_window()
  local buf = terminal_state.buffers[terminal_state.current or 1]

  if not buf then
    return
  end

  if set_terminal_buffer_keymaps then
    set_terminal_buffer_keymaps(buf)
  end

  vim.api.nvim_win_set_buf(win, buf)
  configure_terminal_window(win)
  pcall(vim.api.nvim_win_set_height, win, terminal_state.height)
  update_terminal_winbar()

  if vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
end

local function normalize_restored_code_layout()
  if dap_restore_state.tree_width then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok and api.tree and api.tree.resize then
      pcall(api.tree.resize, { absolute = dap_restore_state.tree_width })
    else
      local tree_win = nvim_tree_win()
      if tree_win then
        pcall(vim.api.nvim_win_set_width, tree_win, dap_restore_state.tree_width)
      end
    end
  end

  if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
    configure_terminal_window(terminal_state.win)
    pcall(vim.api.nvim_win_set_height, terminal_state.win, terminal_state.height)
    update_terminal_winbar()
  end

  vim.cmd("wincmd =")

  if dap_restore_state.tree_width then
    local tree_win = nvim_tree_win()
    if tree_win then
      pcall(vim.api.nvim_win_set_width, tree_win, dap_restore_state.tree_width)
    end
  end

  if terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) then
    pcall(vim.api.nvim_win_set_height, terminal_state.win, terminal_state.height)
  end
end

local function hide_debug_distractions()
  local tree_win = nvim_tree_win()
  dap_restore_state.tree = tree_win ~= nil
  dap_restore_state.terminal = terminal_state.win and vim.api.nvim_win_is_valid(terminal_state.win) or false
  dap_restore_state.tree_width = tree_win and vim.api.nvim_win_get_width(tree_win) or nil

  if dap_restore_state.terminal then
    terminal_state.height = vim.api.nvim_win_get_height(terminal_state.win)
  end

  if dap_restore_state.tree then
    pcall(vim.cmd, "NvimTreeClose")
  end

  if dap_restore_state.terminal then
    local buf = terminal_state.current and terminal_state.buffers[terminal_state.current]

    if buf and capture_terminal_output then
      capture_terminal_output(buf)
    end

    vim.api.nvim_win_hide(terminal_state.win)
    terminal_state.win = nil
  end
end

local function collapse_to_one_debug_source_window()
  local keep_win = nil
  local current_win = vim.api.nvim_get_current_win()

  if is_debug_source_window(current_win) then
    keep_win = current_win
  else
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if is_debug_source_window(win) then
        keep_win = win
        break
      end
    end
  end

  if not keep_win then
    return
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= keep_win and is_debug_source_window(win) then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end

  if vim.api.nvim_win_is_valid(keep_win) then
    vim.api.nvim_set_current_win(keep_win)
  end
end

local function restore_debug_distractions()
  local restore_tree = dap_restore_state.tree
  local restore_terminal = dap_restore_state.terminal

  dap_restore_state.tree = false
  dap_restore_state.terminal = false

  if restore_tree then
    pcall(vim.cmd, "NvimTreeOpen")
  end

  if restore_terminal then
    restore_bottom_terminal_window()
  end

  vim.defer_fn(normalize_restored_code_layout, 20)
end

local function dapui_open_keep_layout()
  if not dap_restore_state.layout then
    dap_restore_state.layout = true
    hide_debug_distractions()
    collapse_to_one_debug_source_window()
  end

  set_debug_mode_keymaps(true)
  dapui.open()
  vim.schedule(function()
    configure_dapui_windows()
    resize_debug_sidebar()
    focus_debug_source(pending_debug_source)
  end)
end

local function dapui_close_restore_layout()
  dapui.close()
  set_debug_mode_keymaps(false)

  if not dap_restore_state.layout then
    restore_debug_distractions()
    vim.defer_fn(function()
      dap_restore_state.tree_width = nil
    end, 80)
    return
  end

  dap_restore_state.layout = nil

  -- Defer so dapui windows are fully gone before recreating normal UI windows.
  vim.schedule(function()
    restore_debug_distractions()
    vim.defer_fn(function()
      normalize_restored_code_layout()
      dap_restore_state.tree_width = nil
    end, 60)
  end)
end

dap.listeners.before.attach.dapui_auto_open = dapui_open_keep_layout
dap.listeners.before.launch.dapui_auto_open = dapui_open_keep_layout

-- ── debug keybinding hint window ─────────────────────────────────────────────

local debug_hint_win = nil
local debug_hint_buf = nil
-- Live location of the paused thread. nil before the first stop; { running = true }
-- while the program is executing; otherwise { func, file, line, reason }.
local debug_location = nil

local function debug_key_list(lhses)
  if lhses == nil or lhses == false then return {} end
  if type(lhses) == "table" then return lhses end
  return { lhses }
end

local function debug_key_label(lhses)
  return table.concat(debug_key_list(lhses), " / ")
end

local function debug_hint_keys()
  local keys = require("exocortex.config_loader").keys("debug")
  return {
    string.format(" %-18s Continue", debug_key_label(keys.start_continue)),
    string.format(" %-18s Breakpoint", debug_key_label(keys.toggle_breakpoint)),
    string.format(" %-18s Step into", debug_key_label(keys.step_into)),
    string.format(" %-18s Step over", debug_key_label(keys.step_over)),
    string.format(" %-18s Step out", debug_key_label(keys.step_out)),
    string.format(" %-18s Kill session", debug_key_label(keys.stop)),
    string.format(" %-18s Close UI", debug_key_label(keys.close_ui)),
    string.format(" %-18s Page up", debug_key_label(keys.debug_nav_up)),
    string.format(" %-18s Page down", debug_key_label(keys.debug_nav_down)),
    string.format(" %-18s Cursor left", debug_key_label(keys.debug_nav_left)),
    string.format(" %-18s Cursor right", debug_key_label(keys.debug_nav_right)),
    string.format(" %-18s Show UI", debug_key_label(keys.show_ui)),
    string.format(" %-18s Variables", debug_key_label(keys.variables)),
    string.format(" %-18s Watches", debug_key_label(keys.watches)),
    string.format(" %-18s Console", debug_key_label(keys.console)),
    string.format(" %-18s Inspect", debug_key_label(keys.inspect)),
    string.format(" %-18s DataFrame", debug_key_label(keys.dataframe)),
    string.format(" %-18s Current fn", debug_key_label(keys.current_function)),
    string.format(" %-18s Values", debug_key_label(keys.toggle_values)),
    string.format(" %-18s View mask", debug_key_label(keys.view_mask)),
  }
end

local debug_mode_keymaps_active = false
local debug_mode_saved_keymaps = {}

set_debug_mode_keymaps = function(enabled)
  if enabled == debug_mode_keymaps_active then
    return
  end

  debug_mode_keymaps_active = enabled

  local keys = require("exocortex.config_loader").keys("debug")
  local maps = {
    { keys.debug_nav_left, "<Left>" },
    { keys.debug_nav_right, "<Right>" },
  }
  local expanded = {}

  for _, map in ipairs(maps) do
    for _, lhs in ipairs(debug_key_list(map[1])) do
      if lhs and lhs ~= "" then
        expanded[#expanded + 1] = { lhs, map[2] }
      end
    end
  end

  if enabled then
    debug_mode_saved_keymaps = {}

    for _, map in ipairs(expanded) do
      local lhs, rhs = map[1], map[2]
      local existing = vim.fn.maparg(lhs, "n", false, true)
      if type(existing) == "table" and next(existing) ~= nil then
        debug_mode_saved_keymaps[lhs] = existing
      end

      vim.keymap.set("n", lhs, rhs, { silent = true, nowait = true, desc = "Debug navigation" })
    end
    return
  end

  for _, map in ipairs(expanded) do
    local lhs = map[1]
    pcall(vim.keymap.del, "n", lhs)

    local existing = debug_mode_saved_keymaps[lhs]
    if existing then
      pcall(vim.fn.mapset, "n", false, existing)
    end
  end

  debug_mode_saved_keymaps = {}
end

-- Rebuild the hint buffer from `debug_location` + the configured keymap list and
-- resize the floating window to fit. Called on open and on every stop/continue
-- so the "current function" header always reflects where the debugger is.
local function render_debug_hint()
  if not (debug_hint_buf and vim.api.nvim_buf_is_valid(debug_hint_buf)) then
    return
  end

  local lines = {}
  local loc_lines = 0

  if debug_location then
    if debug_location.running then
      lines = { "  ▶ running…" }
      loc_lines = 1
    else
      lines = {
        "  ▶ in " .. (debug_location.func or "?"),
        "    " .. (debug_location.file or "?") .. ":" .. (debug_location.line or 0),
      }
      if debug_location.exception then
        table.insert(lines, "  ✗ " .. debug_location.exception)
      end
      loc_lines = 2
    end
    table.insert(lines, "")
  end

  local title_idx = #lines
  table.insert(lines, "  DEBUG  ")
  vim.list_extend(lines, debug_hint_keys())

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end

  vim.bo[debug_hint_buf].modifiable = true
  vim.api.nvim_buf_set_lines(debug_hint_buf, 0, -1, false, lines)
  vim.bo[debug_hint_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(debug_hint_buf, -1, 0, -1)
  if loc_lines >= 1 then
    vim.api.nvim_buf_add_highlight(debug_hint_buf, -1, "DiagnosticWarn", 0, 0, -1)
  end
  if loc_lines >= 2 then
    vim.api.nvim_buf_add_highlight(debug_hint_buf, -1, "Comment", 1, 0, -1)
  end
  vim.api.nvim_buf_add_highlight(debug_hint_buf, -1, "Title", title_idx, 0, -1)

  if debug_hint_win and vim.api.nvim_win_is_valid(debug_hint_win) then
    vim.api.nvim_win_set_config(debug_hint_win, {
      relative = "editor",
      anchor = "NE",
      row = 1,
      col = vim.o.columns - 1,
      width = width,
      height = #lines,
    })
  end
end

-- Update the live location and refresh the hint window if it's open.
local function set_debug_location(loc)
  debug_location = loc
  render_debug_hint()
end

local function show_debug_current_function()
  if not debug_location then
    vim.notify("DAP: no stopped frame yet", vim.log.levels.WARN)
    return
  end

  if debug_location.running then
    vim.notify("DAP: program is running; pause or hit a breakpoint to see the current function", vim.log.levels.INFO)
    return
  end

  local func = debug_location.func or "?"
  local file = debug_location.file or "?"
  local line = debug_location.line or 0
  vim.notify(string.format("DAP: executing %s() at %s:%s", func, file, line), vim.log.levels.INFO, { title = "Debug current function" })
end

local function open_debug_hint()
  if debug_hint_win and vim.api.nvim_win_is_valid(debug_hint_win) then
    render_debug_hint()
    return
  end

  debug_hint_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[debug_hint_buf].bufhidden = "wipe"

  debug_hint_win = vim.api.nvim_open_win(debug_hint_buf, false, {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 1,
    width = 24,
    height = #debug_hint_keys() + 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 50,
  })

  vim.wo[debug_hint_win].winblend = 15

  render_debug_hint()
end

local function close_debug_hint()
  if debug_hint_win and vim.api.nvim_win_is_valid(debug_hint_win) then
    vim.api.nvim_win_close(debug_hint_win, true)
  end
  debug_hint_win = nil
  debug_hint_buf = nil
  debug_location = nil
end

dap.listeners.after.attach.debug_hint_open = function()
  vim.schedule(open_debug_hint)
end

dap.listeners.after.launch.debug_hint_open = function()
  vim.schedule(open_debug_hint)
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

vim.fn.sign_define("DapBreakpoint", {
  text = "●",
  texthl = "DiagnosticError",
  numhl = "DiagnosticError",
})

vim.fn.sign_define("DapBreakpointCondition", {
  text = "◆",
  texthl = "DiagnosticWarn",
  numhl = "DiagnosticWarn",
})

vim.fn.sign_define("DapLogPoint", {
  text = "◆",
  texthl = "DiagnosticInfo",
  numhl = "DiagnosticInfo",
})

vim.fn.sign_define("DapBreakpointRejected", {
  text = "×",
  texthl = "DiagnosticError",
  numhl = "DiagnosticError",
})

local dap_label_ns = vim.api.nvim_create_namespace("dap_stopped_label")
local dap_flash_ns = vim.api.nvim_create_namespace("dap_stopped_flash")
local dap_last_buf = nil
local debug_current_frame_id = nil
_G.debug_current_thread_id = nil
local docker_debug_status = nil

local function clear_dap_stopped_marks()
  if dap_last_buf and vim.api.nvim_buf_is_valid(dap_last_buf) then
    vim.api.nvim_buf_clear_namespace(dap_last_buf, dap_label_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(dap_last_buf, dap_flash_ns, 0, -1)
  end
  dap_last_buf = nil
end

local function compact_debug_text(text, max_len)
  text = vim.trim((text or ""):gsub("%s+", " "))
  if text == "" then
    return nil
  end

  max_len = max_len or 120
  if vim.fn.strdisplaywidth(text) <= max_len then
    return text
  end

  return vim.fn.strcharpart(text, 0, max_len - 1) .. "…"
end

local function format_exception_summary(exception_info)
  if type(exception_info) ~= "table" then
    return nil
  end

  local details = type(exception_info.details) == "table" and exception_info.details or {}
  local type_name = details.typeName or details.fullTypeName or exception_info.exceptionId
  local message = details.message or exception_info.description

  if type_name and message and type_name ~= "" and message ~= "" then
    return compact_debug_text(type_name .. ": " .. message, 140)
  end

  return compact_debug_text(type_name or message or exception_info.exceptionId or exception_info.description, 140)
end

local function request_exception_info(session, thread_id, callback)
  if not thread_id then
    callback(nil)
    return
  end

  session:request("exceptionInfo", { threadId = thread_id }, function(err, response)
    if err then
      callback(nil)
      return
    end

    callback(format_exception_summary(response))
  end)
end

-- On any pause (breakpoint, step, exception), jump the cursor to the stopped
-- line in the nearest editor window so the source is always in focus.
dap.listeners.after.event_stopped["jump_to_source"] = function(session, body)
  if not body.threadId then
    return
  end
  _G.debug_current_thread_id = body.threadId

  session:request("stackTrace", { threadId = body.threadId, startFrame = 0, levels = 1 }, function(err, response)
    if err or not response or not response.stackFrames or #response.stackFrames == 0 then
      return
    end

    local frame = response.stackFrames[1]
    debug_current_frame_id = frame.id

    if not frame.source or not frame.source.path then
      return
    end

    local path = frame.source.path
    local line = frame.line

    local function show_stopped_frame(exception_summary)
      if body.reason == "exception" and not exception_summary then
        exception_summary = compact_debug_text(body.description or body.text, 140)
      end

      vim.schedule(function()
        local bufnr = vim.fn.bufadd(path)
        pcall(function()
          vim.bo[bufnr].swapfile = false
        end)
        local loaded_ok = pcall(vim.fn.bufload, bufnr)
        if not loaded_ok then
          local edit_ok = pcall(vim.cmd, "silent keepalt noswapfile edit " .. vim.fn.fnameescape(path))
          if not edit_ok then
            vim.notify("DAP: could not load stopped source buffer: " .. path, vim.log.levels.WARN)
            return
          end
          bufnr = vim.api.nvim_get_current_buf()
        end
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end

        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if line_count < 1 then
          return
        end

        local safe_line = tonumber(line) or 1
        safe_line = math.max(1, math.min(safe_line, line_count))
        local mark_row = safe_line - 1

        local target_win = nil
        local current_win = vim.api.nvim_get_current_win()
        local current_is_source = is_debug_source_window(current_win)

        if current_is_source then
          target_win = current_win
        else
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
              local wbuf = vim.api.nvim_win_get_buf(win)
              if vim.bo[wbuf].buftype == "" and vim.bo[wbuf].filetype ~= "NvimTree" then
                target_win = win
                break
              end
            end
          end
        end

        if not target_win then
          return
        end

        vim.api.nvim_win_set_buf(target_win, bufnr)
        _G.enable_debug_source_line_numbers(target_win)
        vim.api.nvim_set_current_win(target_win)
        pcall(vim.api.nvim_win_set_cursor, target_win, { safe_line, 0 })
        vim.cmd("normal! zz")

        -- Clear any previous stop markers, then mark the new stopped line.
        clear_dap_stopped_marks()
        dap_last_buf = bufnr

        local reason = body.reason or "stopped"
        local label = reason == "exception" and "  ✗ exception"
          or reason == "breakpoint"         and "  ◆ breakpoint"
          or                                    "  ◆ " .. reason

        if exception_summary then
          label = label .. ": " .. exception_summary
        end

        -- Surface the function we stopped in, both inline and in the hint window,
        -- so it's obvious the debugger is executing your code (and where).
        local func = frame.name
        if func and func ~= "" then
          label = label .. "  in " .. func .. "()"
        end

        set_debug_location({
          func = (func and func ~= "") and func or "?",
          file = vim.fn.fnamemodify(path, ":t"),
          line = safe_line,
          reason = reason,
          exception = exception_summary,
        })

        if exception_summary then
          vim.notify(exception_summary, vim.log.levels.ERROR, { title = "DAP exception" })
        end

        -- Persistent end-of-line label (stays until continue/terminate).
        pcall(vim.api.nvim_buf_set_extmark, bufnr, dap_label_ns, mark_row, 0, {
          virt_text     = { { label, "DiagnosticWarn" } },
          virt_text_pos = "eol",
          priority      = 200,
        })

        -- Bright flash that fades after 500 ms, leaving the sign's linehl.
        pcall(vim.api.nvim_buf_set_extmark, bufnr, dap_flash_ns, mark_row, 0, {
          line_hl_group = "DapStoppedFlash",
          priority      = 210,
        })
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_clear_namespace(bufnr, dap_flash_ns, 0, -1)
          end
        end, 500)
      end)
    end

    if body.reason == "exception" then
      request_exception_info(session, body.threadId, show_stopped_frame)
    else
      show_stopped_frame(nil)
    end
  end)
end

-- Remove the label only when execution resumes. On crash or exit, keep the
-- last stop marker visible for post-mortem inspection until F11 closes the UI.
local function on_dap_continue()
  vim.schedule(function()
    clear_dap_stopped_marks()
    debug_current_frame_id = nil
    _G.debug_current_thread_id = nil
    set_debug_location({ running = true })
  end)
end

dap.listeners.before.event_continued.clear_stopped = on_dap_continue

dap.listeners.before.event_continued.human_debug_status = function()
  docker_debug_status.dap_state = "running"
end

dap.listeners.after.event_stopped.human_debug_status = function(_, body)
  local reason = body and body.reason or "stopped"
  docker_debug_status.dap_state = "stopped: " .. reason
end

dap.listeners.after.event_initialized.human_debug_status = function()
  docker_debug_status.dap_state = "attached"
end

dap.listeners.before.event_exited.human_debug_status = function(_, body)
  local code = body and body.exitCode
  docker_debug_status.dap_state = code and ("exited: " .. tostring(code)) or "exited"
end

dap.listeners.before.event_terminated.human_debug_status = function()
  docker_debug_status.dap_state = "terminated"
end

local function show_debugger_ui()
  dapui_open_keep_layout()
  vim.schedule(open_debug_hint)
end

local function close_debugger_ui()
  dapui_close_restore_layout()
  close_debug_hint()
  clear_dap_stopped_marks()
  debug_current_frame_id = nil
  _G.debug_current_thread_id = nil
  pending_debug_source = nil
end

function _G.step_current_debug_thread(step_name)
  local session = dap.session()
  if session and _G.debug_current_thread_id and not session.stopped_thread_id then
    session.stopped_thread_id = _G.debug_current_thread_id
  end

  if step_name == "into" then
    dap.step_into({ askForTargets = false })
  elseif step_name == "over" then
    dap.step_over()
  elseif step_name == "out" then
    dap.step_out()
  end
end

function _G.install_human_triton_execute_thread_debug(session, frame_id)
  if not session or not frame_id or session._human_triton_execute_thread_debug_installed then
    return
  end

  session._human_triton_execute_thread_debug_installed = true
  local expression = [[exec('''
import debugpy
if "self" in globals() or "self" in locals():
    if not getattr(self, "_dap_execute_thread_debug", False):
        _dap_orig_execute = self.execute
        def _dap_debug_execute(requests):
            debugpy.debug_this_thread()
            return _dap_orig_execute(requests)
        self.execute = _dap_debug_execute
        self._dap_execute_thread_debug = True
elif not getattr(TritonPythonModel, "_dap_execute_thread_debug", False):
    _dap_orig_execute = TritonPythonModel.execute
    def _dap_debug_execute(self, requests):
        debugpy.debug_this_thread()
        return _dap_orig_execute(self, requests)
    TritonPythonModel.execute = _dap_debug_execute
    TritonPythonModel._dap_execute_thread_debug = True
''')]]

  session:request("evaluate", {
    expression = expression,
    frameId = frame_id,
    context = "repl",
  }, function(err)
    vim.schedule(function()
      if err then
        session._human_triton_execute_thread_debug_installed = false
        vim.notify("DAP: failed to trace Triton execute thread: " .. tostring(err.message or err), vim.log.levels.ERROR)
      else
        docker_debug_status.dap_state = "Triton execute thread tracing installed"
        vim.notify("DAP: Triton execute thread tracing installed", vim.log.levels.INFO)
      end
    end)
  end)
end

dap.listeners.after.event_stopped.human_triton_trace_execute_thread = function(session, body)
  if not (session and session.config and session.config.name == "Attach: human Triton model.py") then
    return
  end
  if session._human_triton_execute_thread_debug_installed or not (body and body.threadId) then
    return
  end

  session:request("stackTrace", { threadId = body.threadId, startFrame = 0, levels = 8 }, function(err, response)
    if err or not response or not response.stackFrames then
      return
    end

    for _, frame in ipairs(response.stackFrames) do
      local path = frame.source and frame.source.path or ""
      if path:match("human_detection_segmentation/1/model%.py$") and frame.name == "initialize" then
        _G.install_human_triton_execute_thread_debug(session, frame.id)
        return
      end
    end

    for _, frame in ipairs(response.stackFrames) do
      local path = frame.source and frame.source.path or ""
      if path:match("human_detection_segmentation/1/model%.py$") then
        _G.install_human_triton_execute_thread_debug(session, frame.id)
        return
      end
    end
  end)
end

function _G.ensure_human_triton_model_breakpoint(cfg, line)
  cfg = cfg or { _dir = vim.fn.getcwd(), debug = { local_root = vim.fn.getcwd(), remote_root = "/workspace" } }
  line = tonumber(line) or 203

  local d = cfg.debug or {}
  local base = cfg._dir or vim.fn.getcwd()
  local function resolve_path(path)
    if not path or path == "" then
      return nil
    end
    if path:find("^/") then
      return path
    end
    return base .. "/" .. path
  end
  local cwd = resolve_path(d.cwd) or base
  local local_root = resolve_path(d.local_root) or cwd
  local path = local_root .. "/runtime/branches/human/model_repository/human_detection_segmentation/1/model.py"

  if vim.fn.filereadable(path) ~= 1 then
    vim.notify("DAP: cannot set Triton breakpoint; file not found: " .. path, vim.log.levels.ERROR)
    return nil
  end

  local bufnr = vim.fn.bufadd(path)
  pcall(function()
    vim.bo[bufnr].swapfile = false
  end)
  local loaded_ok = pcall(vim.fn.bufload, bufnr)
  if not loaded_ok then
    vim.cmd("silent keepalt noswapfile edit " .. vim.fn.fnameescape(path))
    bufnr = vim.api.nvim_get_current_buf()
  end

  local breakpoints = require("dap.breakpoints")
  local existing = breakpoints.get(bufnr)[bufnr] or {}
  for _, bp in ipairs(existing) do
    if bp.line == line then
      return bufnr
    end
  end

  breakpoints.set({}, bufnr, line)
  vim.notify("DAP: set Triton model.py breakpoint at line " .. tostring(line), vim.log.levels.INFO)
  return bufnr
end

local function open_dap_float(element)
  local width = math.min(math.max(50, math.floor(vim.o.columns * 0.82)), math.max(20, vim.o.columns - 4))
  local height = math.min(math.max(16, math.floor(vim.o.lines * 0.75)), math.max(10, vim.o.lines - 6))

  dapui.float_element(element, {
    enter = true,
    width = width,
    height = height,
    position = "center",
  })
  vim.schedule(configure_dapui_windows)
end

local function open_debug_output(title, text)
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "text"

  local width = math.min(math.max(70, math.floor(vim.o.columns * 0.72)), math.max(20, vim.o.columns - 4))
  local height = math.min(math.max(12, math.floor(vim.o.lines * 0.62)), math.max(5, vim.o.lines - 6), #lines)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "left",
  })
  vim.wo[win].wrap = false

  vim.keymap.set("n", { "q", "<C-q>" }, function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, desc = "Close debug output" })
end

inspect_debug_expression = function(expr)
  expr = vim.trim(expr or "")
  if expr == "" then
    return
  end

  local session = dap.session()
  if not session then
    vim.notify("DAP: no active debug session", vim.log.levels.WARN)
    return
  end

  if not debug_current_frame_id then
    vim.notify("DAP: pause execution before inspecting variables", vim.log.levels.WARN)
    return
  end

  session:request("evaluate", {
    expression = torch_summary_expression(expr),
    frameId = debug_current_frame_id,
    context = "repl",
  }, function(err, response)
    vim.schedule(function()
      if err then
        vim.notify("DAP inspect failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
        return
      end

      open_debug_output("DAP inspect: " .. expr, response and response.result or "")
    end)
  end)
end

vim.api.nvim_create_user_command("DapInspectVariable", function(opts)
  if opts.args and opts.args ~= "" then
    inspect_debug_expression(opts.args)
    return
  end

  vim.ui.input({ prompt = "DAP inspect expression: " }, inspect_debug_expression)
end, {
  nargs = "*",
  desc = "Inspect a paused Python variable with compact torch tensor summaries",
})

function _G.inspect_debug_dataframe(expr)
  expr = vim.trim(expr or "")
  if expr == "" then
    return
  end

  local session = dap.session()
  if not session then
    vim.notify("DAP: no active debug session", vim.log.levels.WARN)
    return
  end

  if not debug_current_frame_id then
    vim.notify("DAP: pause execution before summarizing a DataFrame", vim.log.levels.WARN)
    return
  end

  session:request("evaluate", {
    expression = _G.dataframe_summary_expression(expr),
    frameId = debug_current_frame_id,
    context = "repl",
  }, function(err, response)
    vim.schedule(function()
      if err then
        vim.notify("DAP DataFrame summary failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
        return
      end

      open_debug_output("DAP DataFrame: " .. expr, _G.decode_debugpy_string_result(response and response.result or ""))
    end)
  end)
end

vim.api.nvim_create_user_command("DapInspectDataFrame", function(opts)
  if opts.args and opts.args ~= "" then
    _G.inspect_debug_dataframe(opts.args)
    return
  end

  local default_expr = vim.fn.expand("<cword>")
  vim.ui.input({ prompt = "DAP DataFrame expression: ", default = default_expr }, _G.inspect_debug_dataframe)
end, {
  nargs = "*",
  desc = "Summarize a paused pandas DataFrame or Series without printing values",
})

vim.api.nvim_create_user_command("DapToggleVariableValues", function()
  vim.g.dapui_show_variable_values = not vim.g.dapui_show_variable_values
  pcall(dapui.update_render, {})
  vim.notify("DAP variable inline values: " .. (vim.g.dapui_show_variable_values and "shown" or "hidden"), vim.log.levels.INFO)
end, {
  desc = "Toggle inline DAP variable values in scopes and watches",
})

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
require("exocortex.keymaps").set("n", require("exocortex.config_loader").keys("debug").toggle_exception_breakpoints, function()
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

function _G.parse_exocortex_debug_env(text)
  local env = {}

  for _, item in ipairs(parse_shell_words(text or "")) do
    local key, value = item:match("^([%w_]+)=(.*)$")
    if key then
      env[key] = value
    end
  end

  return env
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
    options = {
      initialize_timeout_sec = 120,
    },
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
  {
    type = "python",
    request = "attach",
    name = "Attach: human-deepstream container",
    connect = { host = "127.0.0.1", port = 5678 },
    pathMappings = {
      { localRoot = vim.fn.getcwd(), remoteRoot = "/workspace" },
    },
    justMyCode = false,
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
  set_debug_source(config.program, "Training run")

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

require("exocortex.keymaps").set("n", require("exocortex.config_loader").keys("debug").run_training, function()
  run_training_debug()
end, {
  silent = true,
  desc = "Debug default training run",
})

-- Open a debug mask/logit image saved by debug_utils.save_logit_mask.
-- Usage: :DbgViewMask           -> opens /tmp/dbg/mask.png
--        :DbgViewMask /tmp/dbg/mask_grid.png
-- Or from DAP REPL: from src.debug_utils import save_logit_mask; save_logit_mask(outputs['pred_masks'], index=(0,0))
local function open_dbg_image(path)
  path = (path and path ~= "") and path or "/tmp/dbg/mask.png"
  if vim.fn.filereadable(path) == 0 then
    vim.notify("DbgViewMask: file not found: " .. path, vim.log.levels.WARN)
    return
  end
  vim.fn.jobstart({ "eog", path }, { detach = true })
end

vim.api.nvim_create_user_command("DbgViewMask", function(opts)
  open_dbg_image(opts.args)
end, {
  nargs = "?",
  complete = "file",
  desc = "Open a debug mask/logit image saved by debug_utils.save_logit_mask",
})

require("exocortex.keymaps").set("n", require("exocortex.config_loader").keys("debug").view_mask, function()
  open_dbg_image()
end, {
  silent = true,
  desc = "View debug mask image (/tmp/dbg/mask.png)",
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
      local k, v = line:match("^([%w_]+)%s*=%s*(.+)$")
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
  local env = d.env and _G.parse_exocortex_debug_env(d.env) or nil
  local name = d.name or "Training run"

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
  set_debug_source(program, name)

  dap.run({
    type = "python",
    request = "launch",
    name = name,
    cwd = cwd,
    program = program,
    args = args,
    env = env,
    pythonPath = python,
    justMyCode = false,
    subProcess = false,
    console = "integratedTerminal",
  })
end

local docker_debug_jobs = {}
local attach_human_triton_model = nil
local stop_human_triton_auto_attach_watcher = function() end
docker_debug_status = {
  buf = nil,
  win = nil,
  timer = nil,
  triton_timer = nil,
  log_file = nil,
  dap_state = "not attached",
  cfg = nil,
  triton_auto_attach_started = false,
  attach_generation = 0,
  cleanup_started = false,
  last_error = nil,
}

local function is_human_debug_session(session)
  local name = session and session.config and session.config.name
  return name == "Attach: human-deepstream container"
    or name == "Attach: human Triton model.py"
    or name == "Human offline detector"
end

function _G.cleanup_local_human_debug_processes()
  local patterns = {
    "core-cv-service-sx/scripts/human/run_human_offline.py",
    "scripts/human/run_human.sh --input output/human_detection",
  }

  for _, pattern in ipairs(patterns) do
    vim.system({ "pkill", "-TERM", "-f", pattern }, { text = true })
  end
end

local function cleanup_human_debug_processes(reason)
  if docker_debug_status.cleanup_started then
    return
  end

  docker_debug_status.cleanup_started = true
  docker_debug_status.attach_generation = (docker_debug_status.attach_generation or 0) + 1
  docker_debug_status.dap_state = "cleaning up: " .. (reason or "debug ended")

  stop_human_triton_auto_attach_watcher()
  _G.cleanup_local_human_debug_processes()

  for job_key, job_id in pairs(docker_debug_jobs) do
    if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
      pcall(vim.fn.jobstop, job_id)
    end
    docker_debug_jobs[job_key] = nil
  end

  vim.system({
    "docker",
    "ps",
    "-q",
    "--filter", "label=com.docker.compose.project=human-detection",
    "--filter", "label=com.docker.compose.service=human-detection-ds9",
    "--filter", "publish=5678",
  }, { text = true }, function(result)
    local ids = {}
    for id in (result.stdout or ""):gmatch("%S+") do
      ids[#ids + 1] = id
    end

    vim.system({
      "docker",
      "ps",
      "-q",
      "--filter", "ancestor=core-cv-human-detection:local",
      "--filter", "publish=5679",
    }, { text = true }, function(result_5679)
      local seen = {}
      for _, id in ipairs(ids) do
        seen[id] = true
      end
      for id in (result_5679.stdout or ""):gmatch("%S+") do
        if not seen[id] then
          ids[#ids + 1] = id
          seen[id] = true
        end
      end

      if #ids == 0 then
        vim.schedule(function()
          docker_debug_status.cleanup_started = false
        end)
        return
      end

      local cmd = { "docker", "stop" }
      vim.list_extend(cmd, ids)
      vim.system(cmd, { text = true }, function()
        vim.schedule(function()
          docker_debug_status.cleanup_started = false
          docker_debug_status.dap_state = "debug process killed"
          vim.notify("DAP: killed human debug container(s)", vim.log.levels.INFO, { title = "Human debug cleanup" })
        end)
      end)
    end)
  end)
end

dap.listeners.before.event_terminated.human_debug_kill_process = function(session)
  if is_human_debug_session(session) then
    cleanup_human_debug_processes("terminated")
  end
end

dap.listeners.before.event_exited.human_debug_kill_process = function(session)
  if is_human_debug_session(session) then
    cleanup_human_debug_processes("exited")
  end
end

dap.listeners.before.disconnect.human_debug_kill_process = function(session)
  if is_human_debug_session(session) then
    cleanup_human_debug_processes("disconnected")
  end
end

function _G.hard_stop_debug_session()
  docker_debug_status.dap_state = "terminating"
  pcall(dap.terminate, {
    all = true,
    hierarchy = true,
    disconnect_args = { terminateDebuggee = true },
  })
  cleanup_human_debug_processes("F10")
end

local function latest_matching_line(lines, pattern, plain)
  for i = #(lines or {}), 1, -1 do
    local line = lines[i]
    if line and line:find(pattern, 1, plain == nil and true or plain) then
      return line
    end
  end
  return nil
end

function _G.extract_human_debug_error_info(lines)
  local text = table.concat(lines or {}, "\n")
  local patterns = {
    "ModuleNotFoundError: No module named '[^']+'",
    "ImportError: [^\n]+",
    "SyntaxError: [^\n]+",
    "NameError: [^\n]+",
    "TypeError: [^\n]+",
    "ValueError: [^\n]+",
    "RuntimeError: [^\n]+",
  }

  for _, pattern in ipairs(patterns) do
    local match = text:match(pattern)
    if match then
      local remote_path, location = text:match("(/workspace/[^%(]+model%.py)%((%d+)%):")
      if location then
        local cfg = docker_debug_status.cfg or {}
        local d = cfg.debug or {}
        local remote_root = d.remote_root or "/workspace"
        local local_root = d.local_root and resolve_config_path(cfg._dir or vim.fn.getcwd(), d.local_root)
          or d.cwd and resolve_config_path(cfg._dir or vim.fn.getcwd(), d.cwd)
          or vim.fn.getcwd()
        local local_path = remote_path
        if remote_path:sub(1, #remote_root) == remote_root then
          local_path = local_root .. remote_path:sub(#remote_root + 1)
        end

        return {
          message = "Triton model.py failed at line " .. location .. ": " .. match,
          path = local_path,
          line = tonumber(location),
        }
      end
      return { message = match }
    end
  end

  if text:find("Failed to create instance", 1, true) then
    return { message = latest_matching_line(lines, "Failed to create instance", true) }
  end

  if text:find("failed to load 'human_detection_segmentation'", 1, true) then
    return { message = latest_matching_line(lines, "failed to load 'human_detection_segmentation'", true) }
  end

  if text:find("NVDSINFER_TRITON_ERROR", 1, true) then
    return { message = "Triton inference failed: NVDSINFER_TRITON_ERROR" }
  end

  if text:find("Unable to set the pipeline", 1, true) then
    return { message = "DeepStream pipeline failed to start" }
  end

  return nil
end

function _G.extract_human_debug_error(lines)
  local info = _G.extract_human_debug_error_info(lines)
  return info and info.message or nil
end

function _G.notify_human_debug_error_once(error_message)
  local info = nil
  if type(error_message) == "table" then
    info = error_message
    error_message = info.message
  end

  if not error_message or error_message == "" or docker_debug_status.last_error == error_message then
    return
  end

  docker_debug_status.last_error = error_message
  if info and info.path then
    focus_debug_source(info.path, info.line)
  end
  vim.notify(error_message, vim.log.levels.ERROR, { title = "Human debug failure" })
end

local function classify_human_debug_log(lines)
  local text = table.concat(lines or {}, "\n")
  local error_message = extract_human_debug_error(lines)

  if error_message then
    return "failed: " .. error_message
  end

  if text:find("Error: unrecognized switch %-u") then
    return "failed: debugpy command line is invalid (-u passed to debugpy)"
  end
  if text:find("port is already allocated", 1, true) then
    return "failed: localhost:5678 is already allocated by another container/process"
  end
  if text:find("Error on attach", 1, true) or text:find("Timed out waiting for debug server", 1, true) then
    return "failed: DAP/debugpy attach handshake timed out"
  end
  if text:find("Unable to set the pipeline", 1, true) or text:find("NVDSINFER_TRITON_ERROR", 1, true) then
    return "pipeline error after debugger attach; see Triton/GStreamer errors below"
  end
  if text:find("[human_triton_debug] execute:", 1, true) then
    return "Triton model.py is executing inference"
  end
  if text:find("[human_triton_debug] debugger attached", 1, true) then
    return "Triton model.py debugger attached"
  end
  if text:find("[human_triton_debug] waiting for debugger attach", 1, true) then
    return "Triton model.py is waiting for :DebugHumanTritonModel"
  end
  if text:find("[human_triton_debug] debugpy listening", 1, true) then
    return "Triton model.py debugpy listening on localhost:5679"
  end
  if text:find("[run_human_deepstream] done", 1, true) then
    return "pipeline finished"
  end
  if text:find("End of stream", 1, true) then
    return "DeepStream reached end of stream"
  end
  if text:find("[human_debug] running at ", 1, true) then
    return "Python is running; latest repo frame is shown below"
  end
  if text:find("Main Loop Running", 1, true) then
    return "DeepStream main loop is running"
  end
  if text:find("[human_debug] entering core_cv_service_sx.branches.human.entrypoint", 1, true) then
    return "entered human entrypoint"
  end
  if text:find("[human_debug] debugpy client attached", 1, true) then
    return "debugger attached; stopped before human entrypoint"
  end
  if text:find("[human_debug] debugpy listening", 1, true) then
    return "debugpy listening; waiting for Neovim attach"
  end
  if text:find("Note: Debugging will proceed", 1, true) or text:find("Debugger warning", 1, true) then
    return "debugpy ready/attached; Python is running"
  end
  if text:find("| human_detection_ensemble     | 1       | READY", 1, true) then
    return "Triton models READY; starting debugpy"
  end
  if text:find("loading: human_detection", 1, true) or text:find("Started HTTPService", 1, true) then
    return "starting Triton/DeepStream services"
  end
  if text:find("Container .* Created") or text:find("Creating", 1, true) then
    return "Docker container is starting"
  end
  if text:find("convert: creating temporary MKV", 1, true) or text:find("converting ", 1, true) then
    return "converting debug image input to temporary MKV"
  end
  if text:find("Building", 1, true) or text:find("build: checking", 1, true) then
    return "Docker image build/cache check is running"
  end
  if text:find("build: skipped", 1, true) then
    return "build skipped; preparing debug input"
  end
  if text:find("debug: enabled", 1, true) then
    return "debug wrapper started"
  end

  return "waiting for debug wrapper output"
end

local function stop_human_debug_status()
  if docker_debug_status.timer then
    docker_debug_status.timer:stop()
    docker_debug_status.timer:close()
    docker_debug_status.timer = nil
  end
end

stop_human_triton_auto_attach_watcher = function()
  if docker_debug_status.triton_timer then
    docker_debug_status.triton_timer:stop()
    docker_debug_status.triton_timer:close()
    docker_debug_status.triton_timer = nil
  end
end

local function maybe_auto_attach_human_triton(lines)
  local cfg = docker_debug_status.cfg
  local d = (cfg and cfg.debug) or {}
  local should_auto_attach_triton = d.auto_attach_triton ~= "0" and d.triton_auto_attach ~= "0"
  if not should_auto_attach_triton
      or docker_debug_status.triton_auto_attach_started
      or not attach_human_triton_model then
    return false
  end

  if not latest_matching_line(lines, "[human_triton_debug] waiting for debugger attach", true)
      and not latest_matching_line(lines, "[human_triton_debug] debugpy listening", true) then
    return false
  end

  docker_debug_status.triton_auto_attach_started = true
  docker_debug_status.dap_state = "auto-attaching Triton model.py"
  stop_human_triton_auto_attach_watcher()
  vim.schedule(function()
    attach_human_triton_model(cfg, {
      previous_session = dap.session(),
      quiet = true,
      wait_for_port = true,
    })
  end)
  return true
end

local function start_human_triton_auto_attach_watcher(log_file)
  stop_human_triton_auto_attach_watcher()
  docker_debug_status.triton_timer = vim.uv.new_timer()
  docker_debug_status.triton_timer:start(0, 500, vim.schedule_wrap(function()
    if docker_debug_status.triton_auto_attach_started then
      stop_human_triton_auto_attach_watcher()
      return
    end

    if vim.fn.filereadable(log_file) ~= 1 then
      return
    end

    local ok, lines = pcall(vim.fn.readfile, log_file, "", 500)
    if ok then
      notify_human_debug_error_once(_G.extract_human_debug_error_info(lines))
      maybe_auto_attach_human_triton(lines)
    end
  end))
end

local function open_human_debug_status(log_file)
  docker_debug_status.log_file = log_file
  docker_debug_status.dap_state = docker_debug_status.dap_state or "starting"

  if not docker_debug_status.buf or not vim.api.nvim_buf_is_valid(docker_debug_status.buf) then
    docker_debug_status.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[docker_debug_status.buf].bufhidden = "wipe"
    vim.bo[docker_debug_status.buf].filetype = "log"
    vim.api.nvim_buf_set_name(docker_debug_status.buf, "human-deepstream-debug-status")
  end

  local buf = docker_debug_status.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "Human DeepStream debug status",
    "DAP: " .. docker_debug_status.dap_state,
    "phase: starting",
    "log: " .. log_file,
    "",
    "Waiting for first log lines...",
  })
  vim.bo[buf].modifiable = false

  if not docker_debug_status.win or not vim.api.nvim_win_is_valid(docker_debug_status.win) then
    vim.cmd("botright vertical 70split")
    docker_debug_status.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(docker_debug_status.win, buf)
    local width = math.min(90, math.max(55, math.floor(vim.o.columns * 0.36)))
    pcall(vim.api.nvim_win_set_width, docker_debug_status.win, width)
    pcall(vim.api.nvim_set_option_value, "wrap", false, { win = docker_debug_status.win })
  end

  stop_human_debug_status()
  docker_debug_status.timer = vim.uv.new_timer()
  docker_debug_status.timer:start(0, 1000, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      stop_human_debug_status()
      return
    end

    local lines = {}
    if vim.fn.filereadable(log_file) == 1 then
      local ok, read_lines = pcall(vim.fn.readfile, log_file, "", 500)
      if ok then
        lines = read_lines
      end
    end

    notify_human_debug_error_once(_G.extract_human_debug_error_info(lines))

    local tail = {}
    local start = math.max(1, #lines - 80)
    for i = start, #lines do
      tail[#tail + 1] = lines[i]
    end

    local latest_triton = latest_matching_line(lines, "[human_triton_debug] execute:", true)
    local latest_repo_frame = latest_matching_line(lines, "[human_debug] nearest repo frame: ", true)
    local latest_frame = latest_repo_frame or latest_matching_line(lines, "[human_debug] running at ", true) or "not reported yet"
    local latest_entry = latest_matching_line(lines, "[human_debug] entering ", true)
    local latest_context = latest_frame
    if latest_frame == "not reported yet" and latest_entry then
      latest_context = latest_entry
    end
    if latest_triton then
      latest_context = latest_triton
    end

    local error_message = extract_human_debug_error(lines)
    maybe_auto_attach_human_triton(lines)

    local display = {
      "Human DeepStream debug status",
      "DAP: " .. (docker_debug_status.dap_state or "unknown"),
      "phase: " .. classify_human_debug_log(lines),
      "latest: " .. latest_context,
      "log: " .. log_file,
    }
    if error_message then
      vim.list_extend(display, {
        "ERROR: " .. error_message,
      })
    end
    vim.list_extend(display, {
      "",
      "Recent log:",
    })
    vim.list_extend(display, tail)

    local wrote = pcall(function()
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)
      vim.bo[buf].modifiable = false
    end)

    if wrote and docker_debug_status.win and vim.api.nvim_win_is_valid(docker_debug_status.win) then
      local win_buf = vim.api.nvim_win_get_buf(docker_debug_status.win)
      if win_buf == buf and vim.api.nvim_buf_is_valid(buf) then
        local line_count = vim.api.nvim_buf_line_count(buf)
        if line_count > 0 then
          pcall(vim.api.nvim_win_set_cursor, docker_debug_status.win, { line_count, 0 })
        end
      end
    end
  end))
end

local function run_docker_debug_attach(cfg)
  local d = cfg.debug or {}
  docker_debug_status.cfg = cfg
  docker_debug_status.triton_auto_attach_started = false
  docker_debug_status.attach_generation = (docker_debug_status.attach_generation or 0) + 1
  local attach_generation = docker_debug_status.attach_generation
  local base = cfg._dir or vim.fn.getcwd()
  local cwd = d.cwd and resolve_config_path(base, d.cwd) or base
  local host = d.host or "127.0.0.1"
  local port = tonumber(d.port or d.attach_port) or 5678
  local local_root = d.local_root and resolve_config_path(base, d.local_root) or cwd
  local remote_root = d.remote_root or "/workspace"
  local name = d.name or "Attach: human-deepstream container"
  local run = d.run or d.script
  local attach_delay_ms = tonumber(d.attach_delay_ms) or 1500
  local attach_timeout_ms = tonumber(d.attach_timeout_ms) or 60000
  local python = d.python and resolve_config_path(base, d.python) or vim.fn.exepath("python3")

  if not python or python == "" or not file_exists(python) then
    vim.notify("Python interpreter not found: " .. tostring(python), vim.log.levels.ERROR)
    return
  end

  if not ensure_debugpy(python) then
    return
  end

  pending_debug_source = nil
  vim.notify("DAP: debugging " .. vim.fn.fnamemodify(local_root, ":~:.") .. " -> " .. remote_root, vim.log.levels.INFO, { title = name })

  local adapter_name = "human_deepstream_debugpy_" .. tostring(port)
  dap.adapters[adapter_name] = {
    type = "server",
    host = host,
    port = port,
    options = {
      initialize_timeout_sec = 120,
    },
  }

  local attach_started = false

  local function attach()
    if attach_generation ~= docker_debug_status.attach_generation or attach_started then
      return
    end
    attach_started = true
    docker_debug_status.dap_state = "attaching to " .. host .. ":" .. tostring(port)
    dap.run({
      type = adapter_name,
      request = "attach",
      name = name,
      stopOnEntry = true,
      redirectOutput = true,
      pathMappings = {
        { localRoot = local_root, remoteRoot = remote_root },
      },
      pythonPath = python,
      justMyCode = false,
    })
  end

  local function log_has_debugpy_ready_marker()
    if not d.log or d.log == "" or vim.fn.filereadable(d.log) ~= 1 then
      return false
    end

    local ok, lines = pcall(vim.fn.readfile, d.log, "", 200)
    if not ok then
      return false
    end

    local text = table.concat(lines, "\n")
    return text:find("debugpy listening", 1, true) ~= nil
  end

  local function port_is_listening(callback)
    vim.system({ "ss", "-ltn", "( sport = :" .. tostring(port) .. " )" }, { text = true }, function(result)
      local output = (result.stdout or "") .. (result.stderr or "")
      callback(result.code == 0 and output:find(":" .. tostring(port), 1, true) ~= nil)
    end)
  end

  local function wait_for_port_then_attach(start_ms)
    if attach_generation ~= docker_debug_status.attach_generation or attach_started then
      return
    end

    local function retry_or_timeout()
      if attach_generation ~= docker_debug_status.attach_generation or attach_started then
        return
      end

      if (vim.uv.now() - start_ms) >= attach_timeout_ms then
        vim.schedule(function()
          if attach_generation ~= docker_debug_status.attach_generation or attach_started then
            return
          end
          docker_debug_status.dap_state = "attach timeout"
          vim.notify(
            "DAP: timed out waiting for " .. host .. ":" .. port .. "; see " .. (d.log or "/tmp/exocortex-docker-debug.log"),
            vim.log.levels.ERROR
          )
        end)
        return
      end

      vim.defer_fn(function()
        wait_for_port_then_attach(start_ms)
      end, 500)
    end

    if d.log and d.log ~= "" then
      if log_has_debugpy_ready_marker() then
        port_is_listening(function(is_listening)
          if attach_generation ~= docker_debug_status.attach_generation or attach_started then
            return
          end
          if is_listening then
            vim.defer_fn(attach, 100)
          else
            retry_or_timeout()
          end
        end)
        return
      end

      retry_or_timeout()
      return
    end

    port_is_listening(function(is_listening)
      if is_listening then
        vim.schedule(attach)
      else
        retry_or_timeout()
      end
    end)
  end

  if run and run ~= "" then
    local log_file = d.log or "/tmp/exocortex-docker-debug.log"
    local cmd = run
    if not cmd:find("^/") then
      cmd = "./" .. cmd:gsub("^%./", "")
    end

    pcall(vim.fn.writefile, {}, log_file)
    docker_debug_status.dap_state = "starting debug script"
    open_human_debug_status(log_file)
    start_human_triton_auto_attach_watcher(log_file)

    local job_key = cwd .. "\n" .. run
    local existing_job = docker_debug_jobs[job_key]
    if existing_job and vim.fn.jobwait({ existing_job }, 0)[1] == -1 then
      vim.notify("DAP: debug script already running; waiting to attach to " .. host .. ":" .. port, vim.log.levels.INFO, { title = name })
      vim.defer_fn(function()
        wait_for_port_then_attach(vim.uv.now())
      end, attach_delay_ms)
      return
    end

    local job_id = vim.fn.jobstart({ "sh", "-c", "exec " .. cmd .. " >> " .. vim.fn.shellescape(log_file) .. " 2>&1" }, {
      cwd = cwd,
      detach = false,
      on_exit = function()
        docker_debug_jobs[job_key] = nil
      end,
    })

    if job_id <= 0 then
      vim.notify("DAP: failed to start debug script: " .. run, vim.log.levels.ERROR)
      return
    end

    docker_debug_jobs[job_key] = job_id
    docker_debug_status.dap_state = "waiting for debugpy on " .. host .. ":" .. tostring(port)
    vim.notify("DAP: started " .. run .. "; log: " .. log_file, vim.log.levels.INFO, { title = name })
    vim.defer_fn(function()
      wait_for_port_then_attach(vim.uv.now())
    end, attach_delay_ms)
    return
  end

  attach()
end

vim.api.nvim_create_user_command("DebugDockerAttach", function()
  dap.run({
    type = "python",
    request = "attach",
    name = "Attach: human-deepstream container",
    connect = { host = "127.0.0.1", port = 5678 },
    pathMappings = {
      { localRoot = vim.fn.getcwd(), remoteRoot = "/workspace" },
    },
    justMyCode = false,
  })
end, {
  desc = "Attach debugpy to the human-deepstream Docker container",
})

attach_human_triton_model = function(cfg, opts)
  opts = opts or {}
  cfg = cfg or read_exocortex_config()
  local d = cfg.debug or {}
  local base = cfg._dir or vim.fn.getcwd()
  local cwd = d.cwd and resolve_config_path(base, d.cwd) or base
  local local_root = d.local_root and resolve_config_path(base, d.local_root) or cwd
  local remote_root = d.remote_root or "/workspace"
  local host = d.triton_host or d.host or "127.0.0.1"
  local port = tonumber(d.triton_port or d.model_port) or 5679
  local adapter_name = "human_triton_model_debugpy_" .. tostring(port)

  dap.adapters[adapter_name] = {
    type = "server",
    host = host,
    port = port,
    options = {
      initialize_timeout_sec = 120,
    },
  }

  dap.listeners.before.event_initialized.human_triton_ensure_model_breakpoint = function(session)
    if session and session.config and session.config.name == "Attach: human Triton model.py" then
      _G.ensure_human_triton_model_breakpoint(cfg, 203)
    end
  end

  dap.listeners.after.event_initialized.human_triton_activate_session = function(session)
    if session and session.config and session.config.name == "Attach: human Triton model.py" then
      dap.listeners.after.event_initialized.human_triton_activate_session = nil
      dap.listeners.before.event_initialized.human_triton_ensure_model_breakpoint = nil
      vim.schedule(function()
        pcall(dap.set_session, session)
        pcall(function()
          session:set_breakpoints(require("dap.breakpoints").get(), function()
            docker_debug_status.dap_state = "attached to Triton model.py; breakpoint 203 synced"
          end)
        end)
        pcall(function()
          session:set_exception_breakpoints({ "raised", "uncaught", "userUnhandled" })
        end)
      end)
    end
  end

  local function run_attach()
    if not opts.quiet then
      vim.notify(
        "DAP: attaching to Triton model.py on " .. host .. ":" .. tostring(port),
        vim.log.levels.INFO,
        { title = "Attach: human Triton model.py" }
      )
    else
      docker_debug_status.dap_state = "auto-attaching Triton model.py on " .. host .. ":" .. tostring(port)
    end

    dap.run({
      type = adapter_name,
      request = "attach",
      name = "Attach: human Triton model.py",
      redirectOutput = true,
      pathMappings = {
        { localRoot = local_root, remoteRoot = remote_root },
      },
      justMyCode = false,
    })
  end

  local function wait_for_triton_port(start_ms)
    local timeout_ms = tonumber(d.triton_attach_timeout_ms) or 30000
    vim.system({ "ss", "-ltn", "( sport = :" .. tostring(port) .. " )" }, { text = true }, function(result)
      local output = (result.stdout or "") .. (result.stderr or "")
      if result.code == 0 and output:find(":" .. tostring(port), 1, true) then
        vim.schedule(run_attach)
        return
      end

      if (vim.uv.now() - start_ms) >= timeout_ms then
        vim.schedule(function()
          local message = "DAP: timed out waiting for Triton model.py debugpy on " .. host .. ":" .. tostring(port)
          if opts.quiet then
            docker_debug_status.dap_state = "Triton auto-attach timeout"
          else
            vim.notify(message, vim.log.levels.ERROR, { title = "Attach: human Triton model.py" })
          end
        end)
        return
      end

      vim.defer_fn(function()
        wait_for_triton_port(start_ms)
      end, 500)
    end)
  end

  if opts.wait_for_port then
    wait_for_triton_port(vim.uv.now())
  else
    run_attach()
  end
end

vim.api.nvim_create_user_command("DebugHumanTritonModel", function()
  attach_human_triton_model(read_exocortex_config())
end, {
  desc = "Attach debugpy to the human Triton Python backend model.py process",
})

local function current_python_project_root(file)
  local start = vim.fn.fnamemodify(file, ":h")
  local marker = vim.fs.find({ "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" }, {
    upward = true,
    path = start,
  })[1]

  if marker then
    return vim.fn.fnamemodify(marker, ":p:h")
  end

  return vim.fn.getcwd()
end

local function run_current_python_file()
  if vim.bo.filetype ~= "python" then
    return false
  end

  local file = vim.fn.expand("%:p")

  if file == "" or vim.fn.filereadable(file) ~= 1 then
    vim.notify("Save the current Python file before debugging", vim.log.levels.ERROR)
    return true
  end

  local python = vim.fn.exepath("python3")

  if python == "" then
    vim.notify("python3 was not found on PATH", vim.log.levels.ERROR)
    return true
  end

  if not ensure_debugpy(python) then
    return true
  end

  set_debug_source(file, "Current file")

  dap.run({
    type = "python",
    request = "launch",
    name = "Current file",
    program = file,
    cwd = current_python_project_root(file),
    pythonPath = python,
    justMyCode = false,
    console = "integratedTerminal",
  })

  return true
end

local function refresh_debug_views()
  pcall(dapui.update_render, {})
  resize_debug_sidebar()
end

local function toggle_breakpoint_refresh()
  dap.toggle_breakpoint()
  vim.schedule(refresh_debug_views)
end

local debug_keys = require("exocortex.config_loader").keys("debug")
local debug_keymaps = require("exocortex.keymaps")

debug_keymaps.set("n", debug_keys.start_continue, function()
  if dap.session() then
    dap.continue()
    return
  end

  local cfg = read_exocortex_config()
  local d = cfg.debug or {}

  if cfg._dir and d.request == "attach" then
    run_docker_debug_attach(cfg)
    return
  end

  if cfg._dir and (d.python or d.cwd or d.program or d.args) then
    run_training_debug_explicit(cfg)
    return
  end

  if d.run_file then
    local run_file = d.run_file

    if cfg._dir and not run_file:find("^/") then
      run_file = cfg._dir .. "/" .. run_file
    end

    run_training_debug(run_file)
    return
  end

  if cfg._dir then
    local default_run_file = cfg._dir .. "/training_run.sh"

    run_training_debug(file_exists(default_run_file) and default_run_file or nil)
    return
  end

  if run_current_python_file() then
    return
  end

  run_training_debug()
end, {
  silent = true,
  desc = "Debug current Python file or configured training run",
})
debug_keymaps.set("n", debug_keys.toggle_breakpoint, toggle_breakpoint_refresh, {
  silent = true,
  desc = "Toggle breakpoint",
})
debug_keymaps.set("n", debug_keys.step_into, function()
  _G.step_current_debug_thread("into")
end, {
  silent = true,
  desc = "Step into",
})
debug_keymaps.set("n", debug_keys.step_over, function()
  _G.step_current_debug_thread("over")
end, {
  silent = true,
  desc = "Step over",
})
debug_keymaps.set("n", debug_keys.step_out, function()
  _G.step_current_debug_thread("out")
end, {
  silent = true,
  desc = "Step out",
})
debug_keymaps.set("n", debug_keys.stop, _G.hard_stop_debug_session, {
  silent = true,
  desc = "Terminate debug session and kill human debug process",
})
debug_keymaps.set("n", debug_keys.close_ui, close_debugger_ui, {
  silent = true,
  desc = "Close debug UI",
})
debug_keymaps.set("n", debug_keys.show_ui, show_debugger_ui, {
  silent = true,
  desc = "Show debug UI",
})
debug_keymaps.set("n", debug_keys.variables, function()
  open_dap_float("scopes")
end, {
  silent = true,
  desc = "Open large debug variables view",
})
debug_keymaps.set("n", debug_keys.watches, function()
  open_dap_float("watches")
end, {
  silent = true,
  desc = "Open large debug watches view",
})
debug_keymaps.set("n", debug_keys.console, function()
  open_dap_float("console")
end, {
  silent = true,
  desc = "Open large debug console",
})
debug_keymaps.set("n", debug_keys.inspect, function()
  vim.ui.input({ prompt = "DAP inspect expression: " }, inspect_debug_expression)
end, {
  silent = true,
  desc = "Inspect debug variable",
})
debug_keymaps.set("n", debug_keys.dataframe, function()
  local default_expr = vim.fn.expand("<cword>")
  vim.ui.input({ prompt = "DAP DataFrame expression: ", default = default_expr }, _G.inspect_debug_dataframe)
end, {
  silent = true,
  desc = "Summarize pandas DataFrame or Series",
})
debug_keymaps.set("n", debug_keys.current_function, show_debug_current_function, {
  silent = true,
  desc = "Show current debug function",
})
debug_keymaps.set("n", debug_keys.toggle_values, "<cmd>DapToggleVariableValues<CR>", {
  silent = true,
  desc = "Toggle inline debug variable values",
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

local function paste_register_into_codex_terminal()
  local buf = vim.api.nvim_get_current_buf()
  local job_id = vim.b[buf].terminal_job_id

  if not job_id then
    return
  end

  local text = _G.terminal_paste_text or ""
  if text == "" then
    return
  end

  vim.api.nvim_chan_send(job_id, text)
  vim.cmd("startinsert")
end

vim.api.nvim_create_autocmd({ "FileType", "TermOpen" }, {
  group = augroup,
  pattern = "codex",
  callback = function(args)
    vim.keymap.set("n", { "p" }, paste_register_into_codex_terminal, {
      buffer = args.buf,
      silent = true,
      nowait = true,
      desc = "Paste register into Codex terminal",
    })
  end,
})

-- ============================================================================
-- GIT DIFF REVIEW
-- ============================================================================

pcall(function()
  require("diffview").setup({
    keymaps = {
      view = {
        { "n", "<C-q>", require("diffview.config").actions.close, { desc = "Close Diffview" } },
      },
      file_panel = {
        { "n", "<C-q>", require("diffview.config").actions.close, { desc = "Close Diffview" } },
      },
      file_history_panel = {
        { "n", "<C-q>", require("diffview.config").actions.close, { desc = "Close Diffview" } },
      },
      option_panel = {
        { "n", "<C-q>", require("diffview.config").actions.close, { desc = "Close Diffview" } },
      },
    },
  })
end)

function _G.exocortex_close_diffview_or_tab()
  local ok, lib = pcall(require, "diffview.lib")
  if ok and lib.get_current_view and lib.get_current_view() then
    pcall(vim.cmd, "DiffviewClose")
    return
  end

  close_current_tab()
end

vim.keymap.set({ "n", "t" }, "<C-q>", _G.exocortex_close_diffview_or_tab, {
  silent = true,
  desc = "Close Diffview or editor tab",
})

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

function _G.exocortex_diffview_quit_maps()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
    if ok and vim.api.nvim_buf_is_valid(buf) then
      for _, lhs in ipairs({ "<C-q>", "q" }) do
        vim.keymap.set("n", lhs, "<cmd>DiffviewClose<CR>", {
          buffer = buf,
          silent = true,
          nowait = true,
          desc = "Close Diffview",
        })
      end
    end
  end
end

vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("user-diffview-close-maps", { clear = true }),
  pattern = { "DiffviewViewOpened", "DiffviewViewEnter", "DiffviewDiffBufRead", "DiffviewDiffBufWinEnter", "DiffviewViewPostLayout" },
  callback = function()
    vim.schedule(_G.exocortex_diffview_quit_maps)
  end,
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

local exocortex_config_loader = require("exocortex.config_loader")
local exocortex_keymaps = require("exocortex.keymaps")
local exocortex_keys = exocortex_config_loader.keys("editor")

require("exocortex").setup({})

-- Tabline shows running / recently-completed AI nodes. Dismissed when the node
-- is expanded via <CR> in the graph. Keyed by "session:node_id" to avoid
-- collisions across sessions that both start from n1.
function _G.ExocortexTabLine()
  local ok_state, state = pcall(require, "exocortex.state")
  local ok_graph, graph = pcall(require, "exocortex.graph")
  if not (ok_state and ok_graph) then return "%#TabLineFill#" end

  local parts = {}

  for _, id in ipairs(state.order or {}) do
    local node = state.nodes[id]
    if not node or node.kind == "src" then goto bar_skip end

    local key = (node.session_id or "default") .. ":" .. id
    if not graph.bar_nodes[key] then goto bar_skip end
    if graph.bar_dismissed[key] then goto bar_skip end

    local hl, status_str
    if node.status == "running" then
      hl, status_str = "%#ExocortexStatusRunning#", "running"
    elseif node.status == "done" then
      hl, status_str = "%#ExocortexStatusDone#", "complete"
    elseif node.status == "error" then
      hl, status_str = "%#ExocortexStatusError#", "error"
    else
      goto bar_skip
    end

    local raw_sid = node.session_id or "default"
    local info = state.sessions and state.sessions[raw_sid] or {}
    local sid = info.name or ("Session " .. (info.seq or raw_sid:sub(-4)))
    table.insert(parts, hl .. "  " .. sid .. "  " .. id .. "  " .. status_str .. "  %#TabLineFill#")

    ::bar_skip::
  end

  return table.concat(parts, "") .. "%#TabLineFill#"
end

-- Ctrl-A then i. With Ctrl held through both keys the terminal encodes
-- Ctrl-I as Tab, so map that variant too.
exocortex_keymaps.set({ "n", "t" }, exocortex_keys.open_graph, function()
  vim.schedule(function()
    if vim.api.nvim_get_mode().mode == "t" then
      vim.cmd("stopinsert")
    end
    require("exocortex").open()
  end)
end, {
  silent = true,
  desc = "Open agent DAG",
})

exocortex_keymaps.set({ "n", "t" }, exocortex_keys.open_copilot, function()
  vim.schedule(function()
    if vim.api.nvim_get_mode().mode == "t" then
      vim.cmd("stopinsert")
    end
    require("exocortex").open_copilot()
  end)
end, {
  silent = true,
  desc = "Open Copilot settings",
})

-- Ctrl+Shift+A then i: open the graph and start a fresh session. Depending
-- on when Ctrl/Shift are released, the second key arrives as several variants.
exocortex_keymaps.set("n", exocortex_keys.new_session, function()
  require("exocortex").open()
  require("exocortex.graph").create_new_session()
end, {
  silent = true,
  desc = "New exocortex session",
})

-- ============================================================================
-- RELOAD CONFIG
-- ============================================================================

local function reload_exocortex_plugin()
  local graph_open = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    local ft = vim.bo[buf].filetype
    if name == "exocortex://graph" or ft == "exocortex" or ft == "exocortex-sessions" then
      graph_open = true
      break
    end
  end

  for key in pairs(package.loaded) do
    if key == "exocortex" or key:match("^exocortex%.") then
      package.loaded[key] = nil
    end
  end

  local ok, exocortex = pcall(require, "exocortex")
  if not ok then
    vim.notify("Exocortex reload failed: " .. tostring(exocortex), vim.log.levels.ERROR)
    return
  end

  exocortex.setup({})

  if graph_open then
    exocortex.open()
  end

  vim.notify("Exocortex plugin reloaded", vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("ExocortexReload", reload_exocortex_plugin, {
  desc = "Reload Exocortex plugin modules",
})

exocortex_keymaps.set("n", exocortex_keys.reload_plugin, reload_exocortex_plugin, {
  silent = true,
  desc = "Reload Exocortex plugin",
})

-- ============================================================================
-- QUIT
-- ============================================================================

vim.keymap.set("n", "<leader>q", ":qa<CR>")
vim.keymap.set("n", "<leader>Q", ":qa!<CR>")
