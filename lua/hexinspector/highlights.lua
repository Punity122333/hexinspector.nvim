---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local cfg = require("hexinspector.config")
local state = require("hexinspector.state")

local M = {}

function M.setup_highlights()
  local hl = vim.api.nvim_set_hl
  local bg = cfg.get_color("bg")
  local info_bg = cfg.get_color("info_bg")
  hl(0, "HexInspAddr", { fg = cfg.get_color("addr"), bg = bg, bold = true })
  hl(0, "HexInspByte", { fg = cfg.get_color("hex"), bg = bg })
  hl(0, "HexInspNull", { fg = cfg.get_color("null"), bg = bg })
  hl(0, "HexInspAscii", { fg = cfg.get_color("ascii"), bg = bg })
  hl(0, "HexInspNonPrint", { fg = cfg.get_color("null"), bg = bg })
  hl(0, "HexInspCursor", { bg = cfg.get_color("cursor_bg"), fg = cfg.get_color("hex"), bold = true })
  hl(0, "HexInspFloat", { fg = cfg.get_color("float"), bg = info_bg, bold = true })
  hl(0, "HexInspInt", { fg = cfg.get_color("int"), bg = info_bg })
  hl(0, "HexInspUint", { fg = cfg.get_color("uint"), bg = info_bg })
  hl(0, "HexInspTitle", { fg = cfg.get_color("title"), bg = bg, bold = true })
  hl(0, "HexInspBorder", { fg = cfg.get_color("border"), bg = bg })
  hl(0, "HexInspNormal", { fg = cfg.get_color("hex"), bg = bg })
  hl(0, "HexInspInfoNormal", { fg = cfg.get_color("hex"), bg = info_bg })
  hl(0, "HexInspInfoBorder", { fg = cfg.get_color("border"), bg = info_bg })
  hl(0, "HexInspSearch", { fg = cfg.get_color("search"), bg = bg, bold = true })
  hl(0, "HexInspLabel", { fg = cfg.get_color("addr"), bg = info_bg })
  hl(0, "HexInspSep", { fg = cfg.get_color("null"), bg = bg })
  hl(0, "HexInspBackdrop", { bg = bg })
  hl(0, "HexInspModified", { fg = cfg.get_color("modified"), bg = bg, bold = true })
  hl(0, "HexInspSelection", { bg = cfg.get_color("selection_bg"), fg = cfg.get_color("hex") })
  hl(0, "HexInspCursorLine", { bg = cfg.get_color("cursor_line_bg") })
end

function M.apply_line_highlights(buf, lines, data, base_line)
  local ns = state.ns
  local BYTES_PER_LINE = cfg.BYTES_PER_LINE
  local HEX_START_COL = cfg.HEX_START_COL
  local fileio = require("hexinspector.fileio")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local total = state.big_file and state.file_size or #data
  base_line = base_line or 0

  for line_idx, line_str in ipairs(lines) do
    local row = line_idx - 1
    local line_offset = (base_line + row) * BYTES_PER_LINE

    vim.api.nvim_buf_add_highlight(buf, ns, "HexInspAddr", row, 1, 9)
    vim.api.nvim_buf_add_highlight(buf, ns, "HexInspSep", row, 9, 14)

    local col = HEX_START_COL
    for i = 0, BYTES_PER_LINE - 1 do
      if i > 0 and i % 4 == 0 then
        col = col + 1
      end
      local byte_offset = line_offset + i
      if byte_offset < total then
        local b = fileio.get_byte(byte_offset)
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
        local b = fileio.get_byte(byte_offset)
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

function M.highlight_cursor_byte(offset)
  if not state.main_buf or not vim.api.nvim_buf_is_valid(state.main_buf) then
    return
  end

  local BYTES_PER_LINE = cfg.BYTES_PER_LINE
  local HEX_START_COL = cfg.HEX_START_COL
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

return M
