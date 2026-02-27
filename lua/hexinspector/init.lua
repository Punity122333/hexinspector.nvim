---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local M = {}

local default_colors = {
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

local config = {
  colors = {},
  bytes_per_line = 24,
  max_undo = 200,
  chunk_size = 1024 * 1024,
  max_memory_file = 64 * 1024 * 1024,
}

local function get_color(key)
  return config.colors[key] or default_colors[key]
end

local BYTES_PER_LINE = 24
local PAD = " "
local HEX_START_COL = 12
local ASCII_START_COL = HEX_START_COL + (BYTES_PER_LINE * 3)
local MAX_UNDO = 200
local CHUNK_SIZE = 1024 * 1024
local MAX_MEMORY_FILE = 64 * 1024 * 1024

local function apply_config()
  BYTES_PER_LINE = config.bytes_per_line or 24
  HEX_START_COL = 12
  ASCII_START_COL = HEX_START_COL + (BYTES_PER_LINE * 3)
  MAX_UNDO = config.max_undo or 200
  CHUNK_SIZE = config.chunk_size or (1024 * 1024)
  MAX_MEMORY_FILE = config.max_memory_file or (64 * 1024 * 1024)
end

local vertex_templates = {
  {
    name = "Pos+Color (24B)",
    stride = 24,
    fields = {
      { name = "Pos", type = "float3", offset = 0 },
      { name = "Col", type = "float3", offset = 12 },
    },
  },
  {
    name = "Pos+UV+Normal (32B)",
    stride = 32,
    fields = {
      { name = "Pos", type = "float3", offset = 0 },
      { name = "UV", type = "float2", offset = 12 },
      { name = "Nrm", type = "float3", offset = 20 },
    },
  },
  {
    name = "Pos+Normal+UV (32B)",
    stride = 32,
    fields = {
      { name = "Pos", type = "float3", offset = 0 },
      { name = "Nrm", type = "float3", offset = 12 },
      { name = "UV", type = "float2", offset = 24 },
    },
  },
  {
    name = "Pos+UV (20B)",
    stride = 20,
    fields = {
      { name = "Pos", type = "float3", offset = 0 },
      { name = "UV", type = "float2", offset = 12 },
    },
  },
  {
    name = "RGBA8888 (4B)",
    stride = 4,
    fields = {
      { name = "R", type = "u8", offset = 0 },
      { name = "G", type = "u8", offset = 1 },
      { name = "B", type = "u8", offset = 2 },
      { name = "A", type = "u8", offset = 3 },
    },
  },
  {
    name = "Pos+Color+UV (32B)",
    stride = 32,
    fields = {
      { name = "Pos", type = "float3", offset = 0 },
      { name = "Col", type = "float3", offset = 12 },
      { name = "UV", type = "float2", offset = 24 },
    },
  },
  {
    name = "Pos Only (12B)",
    stride = 12,
    fields = {
      { name = "Pos", type = "float3", offset = 0 },
    },
  },
}

local state = {
  main_win = nil,
  main_buf = nil,
  info_win = nil,
  info_buf = nil,
  backdrop_win = nil,
  backdrop_buf = nil,
  raw_data = nil,
  file_path = nil,
  file_size = 0,
  ns = vim.api.nvim_create_namespace("HexInspector"),
  cursor_au = nil,
  dirty = false,
  undo_stack = {},
  redo_stack = {},
  selection_start = nil,
  selection_end = nil,
  selecting = false,
  yank_register = nil,
  last_search = nil,
  big_file = false,
  file_handle = nil,
  chunk_cache = {},
  chunk_dirty = {},
  current_template = 1,
}

local viewport_line_cache = {}
local viewport_cache_valid = false

local function invalidate_viewport_cache()
  viewport_line_cache = {}
  viewport_cache_valid = false
end

local function unpack_u8(data, pos)
  return string.byte(data, pos)
end

local function unpack_i8(data, pos)
  local b = string.byte(data, pos)
  if b >= 128 then
    return b - 256
  end
  return b
end

local function unpack_u16_le(data, pos)
  local b0, b1 = string.byte(data, pos, pos + 1)
  return b0 + b1 * 256
end

local function unpack_i16_le(data, pos)
  local v = unpack_u16_le(data, pos)
  if v >= 32768 then
    return v - 65536
  end
  return v
end

local function unpack_u32_le(data, pos)
  local b0, b1, b2, b3 = string.byte(data, pos, pos + 3)
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function unpack_i32_le(data, pos)
  local v = unpack_u32_le(data, pos)
  if v >= 2147483648 then
    return v - 4294967296
  end
  return v
end

local function unpack_f32_le(data, pos)
  local b0, b1, b2, b3 = string.byte(data, pos, pos + 3)
  local sign = 1
  if b3 >= 128 then
    sign = -1
    b3 = b3 - 128
  end
  local exponent = b3 * 2 + math.floor(b2 / 128)
  local mantissa = (b2 % 128) * 65536 + b1 * 256 + b0
  if exponent == 0 and mantissa == 0 then
    return 0.0
  end
  if exponent == 255 then
    if mantissa == 0 then
      return sign * math.huge
    else
      return 0 / 0
    end
  end
  if exponent == 0 then
    return sign * math.ldexp(mantissa / 8388608, -126)
  end
  return sign * math.ldexp(1 + mantissa / 8388608, exponent - 127)
end

local function unpack_f64_le(data, pos)
  local b0, b1, b2, b3, b4, b5, b6, b7 = string.byte(data, pos, pos + 7)
  local sign = 1
  if b7 >= 128 then
    sign = -1
    b7 = b7 - 128
  end
  local exponent = b7 * 16 + math.floor(b6 / 16)
  local hi_mant = (b6 % 16) * 281474976710656 + b5 * 1099511627776 + b4 * 4294967296
  local lo_mant = b3 * 16777216 + b2 * 65536 + b1 * 256 + b0
  local mantissa = hi_mant + lo_mant
  if exponent == 0 and mantissa == 0 then
    return 0.0
  end
  if exponent == 2047 then
    if mantissa == 0 then
      return sign * math.huge
    else
      return 0 / 0
    end
  end
  if exponent == 0 then
    return sign * math.ldexp(mantissa / 4503599627370496, -1022)
  end
  return sign * math.ldexp(1 + mantissa / 4503599627370496, exponent - 1023)
end

local function setup_highlights()
  local hl = vim.api.nvim_set_hl
  local bg = get_color("bg")
  local info_bg = get_color("info_bg")
  hl(0, "HexInspAddr", { fg = get_color("addr"), bg = bg, bold = true })
  hl(0, "HexInspByte", { fg = get_color("hex"), bg = bg })
  hl(0, "HexInspNull", { fg = get_color("null"), bg = bg })
  hl(0, "HexInspAscii", { fg = get_color("ascii"), bg = bg })
  hl(0, "HexInspNonPrint", { fg = get_color("null"), bg = bg })
  hl(0, "HexInspCursor", { bg = get_color("cursor_bg"), fg = get_color("hex"), bold = true })
  hl(0, "HexInspFloat", { fg = get_color("float"), bg = info_bg, bold = true })
  hl(0, "HexInspInt", { fg = get_color("int"), bg = info_bg })
  hl(0, "HexInspUint", { fg = get_color("uint"), bg = info_bg })
  hl(0, "HexInspTitle", { fg = get_color("title"), bg = bg, bold = true })
  hl(0, "HexInspBorder", { fg = get_color("border"), bg = bg })
  hl(0, "HexInspNormal", { fg = get_color("hex"), bg = bg })
  hl(0, "HexInspInfoNormal", { fg = get_color("hex"), bg = info_bg })
  hl(0, "HexInspInfoBorder", { fg = get_color("border"), bg = info_bg })
  hl(0, "HexInspSearch", { fg = get_color("search"), bg = bg, bold = true })
  hl(0, "HexInspLabel", { fg = get_color("addr"), bg = info_bg })
  hl(0, "HexInspSep", { fg = get_color("null"), bg = bg })
  hl(0, "HexInspBackdrop", { bg = bg })
  hl(0, "HexInspModified", { fg = get_color("modified"), bg = bg, bold = true })
  hl(0, "HexInspSelection", { bg = get_color("selection_bg"), fg = get_color("hex") })
  hl(0, "HexInspCursorLine", { bg = get_color("cursor_line_bg") })
end

local function get_file_size(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local size = f:seek("end")
  f:close()
  return size
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

local function read_chunk(path, offset, length)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  f:seek("set", offset)
  local data = f:read(length)
  f:close()
  return data
end

local function get_chunk_index(byte_offset)
  return math.floor(byte_offset / CHUNK_SIZE)
end

local function ensure_chunk(chunk_idx)
  if state.chunk_cache[chunk_idx] then
    return state.chunk_cache[chunk_idx]
  end
  local start = chunk_idx * CHUNK_SIZE
  local length = math.min(CHUNK_SIZE, state.file_size - start)
  if length <= 0 then
    return nil
  end
  local data = read_chunk(state.file_path, start, length)
  if not data then
    return nil
  end
  state.chunk_cache[chunk_idx] = data
  return data
end

local function get_byte(offset)
  if not state.big_file then
    if not state.raw_data or offset < 0 or offset >= state.file_size then
      return nil
    end
    return string.byte(state.raw_data, offset + 1)
  end
  if offset < 0 or offset >= state.file_size then
    return nil
  end
  local ci = get_chunk_index(offset)
  local chunk = ensure_chunk(ci)
  if not chunk then
    return nil
  end
  local local_off = offset - (ci * CHUNK_SIZE) + 1
  if local_off > #chunk then
    return nil
  end
  return string.byte(chunk, local_off)
end

local function get_bytes(offset, count)
  local result = {}
  for i = 0, count - 1 do
    local b = get_byte(offset + i)
    if not b then
      break
    end
    result[i + 1] = b
  end
  return result
end

local function get_data_slice(offset, count)
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
    local ci = get_chunk_index(pos)
    local chunk = ensure_chunk(ci)
    if not chunk then
      break
    end
    local chunk_start = ci * CHUNK_SIZE
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

local function invalidate_chunk(offset)
  local ci = get_chunk_index(offset)
  state.chunk_cache[ci] = nil
  state.chunk_dirty[ci] = true
  local row = math.floor(offset / BYTES_PER_LINE)
  viewport_line_cache[row] = nil
end

local function write_file(path, data)
  local f = io.open(path, "wb")
  if not f then
    return false
  end
  f:write(data)
  f:close()
  return true
end

local function write_big_file()
  local tmp = state.file_path .. ".hexinsp.tmp"
  local f = io.open(tmp, "wb")
  if not f then
    return false
  end
  local offset = 0
  while offset < state.file_size do
    local ci = get_chunk_index(offset)
    local chunk = ensure_chunk(ci)
    if chunk then
      f:write(chunk)
    end
    offset = offset + CHUNK_SIZE
  end
  f:close()
  os.remove(state.file_path)
  os.rename(tmp, state.file_path)
  return true
end

local function byte_to_hex(b)
  return string.format("%02X", b)
end

local function byte_to_ascii(b)
  if b >= 0x20 and b <= 0x7E then
    return string.char(b)
  end
  return "."
end

local function push_undo()
  if state.big_file then
    return
  end
  table.insert(state.undo_stack, state.raw_data)
  if #state.undo_stack > MAX_UNDO then
    table.remove(state.undo_stack, 1)
  end
  state.redo_stack = {}
end

local function set_byte(offset, val)
  if offset < 0 or offset >= state.file_size then
    return
  end
  if state.big_file then
    local ci = get_chunk_index(offset)
    local chunk = ensure_chunk(ci)
    if not chunk then
      return
    end
    local local_off = offset - (ci * CHUNK_SIZE) + 1
    state.chunk_cache[ci] = chunk:sub(1, local_off - 1) .. string.char(val) .. chunk:sub(local_off + 1)
    state.chunk_dirty[ci] = true
    local row = math.floor(offset / BYTES_PER_LINE)
    viewport_line_cache[row] = nil
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

local function set_bytes(offset, bytes)
  if state.big_file then
    for i = 1, #bytes do
      set_byte(offset + i - 1, bytes[i])
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

local function insert_bytes(offset, bytes)
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

local function delete_bytes(offset, count)
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

local function format_lines(data)
  local lines = {}
  local total = type(data) == "string" and #data or state.file_size
  local offset = 0

  while offset < total do
    local chunk_size = math.min(BYTES_PER_LINE, total - offset)
    local addr = string.format("%08X", offset)
    local hex_parts = {}
    local ascii_parts = {}

    for i = 1, BYTES_PER_LINE do
      if i <= chunk_size then
        local b
        if type(data) == "string" then
          b = string.byte(data, offset + i)
        else
          b = get_byte(offset + i - 1)
        end
        if b then
          hex_parts[i] = byte_to_hex(b)
          ascii_parts[i] = byte_to_ascii(b)
        else
          hex_parts[i] = "  "
          ascii_parts[i] = " "
        end
      else
        hex_parts[i] = "  "
        ascii_parts[i] = " "
      end
    end

    local hex_str = ""
    for i = 1, BYTES_PER_LINE do
      if i > 1 and (i - 1) % 4 == 0 then
        hex_str = hex_str .. " "
      end
      hex_str = hex_str .. hex_parts[i] .. " "
    end

    local ascii_str = table.concat(ascii_parts)
    local line = PAD .. addr .. " │ " .. hex_str .. "│ " .. ascii_str
    table.insert(lines, line)
    offset = offset + BYTES_PER_LINE
  end

  return lines
end

local function format_lines_for_viewport(start_line, num_lines)
  local lines = {}
  local total = state.file_size
  for li = 0, num_lines - 1 do
    local row = start_line + li
    if viewport_line_cache[row] then
      table.insert(lines, viewport_line_cache[row])
    else
      local offset = row * BYTES_PER_LINE
      if offset >= total then
        break
      end
      local chunk_size = math.min(BYTES_PER_LINE, total - offset)
      local addr = string.format("%08X", offset)
      local hex_parts = {}
      local ascii_parts = {}
      for i = 1, BYTES_PER_LINE do
        if i <= chunk_size then
          local b = get_byte(offset + i - 1)
          if b then
            hex_parts[i] = byte_to_hex(b)
            ascii_parts[i] = byte_to_ascii(b)
          else
            hex_parts[i] = "  "
            ascii_parts[i] = " "
          end
        else
          hex_parts[i] = "  "
          ascii_parts[i] = " "
        end
      end
      local hex_str = ""
      for i = 1, BYTES_PER_LINE do
        if i > 1 and (i - 1) % 4 == 0 then
          hex_str = hex_str .. " "
        end
        hex_str = hex_str .. hex_parts[i] .. " "
      end
      local ascii_str = table.concat(ascii_parts)
      local line = PAD .. addr .. " │ " .. hex_str .. "│ " .. ascii_str
      viewport_line_cache[row] = line
      table.insert(lines, line)
    end
  end
  return lines
end

local function total_lines_for_file()
  return math.ceil(state.file_size / BYTES_PER_LINE)
end

local function update_title()
  if not state.main_win or not vim.api.nvim_win_is_valid(state.main_win) then
    return
  end
  local fname = vim.fn.fnamemodify(state.file_path, ":t")
  local size_str
  if state.file_size >= 1048576 then
    size_str = string.format("%.2f MB", state.file_size / 1048576)
  elseif state.file_size >= 1024 then
    size_str = string.format("%.1f KB", state.file_size / 1024)
  else
    size_str = state.file_size .. " B"
  end
  local dirty_mark = state.dirty and " [+]" or ""
  local tpl = vertex_templates[state.current_template]
  local big_mark = state.big_file and " │ STREAM" or ""
  local title = " HexEditor │ " .. fname .. dirty_mark .. " │ " .. size_str .. " │ " .. tpl.name .. big_mark .. " "
  vim.api.nvim_win_set_config(state.main_win, { title = title, title_pos = "center" })
end

local function apply_line_highlights(buf, lines, data, base_line)
  local ns = state.ns
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local total = state.big_file and state.file_size or #data
  base_line = base_line or 0

  for line_idx, line_str in ipairs(lines) do
    local row = line_idx - 1
    local line_offset = (base_line + row) * BYTES_PER_LINE

    vim.api.nvim_buf_add_highlight(buf, ns, "HexInspAddr", row, 1, 9)
    vim.api.nvim_buf_add_highlight(buf, ns, "HexInspSep", row, 9, 12)

    local col = HEX_START_COL
    for i = 0, BYTES_PER_LINE - 1 do
      if i > 0 and i % 4 == 0 then
        col = col + 1
      end
      local byte_offset = line_offset + i
      if byte_offset < total then
        local b = get_byte(byte_offset)
        if b then
          local hl_group = b == 0 and "HexInspNull" or "HexInspByte"
          vim.api.nvim_buf_add_highlight(buf, ns, hl_group, row, col, col + 2)
        end
      end
      col = col + 3
    end

    local sep2_start = HEX_START_COL + (BYTES_PER_LINE * 3) + math.floor((BYTES_PER_LINE - 1) / 4)
    local sep2_pos = string.find(line_str, "│", sep2_start)
    if sep2_pos then
      vim.api.nvim_buf_add_highlight(buf, ns, "HexInspSep", row, sep2_pos - 1, sep2_pos + 2)
    end

    for i = 0, BYTES_PER_LINE - 1 do
      local byte_offset = line_offset + i
      if byte_offset < total then
        local b = get_byte(byte_offset)
        if b then
          local asc_col = #line_str - (BYTES_PER_LINE - i)
          if asc_col >= 0 and asc_col < #line_str then
            local hl = (b >= 0x20 and b <= 0x7E) and "HexInspAscii" or "HexInspNonPrint"
            vim.api.nvim_buf_add_highlight(buf, ns, hl, row, asc_col, asc_col + 1)
          end
        end
      end
    end
  end
end

local function refresh_display()
  if not state.main_buf or not vim.api.nvim_buf_is_valid(state.main_buf) then
    return
  end
  if state.big_file then
    local cursor = vim.api.nvim_win_get_cursor(state.main_win)
    local win_height = vim.api.nvim_win_get_height(state.main_win)
    local top_line = math.max(0, cursor[1] - 1 - math.floor(win_height / 2))
    local total = total_lines_for_file()
    local num_lines = math.min(total - top_line, total)
    local lines = format_lines_for_viewport(top_line, num_lines)
    vim.bo[state.main_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)
    vim.bo[state.main_buf].modifiable = false
    apply_line_highlights(state.main_buf, lines, nil, top_line)
    update_title()
    return
  end
  local data = state.raw_data
  if not data then
    return
  end
  local lines = format_lines(data)
  vim.bo[state.main_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)
  vim.bo[state.main_buf].modifiable = false
  apply_line_highlights(state.main_buf, lines, data)
  update_title()
end

local function get_byte_offset_from_cursor()
  if not state.main_win or not vim.api.nvim_win_is_valid(state.main_win) then
    return 0
  end
  local cursor = vim.api.nvim_win_get_cursor(state.main_win)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line_offset = row * BYTES_PER_LINE

  if col < HEX_START_COL then
    return line_offset
  end

  local hex_col = col - HEX_START_COL
  local byte_idx = 0
  local group_count = 0

  for i = 0, BYTES_PER_LINE - 1 do
    if i > 0 and i % 4 == 0 then
      group_count = group_count + 1
    end
    local start_c = i * 3 + group_count
    local end_c = start_c + 2
    if hex_col >= start_c and hex_col < end_c then
      byte_idx = i
      break
    end
    if hex_col >= start_c and hex_col < start_c + 3 then
      byte_idx = i
      break
    end
    byte_idx = i
  end

  local offset = line_offset + byte_idx
  if offset >= state.file_size then
    offset = state.file_size - 1
  end
  if offset < 0 then
    offset = 0
  end
  return offset
end

local function update_info_window(offset)
  if not state.info_buf or not vim.api.nvim_buf_is_valid(state.info_buf) then
    return
  end
  if offset < 0 then
    return
  end
  if not state.big_file and not state.raw_data then
    return
  end

  local size = state.file_size
  local slice = get_data_slice(offset, 8)
  if not slice or #slice == 0 then
    return
  end
  local lines = {}
  local hl_map = {}

  table.insert(lines, " Offset: 0x" .. string.format("%08X", offset) .. " (" .. offset .. ")")
  table.insert(hl_map, { "HexInspTitle", #lines })

  table.insert(lines, "")

  local b = unpack_u8(slice, 1)
  table.insert(lines, " Uint8:   " .. b)
  table.insert(hl_map, { "HexInspUint", #lines })
  table.insert(lines, " Hex:     0x" .. string.format("%02X", b))
  table.insert(hl_map, { "HexInspUint", #lines })

  local bin_str = ""
  local bval = b
  for _ = 1, 8 do
    bin_str = ((bval % 2 == 1) and "1" or "0") .. bin_str
    bval = math.floor(bval / 2)
  end
  table.insert(lines, " Bin:     " .. bin_str)
  table.insert(hl_map, { "HexInspUint", #lines })

  table.insert(lines, " Char:    " .. (b >= 0x20 and b <= 0x7E and ("'" .. string.char(b) .. "'") or "N/A"))
  table.insert(hl_map, { "HexInspLabel", #lines })

  local int8 = unpack_i8(slice, 1)
  table.insert(lines, " Int8:    " .. int8)
  table.insert(hl_map, { "HexInspInt", #lines })

  if #slice >= 2 and offset + 2 <= size then
    table.insert(lines, "")
    local u16 = unpack_u16_le(slice, 1)
    table.insert(lines, " Uint16:  " .. u16)
    table.insert(hl_map, { "HexInspUint", #lines })
    local i16 = unpack_i16_le(slice, 1)
    table.insert(lines, " Int16:   " .. i16)
    table.insert(hl_map, { "HexInspInt", #lines })
  end

  if #slice >= 4 and offset + 4 <= size then
    table.insert(lines, "")
    local u32 = unpack_u32_le(slice, 1)
    table.insert(lines, " Uint32:  " .. u32)
    table.insert(hl_map, { "HexInspUint", #lines })
    local i32 = unpack_i32_le(slice, 1)
    table.insert(lines, " Int32:   " .. i32)
    table.insert(hl_map, { "HexInspInt", #lines })
    local f32 = unpack_f32_le(slice, 1)
    table.insert(lines, string.format(" Float32: %.8g", f32))
    table.insert(hl_map, { "HexInspFloat", #lines })
  end

  if #slice >= 8 and offset + 8 <= size then
    local f64 = unpack_f64_le(slice, 1)
    table.insert(lines, string.format(" Float64: %.15g", f64))
    table.insert(hl_map, { "HexInspFloat", #lines })
  end

  table.insert(lines, "")

  local tpl = vertex_templates[state.current_template]
  local vertex_base = offset - (offset % tpl.stride)
  if vertex_base + tpl.stride <= size then
    local vslice = get_data_slice(vertex_base, tpl.stride)
    if vslice and #vslice >= tpl.stride then
      table.insert(lines, " ── " .. tpl.name .. " ──")
      table.insert(hl_map, { "HexInspTitle", #lines })
      for _, field in ipairs(tpl.fields) do
        local fo = field.offset + 1
        if field.type == "float3" and fo + 11 <= #vslice then
          local x = unpack_f32_le(vslice, fo)
          local y = unpack_f32_le(vslice, fo + 4)
          local z = unpack_f32_le(vslice, fo + 8)
          table.insert(lines, string.format(" %s: (%.4f, %.4f, %.4f)", field.name, x, y, z))
          table.insert(hl_map, { "HexInspFloat", #lines })
        elseif field.type == "float2" and fo + 7 <= #vslice then
          local x = unpack_f32_le(vslice, fo)
          local y = unpack_f32_le(vslice, fo + 4)
          table.insert(lines, string.format(" %s: (%.4f, %.4f)", field.name, x, y))
          table.insert(hl_map, { "HexInspFloat", #lines })
        elseif field.type == "float1" and fo + 3 <= #vslice then
          local x = unpack_f32_le(vslice, fo)
          table.insert(lines, string.format(" %s: %.4f", field.name, x))
          table.insert(hl_map, { "HexInspFloat", #lines })
        elseif field.type == "u8" and fo <= #vslice then
          local v = unpack_u8(vslice, fo)
          table.insert(lines, string.format(" %s: %d (0x%02X)", field.name, v, v))
          table.insert(hl_map, { "HexInspUint", #lines })
        elseif field.type == "u16" and fo + 1 <= #vslice then
          local v = unpack_u16_le(vslice, fo)
          table.insert(lines, string.format(" %s: %d", field.name, v))
          table.insert(hl_map, { "HexInspUint", #lines })
        elseif field.type == "u32" and fo + 3 <= #vslice then
          local v = unpack_u32_le(vslice, fo)
          table.insert(lines, string.format(" %s: %d", field.name, v))
          table.insert(hl_map, { "HexInspUint", #lines })
        elseif field.type == "i32" and fo + 3 <= #vslice then
          local v = unpack_i32_le(vslice, fo)
          table.insert(lines, string.format(" %s: %d", field.name, v))
          table.insert(hl_map, { "HexInspInt", #lines })
        end
      end
    end
  end

  table.insert(lines, " [T] cycle template")
  table.insert(hl_map, { "HexInspLabel", #lines })

  if state.selecting and state.selection_start then
    table.insert(lines, "")
    table.insert(lines, " ── Selection ──")
    table.insert(hl_map, { "HexInspTitle", #lines })
    local sel_s = math.min(state.selection_start, offset)
    local sel_e = math.max(state.selection_start, offset)
    table.insert(lines, string.format(" Range: 0x%X - 0x%X", sel_s, sel_e))
    table.insert(hl_map, { "HexInspLabel", #lines })
    table.insert(lines, string.format(" Size:  %d bytes", sel_e - sel_s + 1))
    table.insert(hl_map, { "HexInspLabel", #lines })
  end

  table.insert(lines, "")
  table.insert(lines, " ── Keys ──")
  table.insert(hl_map, { "HexInspTitle", #lines })
  table.insert(lines, " e  Edit byte (hex)")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " E  Edit byte (ASCII)")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " m  Edit multi-byte")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " I  Insert bytes")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " x  Delete byte(s)")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " v  Visual select")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " y  Yank bytes")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " p  Paste bytes")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " F  Fill range")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " R  Replace pattern")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " w  Write to disk")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " u  Undo  U  Redo")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " g  Jump   /  Search")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " n  Next match")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " T  Cycle template")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " t  Pick template")
  table.insert(hl_map, { "HexInspLabel", #lines })
  table.insert(lines, " q  Quit")
  table.insert(hl_map, { "HexInspLabel", #lines })

  for i, line in ipairs(lines) do
    if #line < 35 then
      lines[i] = line .. string.rep(" ", 35 - #line)
    end
  end

  vim.bo[state.info_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.info_buf, 0, -1, false, lines)
  vim.bo[state.info_buf].modifiable = false

  local ns = state.ns
  vim.api.nvim_buf_clear_namespace(state.info_buf, ns, 0, -1)
  for _, entry in ipairs(hl_map) do
    vim.api.nvim_buf_add_highlight(state.info_buf, ns, entry[1], entry[2] - 1, 0, -1)
  end
end

local function highlight_cursor_byte(offset)
  if not state.main_buf or not vim.api.nvim_buf_is_valid(state.main_buf) then
    return
  end

  local cursor_ns = state.ns + 1
  vim.api.nvim_buf_clear_namespace(state.main_buf, cursor_ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(state.main_buf)

  if state.selecting and state.selection_start then
    local sel_s = math.min(state.selection_start, offset)
    local sel_e = math.max(state.selection_start, offset)
    for so = sel_s, sel_e do
      local sr = math.floor(so / BYTES_PER_LINE)
      local sb = so % BYTES_PER_LINE
      local sg = math.floor(sb / 4)
      local sc = HEX_START_COL + sb * 3 + sg
      if sr < line_count then
        vim.api.nvim_buf_add_highlight(state.main_buf, cursor_ns, "HexInspSelection", sr, sc, sc + 2)
        local line = vim.api.nvim_buf_get_lines(state.main_buf, sr, sr + 1, false)[1]
        if line then
          local ac = #line - BYTES_PER_LINE + sb
          if ac >= 0 and ac < #line then
            vim.api.nvim_buf_add_highlight(state.main_buf, cursor_ns, "HexInspSelection", sr, ac, ac + 1)
          end
        end
      end
    end
    state.selection_end = offset
  end

  local row = math.floor(offset / BYTES_PER_LINE)
  local byte_in_row = offset % BYTES_PER_LINE
  local group_offset = math.floor(byte_in_row / 4)
  local hex_col = HEX_START_COL + byte_in_row * 3 + group_offset

  if row < line_count then
    vim.api.nvim_buf_add_highlight(state.main_buf, cursor_ns, "HexInspCursor", row, hex_col, hex_col + 2)
    local line = vim.api.nvim_buf_get_lines(state.main_buf, row, row + 1, false)[1]
    if line then
      local ascii_col = #line - BYTES_PER_LINE + byte_in_row
      if ascii_col >= 0 and ascii_col < #line then
        vim.api.nvim_buf_add_highlight(state.main_buf, cursor_ns, "HexInspCursor", row, ascii_col, ascii_col + 1)
      end
    end
  end

  if offset + 4 <= state.file_size then
    for i = 0, 3 do
      local fo = offset + i
      local fr = math.floor(fo / BYTES_PER_LINE)
      local fb = fo % BYTES_PER_LINE
      local fg = math.floor(fb / 4)
      local fc = HEX_START_COL + fb * 3 + fg
      if fr < line_count and fo ~= offset then
        vim.api.nvim_buf_add_highlight(state.main_buf, cursor_ns, "HexInspSearch", fr, fc, fc + 2)
      end
    end
  end
end

local function jump_to_offset(target)
  if not state.main_buf or not state.main_win then
    return
  end
  if target < 0 then
    target = 0
  end
  if target >= state.file_size then
    target = state.file_size - 1
  end

  local row = math.floor(target / BYTES_PER_LINE) + 1
  local byte_in_row = target % BYTES_PER_LINE
  local group_offset = math.floor(byte_in_row / 4)
  local col = HEX_START_COL + byte_in_row * 3 + group_offset

  vim.api.nvim_win_set_cursor(state.main_win, { row, col })
end

local function search_pattern(pattern, start_after)
  if state.big_file then
    local plen = #pattern
    local function check_at(pos)
      for j = 0, plen - 1 do
        local b = get_byte(pos + j)
        if not b or b ~= pattern[j + 1] then
          return false
        end
      end
      return true
    end
    for i = start_after, state.file_size - plen do
      if check_at(i) then
        return i
      end
    end
    for i = 0, math.min(start_after - 1, state.file_size - plen) do
      if check_at(i) then
        return i
      end
    end
    return nil
  end
  local data = state.raw_data
  if not data then
    return nil
  end
  for i = start_after + 1, #data - #pattern + 1 do
    local match = true
    for j = 1, #pattern do
      if string.byte(data, i + j - 1) ~= pattern[j] then
        match = false
        break
      end
    end
    if match then
      return i - 1
    end
  end
  for i = 1, start_after do
    local match = true
    for j = 1, #pattern do
      if i + j - 1 > #data then
        match = false
        break
      end
      if string.byte(data, i + j - 1) ~= pattern[j] then
        match = false
        break
      end
    end
    if match then
      return i - 1
    end
  end
  return nil
end

local function prompt_jump()
  vim.ui.input({ prompt = "Jump to offset (hex: 0x... or decimal): " }, function(input)
    if not input or input == "" then
      return
    end
    local val
    if input:sub(1, 2) == "0x" or input:sub(1, 2) == "0X" then
      val = tonumber(input, 16)
    else
      val = tonumber(input)
    end
    if val then
      jump_to_offset(val)
    else
      vim.notify("Invalid offset: " .. input, vim.log.levels.ERROR)
    end
  end)
end

local function prompt_search_bytes()
  vim.ui.input({ prompt = "Search hex bytes (e.g. FF 00 1A): " }, function(input)
    if not input or input == "" then
      return
    end
    local pattern = {}
    for hex in input:gmatch("%x%x") do
      table.insert(pattern, tonumber(hex, 16))
    end
    if #pattern == 0 then
      vim.notify("No valid hex bytes in input", vim.log.levels.ERROR)
      return
    end
    state.last_search = pattern
    local current_offset = get_byte_offset_from_cursor() + 1
    local found = search_pattern(pattern, current_offset)
    if found then
      jump_to_offset(found)
      local wrapped = found < current_offset - 1
      vim.notify(string.format("Found at 0x%08X%s", found, wrapped and " (wrapped)" or ""), vim.log.levels.INFO)
    else
      vim.notify("Pattern not found", vim.log.levels.WARN)
    end
  end)
end

local function search_next()
  if not state.last_search then
    vim.notify("No previous search", vim.log.levels.WARN)
    return
  end
  local current_offset = get_byte_offset_from_cursor() + 1
  local found = search_pattern(state.last_search, current_offset)
  if found then
    jump_to_offset(found)
    local wrapped = found < current_offset - 1
    vim.notify(string.format("Found at 0x%08X%s", found, wrapped and " (wrapped)" or ""), vim.log.levels.INFO)
  else
    vim.notify("Pattern not found", vim.log.levels.WARN)
  end
end

local function do_edit_byte()
  local offset = get_byte_offset_from_cursor()
  local current = get_byte(offset)
  if not current then
    return
  end
  vim.ui.input({ prompt = string.format("Byte at 0x%08X [%02X] → ", offset, current) }, function(input)
    if not input or input == "" then
      return
    end
    local val = tonumber(input, 16)
    if not val or val < 0 or val > 255 then
      vim.notify("Invalid hex byte: " .. input, vim.log.levels.ERROR)
      return
    end
    push_undo()
    set_byte(offset, val)
    refresh_display()
    jump_to_offset(offset + 1)
  end)
end

local function do_edit_ascii()
  local offset = get_byte_offset_from_cursor()
  local current = get_byte(offset)
  if not current then
    return
  end
  local cur_char = (current >= 0x20 and current <= 0x7E) and string.char(current) or "."
  vim.ui.input({ prompt = string.format("ASCII at 0x%08X [%s] → ", offset, cur_char) }, function(input)
    if not input or input == "" then
      return
    end
    push_undo()
    for i = 1, #input do
      local c = string.byte(input, i)
      if offset + i - 1 < state.file_size then
        set_byte(offset + i - 1, c)
      end
    end
    refresh_display()
    jump_to_offset(offset + #input)
  end)
end

local function do_edit_multi()
  local offset = get_byte_offset_from_cursor()
  vim.ui.input({ prompt = string.format("Hex at 0x%08X (e.g. FF 00 1A): ", offset) }, function(input)
    if not input or input == "" then
      return
    end
    local bytes = {}
    for hex in input:gmatch("%x%x") do
      table.insert(bytes, tonumber(hex, 16))
    end
    if #bytes == 0 then
      vim.notify("No valid hex bytes", vim.log.levels.ERROR)
      return
    end
    push_undo()
    set_bytes(offset, bytes)
    refresh_display()
    jump_to_offset(offset + #bytes)
  end)
end

local function do_insert_bytes()
  local offset = get_byte_offset_from_cursor()
  vim.ui.input({ prompt = string.format("Insert hex at 0x%08X: ", offset) }, function(input)
    if not input or input == "" then
      return
    end
    local bytes = {}
    for hex in input:gmatch("%x%x") do
      table.insert(bytes, tonumber(hex, 16))
    end
    if #bytes == 0 then
      vim.notify("No valid hex bytes", vim.log.levels.ERROR)
      return
    end
    push_undo()
    insert_bytes(offset, bytes)
    refresh_display()
    jump_to_offset(offset + #bytes)
  end)
end

local function do_delete_byte()
  local offset = get_byte_offset_from_cursor()
  if state.selecting and state.selection_start then
    local sel_s = math.min(state.selection_start, state.selection_end or offset)
    local sel_e = math.max(state.selection_start, state.selection_end or offset)
    local count = sel_e - sel_s + 1
    push_undo()
    delete_bytes(sel_s, count)
    state.selecting = false
    state.selection_start = nil
    state.selection_end = nil
    refresh_display()
    jump_to_offset(math.min(sel_s, state.file_size - 1))
    vim.notify(string.format("Deleted %d bytes", count), vim.log.levels.INFO)
  else
    push_undo()
    delete_bytes(offset, 1)
    refresh_display()
    jump_to_offset(math.min(offset, state.file_size - 1))
  end
end

local function do_undo()
  if #state.undo_stack == 0 then
    vim.notify("Nothing to undo", vim.log.levels.WARN)
    return
  end
  table.insert(state.redo_stack, state.raw_data)
  state.raw_data = table.remove(state.undo_stack)
  state.file_size = #state.raw_data
  if #state.undo_stack == 0 then
    state.dirty = false
  end
  local offset = get_byte_offset_from_cursor()
  refresh_display()
  jump_to_offset(math.min(offset, state.file_size - 1))
  vim.notify("Undo (" .. #state.undo_stack .. " left)", vim.log.levels.INFO)
end

local function do_redo()
  if #state.redo_stack == 0 then
    vim.notify("Nothing to redo", vim.log.levels.WARN)
    return
  end
  table.insert(state.undo_stack, state.raw_data)
  state.raw_data = table.remove(state.redo_stack)
  state.file_size = #state.raw_data
  state.dirty = true
  local offset = get_byte_offset_from_cursor()
  refresh_display()
  jump_to_offset(math.min(offset, state.file_size - 1))
  vim.notify("Redo (" .. #state.redo_stack .. " left)", vim.log.levels.INFO)
end

local function do_save()
  if not state.file_path then
    vim.notify("No file path", vim.log.levels.ERROR)
    return
  end
  local ok
  if state.big_file then
    ok = write_big_file()
  else
    ok = write_file(state.file_path, state.raw_data)
  end
  if ok then
    state.dirty = false
    state.undo_stack = {}
    state.redo_stack = {}
    state.chunk_dirty = {}
    update_title()
    vim.notify("Written " .. state.file_size .. " bytes → " .. state.file_path, vim.log.levels.INFO)
  else
    vim.notify("Write failed: " .. state.file_path, vim.log.levels.ERROR)
  end
end

local function do_toggle_select()
  if state.selecting then
    state.selecting = false
    vim.notify("Selection cleared", vim.log.levels.INFO)
    local offset = get_byte_offset_from_cursor()
    highlight_cursor_byte(offset)
    update_info_window(offset)
  else
    state.selecting = true
    state.selection_start = get_byte_offset_from_cursor()
    state.selection_end = state.selection_start
    vim.notify(string.format("Select from 0x%08X — move cursor, then v/y/x/F", state.selection_start), vim.log.levels.INFO)
  end
end

local function do_yank()
  local offset = get_byte_offset_from_cursor()
  if state.selecting and state.selection_start then
    local sel_s = math.min(state.selection_start, state.selection_end or offset)
    local sel_e = math.max(state.selection_start, state.selection_end or offset)
    local count = sel_e - sel_s + 1
    local bytes = get_bytes(sel_s, count)
    state.yank_register = bytes
    state.selecting = false
    state.selection_start = nil
    state.selection_end = nil
    local hex_str = ""
    for _, bv in ipairs(bytes) do
      hex_str = hex_str .. string.format("%02X ", bv)
    end
    vim.fn.setreg("+", hex_str:sub(1, -2))
    vim.notify(string.format("Yanked %d bytes", count), vim.log.levels.INFO)
    highlight_cursor_byte(offset)
    update_info_window(offset)
  else
    vim.ui.input({ prompt = "Yank how many bytes? [1]: " }, function(input)
      local count = 1
      if input and input ~= "" then
        count = tonumber(input) or 1
      end
      if count < 1 then
        count = 1
      end
      local bytes = get_bytes(offset, count)
      state.yank_register = bytes
      local hex_str = ""
      for _, bv in ipairs(bytes) do
        hex_str = hex_str .. string.format("%02X ", bv)
      end
      vim.fn.setreg("+", hex_str:sub(1, -2))
      vim.notify(string.format("Yanked %d bytes", #bytes), vim.log.levels.INFO)
    end)
  end
end

local function do_paste()
  if not state.yank_register or #state.yank_register == 0 then
    local clip = vim.fn.getreg("+")
    if clip and clip ~= "" then
      local bytes = {}
      for hex in clip:gmatch("%x%x") do
        table.insert(bytes, tonumber(hex, 16))
      end
      if #bytes > 0 then
        state.yank_register = bytes
      end
    end
  end
  if not state.yank_register or #state.yank_register == 0 then
    vim.notify("Nothing to paste", vim.log.levels.WARN)
    return
  end
  local offset = get_byte_offset_from_cursor()
  vim.ui.select({ "Overwrite", "Insert" }, { prompt = "Paste mode:" }, function(choice)
    if not choice then
      return
    end
    push_undo()
    if choice == "Insert" then
      insert_bytes(offset, state.yank_register)
    else
      set_bytes(offset, state.yank_register)
    end
    refresh_display()
    jump_to_offset(offset + #state.yank_register)
    vim.notify(string.format("Pasted %d bytes (%s)", #state.yank_register, choice:lower()), vim.log.levels.INFO)
  end)
end

local function do_fill_range()
  local offset = get_byte_offset_from_cursor()
  local sel_s, sel_e
  if state.selecting and state.selection_start then
    sel_s = math.min(state.selection_start, state.selection_end or offset)
    sel_e = math.max(state.selection_start, state.selection_end or offset)
    state.selecting = false
    state.selection_start = nil
    state.selection_end = nil
  else
    sel_s = offset
    vim.ui.input({ prompt = string.format("Fill from 0x%08X, count: ", offset) }, function(input)
      if not input or input == "" then
        return
      end
      local count = tonumber(input) or 0
      if count < 1 then
        return
      end
      sel_e = sel_s + count - 1
      vim.ui.input({ prompt = "Fill byte (hex, e.g. 00): " }, function(val_input)
        if not val_input or val_input == "" then
          return
        end
        local fill_val = tonumber(val_input, 16)
        if not fill_val or fill_val < 0 or fill_val > 255 then
          vim.notify("Invalid byte", vim.log.levels.ERROR)
          return
        end
        push_undo()
        local bytes = {}
        for _ = 1, sel_e - sel_s + 1 do
          table.insert(bytes, fill_val)
        end
        set_bytes(sel_s, bytes)
        refresh_display()
        jump_to_offset(sel_s)
        vim.notify(string.format("Filled %d bytes with 0x%02X", #bytes, fill_val), vim.log.levels.INFO)
      end)
    end)
    return
  end

  vim.ui.input({ prompt = "Fill byte (hex, e.g. 00): " }, function(val_input)
    if not val_input or val_input == "" then
      return
    end
    local fill_val = tonumber(val_input, 16)
    if not fill_val or fill_val < 0 or fill_val > 255 then
      vim.notify("Invalid byte", vim.log.levels.ERROR)
      return
    end
    push_undo()
    local bytes = {}
    for _ = 1, sel_e - sel_s + 1 do
      table.insert(bytes, fill_val)
    end
    set_bytes(sel_s, bytes)
    refresh_display()
    jump_to_offset(sel_s)
    vim.notify(string.format("Filled %d bytes with 0x%02X", #bytes, fill_val), vim.log.levels.INFO)
  end)
end

local function do_replace_pattern()
  if state.big_file then
    vim.notify("Replace not supported for large files", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "Find hex (e.g. FF 00): " }, function(find_input)
    if not find_input or find_input == "" then
      return
    end
    local find_bytes = {}
    for hex in find_input:gmatch("%x%x") do
      table.insert(find_bytes, tonumber(hex, 16))
    end
    if #find_bytes == 0 then
      vim.notify("No valid hex in find", vim.log.levels.ERROR)
      return
    end

    vim.ui.input({ prompt = "Replace with hex (e.g. 00 FF): " }, function(repl_input)
      if not repl_input or repl_input == "" then
        return
      end
      local repl_bytes = {}
      for hex in repl_input:gmatch("%x%x") do
        table.insert(repl_bytes, tonumber(hex, 16))
      end
      if #repl_bytes == 0 then
        vim.notify("No valid hex in replace", vim.log.levels.ERROR)
        return
      end
      if #repl_bytes ~= #find_bytes then
        vim.notify("Find/replace must be same length", vim.log.levels.ERROR)
        return
      end

      push_undo()
      local data = state.raw_data
      local count = 0
      local i = 1
      while i <= #data - #find_bytes + 1 do
        local match = true
        for j = 1, #find_bytes do
          if string.byte(data, i + j - 1) ~= find_bytes[j] then
            match = false
            break
          end
        end
        if match then
          for j = 1, #repl_bytes do
            local pos = i + j - 2
            data = data:sub(1, pos) .. string.char(repl_bytes[j]) .. data:sub(pos + 2)
          end
          count = count + 1
          i = i + #find_bytes
        else
          i = i + 1
        end
      end

      state.raw_data = data
      state.dirty = true
      refresh_display()
      vim.notify(string.format("Replaced %d occurrences", count), vim.log.levels.INFO)
    end)
  end)
end

local function close_inspector()
  local function do_close()
    if state.cursor_au then
      vim.api.nvim_del_autocmd(state.cursor_au)
      state.cursor_au = nil
    end
    if state.info_win and vim.api.nvim_win_is_valid(state.info_win) then
      vim.api.nvim_win_close(state.info_win, true)
    end
    if state.info_buf and vim.api.nvim_buf_is_valid(state.info_buf) then
      vim.api.nvim_buf_delete(state.info_buf, { force = true })
    end
    if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
      vim.api.nvim_win_close(state.main_win, true)
    end
    if state.main_buf and vim.api.nvim_buf_is_valid(state.main_buf) then
      vim.api.nvim_buf_delete(state.main_buf, { force = true })
    end
    if state.backdrop_win and vim.api.nvim_win_is_valid(state.backdrop_win) then
      vim.api.nvim_win_close(state.backdrop_win, true)
    end
    if state.backdrop_buf and vim.api.nvim_buf_is_valid(state.backdrop_buf) then
      vim.api.nvim_buf_delete(state.backdrop_buf, { force = true })
    end
    state.main_win = nil
    state.main_buf = nil
    state.info_win = nil
    state.info_buf = nil
    state.backdrop_win = nil
    state.backdrop_buf = nil
    state.raw_data = nil
    state.file_path = nil
    state.file_size = 0
    state.cursor_au = nil
    state.dirty = false
    state.undo_stack = {}
    state.redo_stack = {}
    state.selecting = false
    state.selection_start = nil
    state.selection_end = nil
    state.big_file = false
    state.chunk_cache = {}
    state.chunk_dirty = {}
    invalidate_viewport_cache()
  end

  if state.dirty then
    vim.ui.select({ "Save and quit", "Quit without saving", "Cancel" }, {
      prompt = "Unsaved changes!",
    }, function(choice)
      if choice == "Save and quit" then
        do_save()
        do_close()
      elseif choice == "Quit without saving" then
        do_close()
      end
    end)
  else
    do_close()
  end
end

function M.open(path)
  path = path or vim.fn.expand("%:p")
  if path == "" or vim.fn.filereadable(path) == 0 then
    vim.notify("HexEditor: Cannot read file", vim.log.levels.ERROR)
    return
  end

  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    close_inspector()
  end

  setup_highlights()

  local fsize = get_file_size(path)
  if not fsize or fsize == 0 then
    vim.notify("HexEditor: File is empty or unreadable", vim.log.levels.ERROR)
    return
  end

  state.file_path = path
  state.file_size = fsize
  state.dirty = false
  state.undo_stack = {}
  state.redo_stack = {}
  state.selecting = false
  state.selection_start = nil
  state.selection_end = nil
  state.yank_register = nil
  state.chunk_cache = {}
  state.chunk_dirty = {}
  invalidate_viewport_cache()

  local lines
  if fsize > MAX_MEMORY_FILE then
    state.big_file = true
    state.raw_data = nil
    local total = total_lines_for_file()
    local preview_lines = math.min(total, vim.o.lines - 8)
    lines = format_lines_for_viewport(0, preview_lines)
  else
    state.big_file = false
    local data = read_file(path)
    if not data or #data == 0 then
      vim.notify("HexEditor: File is empty or unreadable", vim.log.levels.ERROR)
      return
    end
    state.raw_data = data
    lines = format_lines(data)
  end

  local total_line_count = state.big_file and total_lines_for_file() or #lines

  local ui_width = vim.o.columns
  local ui_height = vim.o.lines
  local main_width = ASCII_START_COL + BYTES_PER_LINE + math.floor((BYTES_PER_LINE - 1) / 4) + 10
  if main_width > ui_width - 4 then
    main_width = ui_width - 4
  end
  local info_width = 36
  local total_width = main_width + info_width + 3
  local main_height = math.min(total_line_count, ui_height - 8)
  if main_height < 10 then
    main_height = 10
  end

  local start_col = math.floor((ui_width - total_width) / 2)
  if start_col < 0 then
    start_col = 0
  end
  local start_row = math.floor((ui_height - main_height - 4) / 2) + 1
  if start_row < 0 then
    start_row = 0
  end

  local fname = vim.fn.fnamemodify(path, ":t")
  local size_str
  if fsize >= 1048576 then
    size_str = string.format("%.2f MB", fsize / 1048576)
  elseif fsize >= 1024 then
    size_str = string.format("%.1f KB", fsize / 1024)
  else
    size_str = fsize .. " B"
  end
  local tpl = vertex_templates[state.current_template]
  local big_mark = state.big_file and " │ STREAM" or ""
  local title = " HexEditor │ " .. fname .. " │ " .. size_str .. " │ " .. tpl.name .. big_mark .. " "

  state.backdrop_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.backdrop_buf].buftype = "nofile"
  vim.bo[state.backdrop_buf].bufhidden = "wipe"
  vim.bo[state.backdrop_buf].swapfile = false
  state.backdrop_win = vim.api.nvim_open_win(state.backdrop_buf, false, {
    relative = "editor",
    width = ui_width,
    height = ui_height,
    row = 0,
    col = 0,
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 40,
    noautocmd = true,
  })
  vim.wo[state.backdrop_win].winblend = 0
  vim.wo[state.backdrop_win].winhighlight = "Normal:HexInspBackdrop"

  state.main_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.main_buf].buftype = "nofile"
  vim.bo[state.main_buf].bufhidden = "wipe"
  vim.bo[state.main_buf].swapfile = false
  vim.bo[state.main_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)
  vim.bo[state.main_buf].modifiable = false

  state.main_win = vim.api.nvim_open_win(state.main_buf, true, {
    relative = "editor",
    width = main_width,
    height = main_height,
    row = start_row,
    col = start_col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    noautocmd = true,
    zindex = 50,
  })

  vim.wo[state.main_win].number = false
  vim.wo[state.main_win].relativenumber = false
  vim.wo[state.main_win].signcolumn = "no"
  vim.wo[state.main_win].cursorline = true
  vim.wo[state.main_win].wrap = false
  vim.wo[state.main_win].winblend = 0
  vim.wo[state.main_win].winhighlight = "Normal:HexInspNormal,FloatBorder:HexInspBorder,FloatTitle:HexInspTitle,CursorLine:HexInspCursorLine"

  apply_line_highlights(state.main_buf, lines, state.raw_data, state.big_file and 0 or nil)

  state.info_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.info_buf].buftype = "nofile"
  vim.bo[state.info_buf].bufhidden = "wipe"
  vim.bo[state.info_buf].swapfile = false
  vim.bo[state.info_buf].modifiable = false

  state.info_win = vim.api.nvim_open_win(state.info_buf, false, {
    relative = "editor",
    width = info_width,
    height = main_height,
    row = start_row,
    col = start_col + main_width + 2,
    style = "minimal",
    border = "rounded",
    title = " Data Inspector ",
    title_pos = "center",
    noautocmd = true,
    focusable = false,
    zindex = 50,
  })

  vim.wo[state.info_win].number = false
  vim.wo[state.info_win].relativenumber = false
  vim.wo[state.info_win].signcolumn = "no"
  vim.wo[state.info_win].wrap = false
  vim.wo[state.info_win].winblend = 0
  vim.wo[state.info_win].winhighlight = "Normal:HexInspInfoNormal,FloatBorder:HexInspBorder,FloatTitle:HexInspTitle"

  local function on_cursor_move()
    if not state.main_win or not vim.api.nvim_win_is_valid(state.main_win) then
      return
    end
    local offset = get_byte_offset_from_cursor()
    highlight_cursor_byte(offset)
    update_info_window(offset)
  end

  state.cursor_au = vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = state.main_buf,
    callback = on_cursor_move,
  })

  local kopts = { buffer = state.main_buf, nowait = true, silent = true }

  vim.keymap.set("n", "q", close_inspector, kopts)
  vim.keymap.set("n", "<Esc>", function()
    if state.selecting then
      state.selecting = false
      state.selection_start = nil
      state.selection_end = nil
      vim.notify("Selection cleared", vim.log.levels.INFO)
      local off = get_byte_offset_from_cursor()
      highlight_cursor_byte(off)
      update_info_window(off)
    else
      close_inspector()
    end
  end, kopts)

  vim.keymap.set("n", "g", prompt_jump, kopts)
  vim.keymap.set("n", "/", prompt_search_bytes, kopts)
  vim.keymap.set("n", "n", search_next, kopts)
  vim.keymap.set("n", "e", do_edit_byte, kopts)
  vim.keymap.set("n", "E", do_edit_ascii, kopts)
  vim.keymap.set("n", "m", do_edit_multi, kopts)
  vim.keymap.set("n", "I", do_insert_bytes, kopts)
  vim.keymap.set("n", "x", do_delete_byte, kopts)
  vim.keymap.set("n", "u", do_undo, kopts)
  vim.keymap.set("n", "U", do_redo, kopts)
  vim.keymap.set("n", "w", do_save, kopts)
  vim.keymap.set("n", "v", do_toggle_select, kopts)
  vim.keymap.set("n", "y", do_yank, kopts)
  vim.keymap.set("n", "p", do_paste, kopts)
  vim.keymap.set("n", "F", do_fill_range, kopts)
  vim.keymap.set("n", "R", do_replace_pattern, kopts)

  vim.keymap.set("n", "T", function()
    state.current_template = (state.current_template % #vertex_templates) + 1
    update_title()
    local off = get_byte_offset_from_cursor()
    update_info_window(off)
    vim.notify("Template: " .. vertex_templates[state.current_template].name, vim.log.levels.INFO)
  end, kopts)

  vim.keymap.set("n", "t", function()
    local names = {}
    for i, t in ipairs(vertex_templates) do
      local marker = i == state.current_template and " ●" or ""
      table.insert(names, t.name .. marker)
    end
    vim.ui.select(names, { prompt = "Vertex Template:" }, function(_, idx)
      if not idx then
        return
      end
      state.current_template = idx
      update_title()
      local off = get_byte_offset_from_cursor()
      update_info_window(off)
      vim.notify("Template: " .. vertex_templates[idx].name, vim.log.levels.INFO)
    end)
  end, kopts)

  vim.keymap.set("n", "<C-d>", function()
    local target = get_byte_offset_from_cursor() + (BYTES_PER_LINE * 16)
    jump_to_offset(target)
  end, kopts)

  vim.keymap.set("n", "<C-u>", function()
    local target = get_byte_offset_from_cursor() - (BYTES_PER_LINE * 16)
    jump_to_offset(target)
  end, kopts)

  vim.keymap.set("n", "G", function()
    jump_to_offset(state.file_size - 1)
  end, kopts)

  vim.keymap.set("n", "gg", function()
    jump_to_offset(0)
  end, kopts)

  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = state.main_buf,
    once = true,
    callback = function()
      vim.schedule(close_inspector)
    end,
  })

  vim.schedule(on_cursor_move)
end

function M.setup(opts)
  opts = opts or {}
  if opts.colors then
    config.colors = vim.tbl_extend("force", config.colors, opts.colors)
  end
  if opts.bytes_per_line then
    config.bytes_per_line = opts.bytes_per_line
  end
  if opts.max_undo then
    config.max_undo = opts.max_undo
  end
  if opts.chunk_size then
    config.chunk_size = opts.chunk_size
  end
  if opts.max_memory_file then
    config.max_memory_file = opts.max_memory_file
  end
  if opts.vertex_templates then
    for _, t in ipairs(opts.vertex_templates) do
      table.insert(vertex_templates, t)
    end
  end
  apply_config()
end

return M
