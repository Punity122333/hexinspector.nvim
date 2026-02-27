---@diagnostic disable: undefined-global
if vim.g.loaded_hexinspector then
  return
end
vim.g.loaded_hexinspector = true

vim.api.nvim_create_user_command("HexEdit", function(cmd)
  local fpath = cmd.args ~= "" and cmd.args or nil
  require("hexinspector").open(fpath)
end, { nargs = "?", complete = "file", desc = "Open Hex Editor" })

vim.api.nvim_create_user_command("HexInspect", function(cmd)
  local fpath = cmd.args ~= "" and cmd.args or nil
  require("hexinspector").open(fpath)
end, { nargs = "?", complete = "file", desc = "Open Hex Editor" })
