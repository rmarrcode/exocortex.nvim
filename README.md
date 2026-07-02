# exocortex.nvim

This Neovim config centers on four working views: the code editor view, the AI graph view, the diff review view, and the debug view. Exocortex keybindings are configured in `lua/exocortex/config.lua`. Defaults live in `lua/exocortex/config_loader.lua`, and `lua/exocortex/config.example.lua` shows a portable template.

Plugin dependencies are managed by `lazy.nvim` in `init.lua`. The current plugin list is loaded eagerly to preserve startup behavior.

## Code Editor View

The code editor view is the normal workspace: file tree on the side, terminal on the bottom, and source text in the main window.

To open the AI graph, use operation `keys.editor.open_graph`. It is currently set to `<C-a>i` and `<C-a><Tab>`.

To open the Copilot settings screen, use operation `keys.editor.open_copilot`. It is currently set to `<C-a>p`.

To open the AI graph and create a fresh session, use operation `keys.editor.new_session`. It is currently set to `<C-S-a>i`, `<C-S-a>I`, `<C-S-a><C-S-i>`, `<C-S-a><C-i>`, and `<C-S-a><Tab>`.

To reload Exocortex modules without reloading the whole Neovim config, use operation `keys.editor.reload_plugin`. It is currently set to `<F2>` and runs `:ExocortexReload`.

To move the active window to the left side, use operation `keys.editor.move_window_left`. It is currently set to `<C-D-Left>`.

To open the same file in a right split, use operation `keys.editor.open_same_file_right`. It is currently set to `<C-\>`.

To move the enclosing function to the top of the current window, use operation `keys.editor.function_to_top`. It is currently set to `f` in normal editor buffers.

To open the AI graph from terminal mode, use operation `keys.editor.terminal_open_graph`. It is currently set to `<C-a>i` and `<C-a><Tab>`.

To open the Copilot settings screen from terminal mode, use operation `keys.editor.terminal_open_copilot`. It is currently set to `<C-a>p`.

## AI Graph View

The AI graph view shows Exocortex sessions in the left sidebar and proposal nodes in the main graph. Nodes are git-backed proposal snapshots. Real files change only through diff review accepts or direct edits in the right review pane.

By default, gitignored files are selectively mirrored into each temporary proposal worktree for read-only context. Small text-like files such as `mlruns/meta.yaml` are copied directly, while large or binary ignored directories get visible `EXOCORTEX_IGNORED_INDEX.txt` summaries instead of full copies; set `exocortex.copy_ignored_files = false` to skip that overlay.

The `obsidian` session is always present. It is read-only, cannot be deleted, and is built from notes in `OBSIDIAN_DIR`. Its graph uses narrower card spacing so more nodes fit on screen.

To move to a parent node, use operation `keys.graph.parent`. It is currently set to `h`.

To move to a child node, use operation `keys.graph.child`. It is currently set to `l`. The alternate operation `keys.graph.child_alt` is currently set to `<Tab>`.

To move vertically between lanes, use operations `keys.graph.below` and `keys.graph.above`. They are currently set to `j` and `k`.

To select the node under the mouse, use operation `keys.graph.select_mouse`. It is currently set to `<LeftRelease>`.

To open a node detail float, use operation `keys.graph.view`. It is currently set to `<CR>`.

To open a node response as a readable file buffer, use operation `keys.graph.read`. It is currently set to `r`.

To review a node proposal against the working tree, use operation `keys.graph.review_diffs`. It is currently set to `d`.

To open a node snapshot in Diffview, use operation `keys.graph.diffview`. It is currently set to `D`.

To prompt from the selected node, use operation `keys.graph.prompt_branch`. It is currently set to `p`.

To prompt from a fresh root, use operation `keys.graph.prompt_root`. It is currently set to `P`.

To choose the session agent, use operation `keys.graph.choose_agent`. It is currently set to `a`.

To move between sessions, use operations `keys.graph.next_session` and `keys.graph.previous_session`. They are currently set to `<PageDown>` and `<PageUp>`.

To create a session, use operation `keys.graph.new_session`. It is currently set to `<C-t>`.

To close a mutable session, use operation `keys.graph.close_session`. It is currently set to `<C-w>`. The `obsidian` session rejects this operation.

To redraw the graph, use operation `keys.graph.redraw`. It is currently set to `R`.

To show graph help, use operation `keys.graph.help`. It is currently set to `g?`.

To return to code, use operation `keys.graph.return_to_code`. It is currently set to `<Esc>`.

To close the graph tab, use operation `keys.graph.close`. It is currently set to `q`.

The session sidebar has its own operations under `keys.sessions`. Switching is currently `<CR>`, next and previous session are `<PageDown>` and `<PageUp>`, new session is `<C-t>`, close session is `<C-w>`, help is `g?`, close is `q`, and return to code is `<Esc>`.

## Diff View

The diff review view opens in its own review tab, separate from your normal editing windows. The left pane is the proposal, the right pane is the review target, and the top bar shows the active controls. Every hunk is labeled as `proposed`, `accepted`, or `skipped/rejected`. Hunk state is retained per file while the review session is active, so accepted or skipped hunks remain visible when you leave a file and return to it.

To accept the focused hunk, use operation `keys.diff.accept`. It is currently set to `<C-a>`.

To skip and reject the focused hunk, use operation `keys.diff.skip`. It is currently set to `<leader>s`.

To undo an accept or skip, use operation `keys.diff.undo`. It is currently set to `<C-u>`.

To focus the editable right side, use operation `keys.diff.edit_right`. It is currently set to `<C-e>`.

To move to the next or previous focused hunk by index, use operations `keys.diff.next` and `keys.diff.previous`. They are currently set to `<C-j>` and `<C-k>`.

To move to the next or previous hunk from the cursor location, use operations `keys.diff.next_from_cursor` and `keys.diff.previous_from_cursor`. They are currently set to `<C-;>` and `<C-p>`.

To move to the next or previous changed file, use operations `keys.diff.next_file` and `keys.diff.previous_file`. They are currently set to `<C-l>` and `<C-h>`.

To page inside the right file, use operations `keys.diff.page_down` and `keys.diff.page_up`. They are currently set to `]` and `[`.

To move the current function to the top of the window, use operation `keys.diff.function_to_top`. It is currently set to `<C-t>`.

To end review, use operation `keys.diff.close`. It is currently set to `<C-q>`.



## Debug View

The debug view uses `nvim-dap` and `dap-ui`. The UI opens around a source window, shows scopes, watches, breakpoints, console, and a compact key hint window.

To start or continue debugging, use operation `keys.debug.start_continue`. It is currently set to `<F5>` and `<leader>dc`.

To toggle breakpoints, use operation `keys.debug.toggle_breakpoint`. It is currently set to `<F6>` and `<leader>db`.

To step into, over, or out, use operations `keys.debug.step_into`, `keys.debug.step_over`, and `keys.debug.step_out`. They are currently set to `<F7>`/`<leader>di`, `<F8>`/`<leader>dn`, and `<F9>`/`<leader>do`.

To stop the debug session, use operation `keys.debug.stop`. It is currently set to `<F10>` and `<leader>dx`.

To close the debug UI while preserving normal layout, use operation `keys.debug.close_ui`. It is currently set to `<F11>`.

To show the debug UI, use operation `keys.debug.show_ui`. It is currently set to `<leader>du`.

To open large variables, watches, or console floats, use operations `keys.debug.variables`, `keys.debug.watches`, and `keys.debug.console`. They are currently set to `<leader>dv`, `<leader>dw`, and `<leader>dC`.

To inspect an expression in the current frame, use operation `keys.debug.inspect`. It is currently set to `<leader>de`.

To toggle inline variable values, use operation `keys.debug.toggle_values`. It is currently set to `<leader>dV`.

To open the debug mask/logit image, use operation `keys.debug.view_mask`. It is currently set to `<leader>dm`.

To toggle breaking on all raised exceptions, use operation `keys.debug.toggle_exception_breakpoints`. It is currently set to `<leader>dE`.

To run the configured training debug target, use operation `keys.debug.run_training`. It is currently set to `<leader>dr`.

While debug mode is active, cursor navigation in debug panes uses `keys.debug.debug_nav_up`, `keys.debug.debug_nav_down`, `keys.debug.debug_nav_left`, and `keys.debug.debug_nav_right`. They are currently set to `<PageUp>`, `<PageDown>`, `[`, and `]`.
