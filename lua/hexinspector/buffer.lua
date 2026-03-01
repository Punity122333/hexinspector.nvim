---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local cfg = require("hexinspector.config")
local state = require("hexinspector.state")
local fileio = require("hexinspector.fileio")

local M = {}

function M.byte_to_hex(b)
  return string.format("%02X", b)
end

function M.byte_to_ascii(b)
  if b >= 0x20 and b <= 0x7E then
    return string.char(b)
  end
  return "."
end

function M.push_undo()
  if state.big_file then
    return
  end
  table.insert(state.undo_stack, state.raw_data)
  if #state.undo_stack > cfg.MAX_UNDO then
    table.remove(state.undo_stack, 1)
  end
  state.redo_stack = {}
end

function M.set_byte(offset, val)
  if offset < 0 or offset >= state.file_size then
    return
  end
  if state.big_file then
    local ci = fileio.get_chunk_index(offset)
    local chunk = fileio.ensure_chunk(ci)
    if not chunk then
      return
    end
    local local_off = offset - (ci * cfg.CHUNK_SIZE) + 1
    state.chunk_cache[ci] = chunk:sub(1, local_off - 1) .. string.char(val) .. chunk:sub(local_off + 1)
    state.chunk_dirty[ci] = true
    local row = math.floor(offset / cfg.BYTES_PER_LINE)
    state.viewport_line_cache[row] = nil
    state.dirty = true
    return
  end
  if not state.raw_data then
    return
  end
  local d = state.raw_data
  state.raw_data = d:sub(1, offset) .. string.char(val) .. d:sub(offset + 2)
  state.dirty = true
end

function M.set_bytes(offset, bytes)
  if state.big_file then
    for i = 1, #bytes do
      M.set_byte(offset + i - 1, bytes[i])
    end
    return
  end
  if not state.raw_data then
    return
  end
  local d = state.raw_data
  for i = 1, #bytes do
    local pos = offset + i - 1
    if pos >= 0 and pos < state.file_size then
      d = d:sub(1, pos) .. string.char(bytes[i]) .. d:sub(pos + 2)
    end
  end
  state.raw_data = d
  state.dirty = true
end

function M.insert_bytes(offset, bytes)
  if state.big_file then
    vim.notify("Insert not supported for large files", vim.log.levels.WARN)
    return
  end
  if not state.raw_data then
    return
  end
  local new_chars = ""
  for i = 1, #bytes do
    new_chars = new_chars .. string.char(bytes[i])
  end
  state.raw_data = state.raw_data:sub(1, offset) .. new_chars .. state.raw_data:sub(offset + 1)
  state.file_size = #state.raw_data
  state.dirty = true
end

function M.delete_bytes(offset, count)
  if state.big_file then
    vim.notify("Delete not supported for large files", vim.log.levels.WARN)
    return
  end
  if not state.raw_data or offset < 0 or offset >= state.file_size then
    return
  end
  if offset + count > state.file_size then
    count = state.file_size - offset
  end
  state.raw_data = state.raw_data:sub(1, offset) .. state.raw_data:sub(offset + count + 1)
  state.file_size = #state.raw_data
  state.dirty = true
end

return M
