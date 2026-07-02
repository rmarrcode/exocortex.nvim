local M = {}

M.defaults = {
  OBSIDIAN_DIR = "",
  graph = {
    obsidian_session = "obsidian",
  },
  exocortex = {
    agent = nil,
    model = nil,
    copilot_model = nil,
    context_chars = 4000,
    terminal_lines = 50,
    copy_ignored_files = true,
  },
  keys = {
    editor = {
      open_graph = { "<C-a>i", "<C-a><Tab>" },
      new_session = { "<C-S-a>i", "<C-S-a>I", "<C-S-a><C-S-i>", "<C-S-a><C-i>", "<C-S-a><Tab>" },
      reload_plugin = "<F2>",
      move_window_left = "<C-D-Left>",
      open_same_file_right = "<C-\\>",
      function_to_top = "f",
      terminal_open_graph = { "<C-a>i", "<C-a><Tab>" },
    },
    graph = {
      parent = "h",
      child = "l",
      below = "j",
      above = "k",
      child_alt = "<Tab>",
      parent_alt = "<S-Tab>",
      select_mouse = "<LeftRelease>",
      view = "<CR>",
      read = "r",
      review_diffs = "d",
      diffview = "D",
      prompt_branch = "p",
      prompt_root = "P",
      choose_agent = "a",
      next_session = "<PageDown>",
      previous_session = "<PageUp>",
      new_session = "<C-t>",
      close_session = "<C-w>",
      redraw = "R",
      help = "g?",
      return_to_code = "<Esc>",
      close = { "<C-q>", "q" },
    },
    sessions = {
      switch = "<CR>",
      next_session = "<PageDown>",
      previous_session = "<PageUp>",
      new_session = "<C-t>",
      close_session = "<C-w>",
      help = "g?",
      close = { "<C-q>", "q" },
      return_to_code = "<Esc>",
    },
    node_view = {
      close = { "<C-q>", "q", "ZZ", "ZQ" },
      return_to_code = "<Esc>",
      read = "r",
      review_diffs = "d",
      diffview = "D",
    },
    diff = {
      accept = "<C-a>",
      skip = "<leader>s",
      undo = "<C-u>",
      edit_right = "<C-e>",
      next = "<C-j>",
      previous = "<C-k>",
      next_from_cursor = "<C-;>",
      previous_from_cursor = "<C-p>",
      next_file = "<C-l>",
      previous_file = "<C-h>",
      page_down = "]",
      page_up = "[",
      function_to_top = "<C-t>",
      close = { "<C-q>", "<Esc>" },
    },
    debug = {
      start_continue = { "<F5>", "<leader>dc" },
      toggle_exception_breakpoints = "<leader>dE",
      run_training = "<leader>dr",
      toggle_breakpoint = { "<F6>", "<leader>db" },
      step_into = { "<F7>", "<leader>di" },
      step_over = { "<F8>", "<leader>dn" },
      step_out = { "<F9>", "<leader>do" },
      stop = { "<F10>", "<leader>dx" },
      close_ui = { "<C-q>", "<F11>" },
      show_ui = "<leader>du",
      variables = "<leader>dv",
      watches = "<leader>dw",
      console = "<leader>dC",
      inspect = "<leader>de",
      toggle_values = "<leader>dV",
      view_mask = "<leader>dm",
      debug_nav_up = "<PageUp>",
      debug_nav_down = "<PageDown>",
      debug_nav_left = "[",
      debug_nav_right = "]",
    },
  },
}

local function load_user()
  local ok, user = pcall(require, "exocortex.config")
  if ok and type(user) == "table" then
    return user
  end
  return {}
end

function M.load()
  return vim.tbl_deep_extend("force", M.defaults, load_user())
end

function M.keys(section)
  local cfg = M.load()
  return (cfg.keys and cfg.keys[section]) or {}
end

return M
