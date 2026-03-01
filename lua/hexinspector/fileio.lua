---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local cfg = require("hexinspector.config")
local state = require("hexinspector.state")

local M = {}

function M.get_file_size(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local size = f:seek("end")
  f:close()
  return size
end

function M.read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

function M.read_chunk(path, offset, length)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  f:seek("set", offset)
  local data = f:read(length)
  f:close()
  return data
end

function M.get_chunk_index(byte_offset)
  return math.floor(byte_offset / cfg.CHUNK_SIZE)
end

function M.ensure_chunk(chunk_idx)
  if state.chunk_cache[chunk_idx] then
    return state.chunk_cache[chunk_idx]
  end
  local start = chunk_idx * cfg.CHUNK_SIZE
  local length = math.min(cfg.CHUNK_SIZE, state.file_size - start)
  if length <= 0 then
    return nil
  end
  local data = M.read_chunk(state.file_path, start, length)
  if not data then
    return nil
  end
  state.chunk_cache[chunk_idx] = data
  return data
end

function M.get_byte(offset)
  if not state.big_file then
    if not state.raw_data or offset < 0 or offset >= state.file_size then
      return nil
    end
    return string.byte(state.raw_data, offset + 1)
  end
  if offset < 0 or offset >= state.file_size then
    return nil
  end
  local ci = M.get_chunk_index(offset)
  local chunk = M.ensure_chunk(ci)
  if not chunk then
    return nil
  end
  local local_off = offset - (ci * cfg.CHUNK_SIZE) + 1
  if local_off > #chunk then
    return nil
  end
  return string.byte(chunk, local_off)
end

function M.get_bytes(offset, count)
  local result = {}
  for i = 0, count - 1 do
    local b = M.get_byte(offset + i)
    if not b then
      break
    end
    result[i + 1] = b
  end
  return result
end

function M.get_data_slice(offset, count)
  if not state.big_file then
    if not state.raw_data then
      return nil
    end
    local s = offset + 1
    local e = math.min(offset + count, #state.raw_data)
    return state.raw_data:sub(s, e)
  end
  local parts = {}
  local remaining = count
  local pos = offset
  while remaining > 0 and pos < state.file_size do
    local ci = M.get_chunk_index(pos)
    local chunk = M.ensure_chunk(ci)
    if not chunk then
      break
    end
    local chunk_start = ci * cfg.CHUNK_SIZE
    local local_off = pos - chunk_start + 1
    local avail = #chunk - local_off + 1
    local take = math.min(avail, remaining)
    table.insert(parts, chunk:sub(local_off, local_off + take - 1))
    remaining = remaining - take
    pos = pos + take
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts)
end

function M.invalidate_chunk(offset)
  local ci = M.get_chunk_index(offset)
  state.chunk_cache[ci] = nil
  state.chunk_dirty[ci] = true
  local row = math.floor(offset / cfg.BYTES_PER_LINE)
  state.viewport_line_cache[row] = nil
end

function M.write_file(path, data)
  local f = io.open(path, "wb")
  if not f then
    return false
  end
  f:write(data)
  f:close()
  return true
end

function M.write_big_file()
  local tmp = state.file_path .. ".hexinsp.tmp"
  local f = io.open(tmp, "wb")
  if not f then
    return false
  end
  local offset = 0
  while offset < state.file_size do
    local ci = M.get_chunk_index(offset)
    local chunk = M.ensure_chunk(ci)
    if chunk then
      f:write(chunk)
    end
    offset = offset + cfg.CHUNK_SIZE
  end
  f:close()
  os.remove(state.file_path)
  os.rename(tmp, state.file_path)
  return true
end

return M
