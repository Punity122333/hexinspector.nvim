---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local M = {}

M.main_win = nil
M.main_buf = nil
M.info_win = nil
M.info_buf = nil
M.backdrop_win = nil
M.backdrop_buf = nil
M.raw_data = nil
M.file_path = nil
M.file_size = 0
M.ns = vim.api.nvim_create_namespace("HexInspector")
M.cursor_au = nil
M.dirty = false
M.undo_stack = {}
M.redo_stack = {}
M.selection_start = nil
M.selection_end = nil
M.selecting = false
M.yank_register = nil
M.last_search = nil
M.big_file = false
M.file_handle = nil
M.chunk_cache = {}
M.chunk_dirty = {}
M.current_template = 1

M.viewport_line_cache = {}
M.viewport_cache_valid = false

function M.invalidate_viewport_cache()
  M.viewport_line_cache = {}
  M.viewport_cache_valid = false
end

function M.reset()
  M.main_win = nil
  M.main_buf = nil
  M.info_win = nil
  M.info_buf = nil
  M.backdrop_win = nil
  M.backdrop_buf = nil
  M.raw_data = nil
  M.file_path = nil
  M.file_size = 0
  M.cursor_au = nil
  M.dirty = false
  M.undo_stack = {}
  M.redo_stack = {}
  M.selecting = false
  M.selection_start = nil
  M.selection_end = nil
  M.big_file = false
  M.chunk_cache = {}
  M.chunk_dirty = {}
  M.invalidate_viewport_cache()
end

return M
