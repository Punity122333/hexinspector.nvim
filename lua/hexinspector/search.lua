---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local state = require("hexinspector.state")
local fileio = require("hexinspector.fileio")
local cursor = require("hexinspector.cursor")

local M = {}

function M.search_pattern(pattern, start_after)
  if state.big_file then
    local plen = #pattern
    local function check_at(pos)
      for j = 0, plen - 1 do
        local b = fileio.get_byte(pos + j)
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

function M.prompt_jump()
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
      cursor.jump_to_offset(val)
    else
      vim.notify("Invalid offset: " .. input, vim.log.levels.ERROR)
    end
  end)
end

function M.prompt_search_bytes()
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
    local current_offset = cursor.get_byte_offset_from_cursor() + 1
    local found = M.search_pattern(pattern, current_offset)
    if found then
      cursor.jump_to_offset(found)
      local wrapped = found < current_offset - 1
      vim.notify(string.format("Found at 0x%08X%s", found, wrapped and " (wrapped)" or ""), vim.log.levels.INFO)
    else
      vim.notify("Pattern not found", vim.log.levels.WARN)
    end
  end)
end

function M.search_next()
  if not state.last_search then
    vim.notify("No previous search", vim.log.levels.WARN)
    return
  end
  local current_offset = cursor.get_byte_offset_from_cursor() + 1
  local found = M.search_pattern(state.last_search, current_offset)
  if found then
    cursor.jump_to_offset(found)
    local wrapped = found < current_offset - 1
    vim.notify(string.format("Found at 0x%08X%s", found, wrapped and " (wrapped)" or ""), vim.log.levels.INFO)
  else
    vim.notify("Pattern not found", vim.log.levels.WARN)
  end
end

return M
