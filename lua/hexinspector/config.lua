---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local M = {}

M.default_colors = {
  bg = "#1a1b26",
  info_bg = "#1a1b26",
  border = "#115e72",
  addr = "#565f89",
  hex = "#c0caf5",
  ascii = "#9ece6a",
  null = "#3b4261",
  cursor_bg = "#28344a",
  cursor_line_bg = "#1e2030",
  float = "#ff9e64",
  int = "#bb9af7",
  uint = "#7dcfff",
  title = "#7aa2f7",
  search = "#f7768e",
  modified = "#f7768e",
  selection_bg = "#2d4f67",
}

M.config = {
  colors = {},
  bytes_per_line = 24,
  max_undo = 200,
  chunk_size = 1024 * 1024,
  max_memory_file = 64 * 1024 * 1024,
}

function M.get_color(key)
  return M.config.colors[key] or M.default_colors[key]
end

M.BYTES_PER_LINE = 24
M.PAD = " "
M.HEX_START_COL = 14
M.ASCII_START_COL = M.HEX_START_COL + (M.BYTES_PER_LINE * 3)
M.MAX_UNDO = 200
M.CHUNK_SIZE = 1024 * 1024
M.MAX_MEMORY_FILE = 64 * 1024 * 1024

function M.apply_config()
  M.BYTES_PER_LINE = M.config.bytes_per_line or 24
  M.HEX_START_COL = 14
  M.ASCII_START_COL = M.HEX_START_COL + (M.BYTES_PER_LINE * 3)
  M.MAX_UNDO = M.config.max_undo or 200
  M.CHUNK_SIZE = M.config.chunk_size or (1024 * 1024)
  M.MAX_MEMORY_FILE = M.config.max_memory_file or (64 * 1024 * 1024)
end

return M
