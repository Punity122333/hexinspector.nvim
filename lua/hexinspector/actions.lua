---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local state = require("hexinspector.state")
local fileio = require("hexinspector.fileio")
local buffer = require("hexinspector.buffer")
local display = require("hexinspector.display")
local cursor = require("hexinspector.cursor")
local highlights = require("hexinspector.highlights")

local M = {}

function M.do_edit_byte()
  local offset = cursor.get_byte_offset_from_cursor()
  local current = fileio.get_byte(offset)
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
    buffer.push_undo()
    buffer.set_byte(offset, val)
    display.refresh_display()
    cursor.jump_to_offset(offset + 1)
  end)
end

function M.do_edit_ascii()
  local offset = cursor.get_byte_offset_from_cursor()
  local current = fileio.get_byte(offset)
  if not current then
    return
  end
  local cur_char = (current >= 0x20 and current <= 0x7E) and string.char(current) or "."
  vim.ui.input({ prompt = string.format("ASCII at 0x%08X [%s] → ", offset, cur_char) }, function(input)
    if not input or input == "" then
      return
    end
    buffer.push_undo()
    for i = 1, #input do
      local c = string.byte(input, i)
      if offset + i - 1 < state.file_size then
        buffer.set_byte(offset + i - 1, c)
      end
    end
    display.refresh_display()
    cursor.jump_to_offset(offset + #input)
  end)
end

function M.do_edit_multi()
  local offset = cursor.get_byte_offset_from_cursor()
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
    buffer.push_undo()
    buffer.set_bytes(offset, bytes)
    display.refresh_display()
    cursor.jump_to_offset(offset + #bytes)
  end)
end

function M.do_insert_bytes()
  local offset = cursor.get_byte_offset_from_cursor()
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
    buffer.push_undo()
    buffer.insert_bytes(offset, bytes)
    display.refresh_display()
    cursor.jump_to_offset(offset + #bytes)
  end)
end

function M.do_delete_byte()
  local offset = cursor.get_byte_offset_from_cursor()
  if state.selecting and state.selection_start then
    local sel_s = math.min(state.selection_start, state.selection_end or offset)
    local sel_e = math.max(state.selection_start, state.selection_end or offset)
    local count = sel_e - sel_s + 1
    buffer.push_undo()
    buffer.delete_bytes(sel_s, count)
    state.selecting = false
    state.selection_start = nil
    state.selection_end = nil
    display.refresh_display()
    cursor.jump_to_offset(math.min(sel_s, state.file_size - 1))
    vim.notify(string.format("Deleted %d bytes", count), vim.log.levels.INFO)
  else
    buffer.push_undo()
    buffer.delete_bytes(offset, 1)
    display.refresh_display()
    cursor.jump_to_offset(math.min(offset, state.file_size - 1))
  end
end

function M.do_undo()
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
  local offset = cursor.get_byte_offset_from_cursor()
  display.refresh_display()
  cursor.jump_to_offset(math.min(offset, state.file_size - 1))
  vim.notify("Undo (" .. #state.undo_stack .. " left)", vim.log.levels.INFO)
end

function M.do_redo()
  if #state.redo_stack == 0 then
    vim.notify("Nothing to redo", vim.log.levels.WARN)
    return
  end
  table.insert(state.undo_stack, state.raw_data)
  state.raw_data = table.remove(state.redo_stack)
  state.file_size = #state.raw_data
  state.dirty = true
  local offset = cursor.get_byte_offset_from_cursor()
  display.refresh_display()
  cursor.jump_to_offset(math.min(offset, state.file_size - 1))
  vim.notify("Redo (" .. #state.redo_stack .. " left)", vim.log.levels.INFO)
end

function M.do_save()
  if not state.file_path then
    vim.notify("No file path", vim.log.levels.ERROR)
    return
  end
  local ok
  if state.big_file then
    ok = fileio.write_big_file()
  else
    ok = fileio.write_file(state.file_path, state.raw_data)
  end
  if ok then
    state.dirty = false
    state.undo_stack = {}
    state.redo_stack = {}
    state.chunk_dirty = {}
    display.update_title()
    vim.notify("Written " .. state.file_size .. " bytes → " .. state.file_path, vim.log.levels.INFO)
  else
    vim.notify("Write failed: " .. state.file_path, vim.log.levels.ERROR)
  end
end

function M.do_toggle_select()
  if state.selecting then
    state.selecting = false
    vim.notify("Selection cleared", vim.log.levels.INFO)
    local offset = cursor.get_byte_offset_from_cursor()
    highlights.highlight_cursor_byte(offset)
    cursor.update_info_window(offset)
  else
    state.selecting = true
    state.selection_start = cursor.get_byte_offset_from_cursor()
    state.selection_end = state.selection_start
    vim.notify(string.format("Select from 0x%08X — move cursor, then v/y/x/F", state.selection_start), vim.log.levels.INFO)
  end
end

function M.do_yank()
  local offset = cursor.get_byte_offset_from_cursor()
  if state.selecting and state.selection_start then
    local sel_s = math.min(state.selection_start, state.selection_end or offset)
    local sel_e = math.max(state.selection_start, state.selection_end or offset)
    local count = sel_e - sel_s + 1
    local bytes = fileio.get_bytes(sel_s, count)
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
    highlights.highlight_cursor_byte(offset)
    cursor.update_info_window(offset)
  else
    vim.ui.input({ prompt = "Yank how many bytes? [1]: " }, function(input)
      local count = 1
      if input and input ~= "" then
        count = tonumber(input) or 1
      end
      if count < 1 then
        count = 1
      end
      local bytes = fileio.get_bytes(offset, count)
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

function M.do_paste()
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
  local offset = cursor.get_byte_offset_from_cursor()
  vim.ui.select({ "Overwrite", "Insert" }, { prompt = "Paste mode:" }, function(choice)
    if not choice then
      return
    end
    buffer.push_undo()
    if choice == "Insert" then
      buffer.insert_bytes(offset, state.yank_register)
    else
      buffer.set_bytes(offset, state.yank_register)
    end
    display.refresh_display()
    cursor.jump_to_offset(offset + #state.yank_register)
    vim.notify(string.format("Pasted %d bytes (%s)", #state.yank_register, choice:lower()), vim.log.levels.INFO)
  end)
end

function M.do_fill_range()
  local offset = cursor.get_byte_offset_from_cursor()
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
        buffer.push_undo()
        local bytes = {}
        for _ = 1, sel_e - sel_s + 1 do
          table.insert(bytes, fill_val)
        end
        buffer.set_bytes(sel_s, bytes)
        display.refresh_display()
        cursor.jump_to_offset(sel_s)
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
    buffer.push_undo()
    local bytes = {}
    for _ = 1, sel_e - sel_s + 1 do
      table.insert(bytes, fill_val)
    end
    buffer.set_bytes(sel_s, bytes)
    display.refresh_display()
    cursor.jump_to_offset(sel_s)
    vim.notify(string.format("Filled %d bytes with 0x%02X", #bytes, fill_val), vim.log.levels.INFO)
  end)
end

function M.do_replace_pattern()
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

      buffer.push_undo()
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
      display.refresh_display()
      vim.notify(string.format("Replaced %d occurrences", count), vim.log.levels.INFO)
    end)
  end)
end

function M.close_inspector()
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
    state.reset()
  end

  if state.dirty then
    vim.ui.select({ "Save and quit", "Quit without saving", "Cancel" }, {
      prompt = "Unsaved changes!",
    }, function(choice)
      if choice == "Save and quit" then
        M.do_save()
        do_close()
      elseif choice == "Quit without saving" then
        do_close()
      end
    end)
  else
    do_close()
  end
end

return M
