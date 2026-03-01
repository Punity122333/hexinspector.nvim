---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local cfg = require("hexinspector.config")
local state = require("hexinspector.state")
local fileio = require("hexinspector.fileio")
local unpack = require("hexinspector.unpack")
local templates = require("hexinspector.templates")

local M = {}

function M.get_byte_offset_from_cursor()
  if not state.main_win or not vim.api.nvim_win_is_valid(state.main_win) then
    return 0
  end
  local BYTES_PER_LINE = cfg.BYTES_PER_LINE
  local HEX_START_COL = cfg.HEX_START_COL
  local cursor = vim.api.nvim_win_get_cursor(state.main_win)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line_offset = row * BYTES_PER_LINE

  local line = vim.api.nvim_buf_get_lines(state.main_buf, row, row + 1, false)[1]
  if line then
    local ascii_byte_start = #line - BYTES_PER_LINE
    if col >= ascii_byte_start then
      local byte_idx = col - ascii_byte_start
      if byte_idx >= BYTES_PER_LINE then
        byte_idx = BYTES_PER_LINE - 1
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
  end

  if col < HEX_START_COL then
    return line_offset
  end

  local hex_col = col - HEX_START_COL
  local byte_idx = 0

  for i = 0, BYTES_PER_LINE - 1 do
    local group_count = math.floor(i / 4)
    local start_c = i * 3 + group_count
    local next_start
    if i < BYTES_PER_LINE - 1 then
      local next_group = math.floor((i + 1) / 4)
      next_start = (i + 1) * 3 + next_group
    else
      next_start = start_c + 3
    end
    if hex_col >= start_c and hex_col < next_start then
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

function M.jump_to_offset(target)
  if not state.main_buf or not state.main_win then
    return
  end
  local BYTES_PER_LINE = cfg.BYTES_PER_LINE
  local HEX_START_COL = cfg.HEX_START_COL
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

function M.update_info_window(offset)
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
  local slice = fileio.get_data_slice(offset, 8)
  if not slice or #slice == 0 then
    return
  end
  local lines = {}
  local hl_map = {}

  table.insert(lines, " Offset: 0x" .. string.format("%08X", offset) .. " (" .. offset .. ")")
  table.insert(hl_map, { "HexInspTitle", #lines })

  table.insert(lines, "")

  local b = unpack.u8(slice, 1)
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

  local int8 = unpack.i8(slice, 1)
  table.insert(lines, " Int8:    " .. int8)
  table.insert(hl_map, { "HexInspInt", #lines })

  if #slice >= 2 and offset + 2 <= size then
    table.insert(lines, "")
    local u16 = unpack.u16_le(slice, 1)
    table.insert(lines, " Uint16:  " .. u16)
    table.insert(hl_map, { "HexInspUint", #lines })
    local i16 = unpack.i16_le(slice, 1)
    table.insert(lines, " Int16:   " .. i16)
    table.insert(hl_map, { "HexInspInt", #lines })
  end

  if #slice >= 4 and offset + 4 <= size then
    table.insert(lines, "")
    local u32 = unpack.u32_le(slice, 1)
    table.insert(lines, " Uint32:  " .. u32)
    table.insert(hl_map, { "HexInspUint", #lines })
    local i32 = unpack.i32_le(slice, 1)
    table.insert(lines, " Int32:   " .. i32)
    table.insert(hl_map, { "HexInspInt", #lines })
    local f32 = unpack.f32_le(slice, 1)
    table.insert(lines, string.format(" Float32: %.8g", f32))
    table.insert(hl_map, { "HexInspFloat", #lines })
  end

  if #slice >= 8 and offset + 8 <= size then
    local f64 = unpack.f64_le(slice, 1)
    table.insert(lines, string.format(" Float64: %.15g", f64))
    table.insert(hl_map, { "HexInspFloat", #lines })
  end

  table.insert(lines, "")

  local tpl = templates.list[state.current_template]
  local vertex_base = offset - (offset % tpl.stride)
  if vertex_base + tpl.stride <= size then
    local vslice = fileio.get_data_slice(vertex_base, tpl.stride)
    if vslice and #vslice >= tpl.stride then
      table.insert(lines, " ── " .. tpl.name .. " ──")
      table.insert(hl_map, { "HexInspTitle", #lines })
      for _, field in ipairs(tpl.fields) do
        local fo = field.offset + 1
        if field.type == "float3" and fo + 11 <= #vslice then
          local x = unpack.f32_le(vslice, fo)
          local y = unpack.f32_le(vslice, fo + 4)
          local z = unpack.f32_le(vslice, fo + 8)
          table.insert(lines, string.format(" %s: (%.4f, %.4f, %.4f)", field.name, x, y, z))
          table.insert(hl_map, { "HexInspFloat", #lines })
        elseif field.type == "float2" and fo + 7 <= #vslice then
          local x = unpack.f32_le(vslice, fo)
          local y = unpack.f32_le(vslice, fo + 4)
          table.insert(lines, string.format(" %s: (%.4f, %.4f)", field.name, x, y))
          table.insert(hl_map, { "HexInspFloat", #lines })
        elseif field.type == "float1" and fo + 3 <= #vslice then
          local x = unpack.f32_le(vslice, fo)
          table.insert(lines, string.format(" %s: %.4f", field.name, x))
          table.insert(hl_map, { "HexInspFloat", #lines })
        elseif field.type == "u8" and fo <= #vslice then
          local v = unpack.u8(vslice, fo)
          table.insert(lines, string.format(" %s: %d (0x%02X)", field.name, v, v))
          table.insert(hl_map, { "HexInspUint", #lines })
        elseif field.type == "u16" and fo + 1 <= #vslice then
          local v = unpack.u16_le(vslice, fo)
          table.insert(lines, string.format(" %s: %d", field.name, v))
          table.insert(hl_map, { "HexInspUint", #lines })
        elseif field.type == "u32" and fo + 3 <= #vslice then
          local v = unpack.u32_le(vslice, fo)
          table.insert(lines, string.format(" %s: %d", field.name, v))
          table.insert(hl_map, { "HexInspUint", #lines })
        elseif field.type == "i32" and fo + 3 <= #vslice then
          local v = unpack.i32_le(vslice, fo)
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

return M
