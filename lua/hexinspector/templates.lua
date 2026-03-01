---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local M = {}

M.list = {
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

return M
