---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local cfg = require("hexinspector.config")
local state = require("hexinspector.state")
local fileio = require("hexinspector.fileio")
local buffer = require("hexinspector.buffer")
local highlights = require("hexinspector.highlights")
local templates = require("hexinspector.templates")

local M = {}

function M.format_lines(data)
  local lines = {}
  local BYTES_PER_LINE = cfg.BYTES_PER_LINE
  local PAD = cfg.PAD
  local HEX_START_COL = cfg.HEX_START_COL
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
          b = fileio.get_byte(offset + i - 1)
        end
        if b then
          hex_parts[i] = buffer.byte_to_hex(b)
          ascii_parts[i] = buffer.byte_to_ascii(b)
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

function M.format_lines_for_viewport(start_line, num_lines)
  local lines = {}
  local BYTES_PER_LINE = cfg.BYTES_PER_LINE
  local PAD = cfg.PAD
  local total = state.file_size
  for li = 0, num_lines - 1 do
    local row = start_line + li
    if state.viewport_line_cache[row] then
      table.insert(lines, state.viewport_line_cache[row])
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
          local b = fileio.get_byte(offset + i - 1)
          if b then
            hex_parts[i] = buffer.byte_to_hex(b)
            ascii_parts[i] = buffer.byte_to_ascii(b)
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
      state.viewport_line_cache[row] = line
      table.insert(lines, line)
    end
  end
  return lines
end

function M.total_lines_for_file()
  return math.ceil(state.file_size / cfg.BYTES_PER_LINE)
end

function M.update_title()
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
  local tpl = templates.list[state.current_template]
  local big_mark = state.big_file and " │ STREAM" or ""
  local endian_mark = state.big_endian and " │ BE" or " │ LE"
  local title = " HexEditor │ " .. fname .. dirty_mark .. " │ " .. size_str .. " │ " .. tpl.name .. endian_mark .. big_mark .. " "
  vim.api.nvim_win_set_config(state.main_win, { title = title, title_pos = "center" })
end

function M.refresh_display()
  if not state.main_buf or not vim.api.nvim_buf_is_valid(state.main_buf) then
    return
  end
  if state.big_file then
    local cursor = vim.api.nvim_win_get_cursor(state.main_win)
    local win_height = vim.api.nvim_win_get_height(state.main_win)
    local top_line = math.max(0, cursor[1] - 1 - math.floor(win_height / 2))
    local total = M.total_lines_for_file()
    local num_lines = math.min(total - top_line, total)
    local lines = M.format_lines_for_viewport(top_line, num_lines)
    vim.bo[state.main_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)
    vim.bo[state.main_buf].modifiable = false
    highlights.apply_line_highlights(state.main_buf, lines, nil, top_line)
    M.update_title()
    return
  end
  local data = state.raw_data
  if not data then
    return
  end
  local lines = M.format_lines(data)
  vim.bo[state.main_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)
  vim.bo[state.main_buf].modifiable = false
  highlights.apply_line_highlights(state.main_buf, lines, data)
  M.update_title()
end

return M
