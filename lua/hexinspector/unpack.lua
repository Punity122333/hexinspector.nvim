---@diagnostic disable: param-type-mismatch, undefined-global, deprecated
local state = require("hexinspector.state")

local M = {}

function M.u8(data, pos)
  return string.byte(data, pos)
end

function M.i8(data, pos)
  local b = string.byte(data, pos)
  if b >= 128 then
    return b - 256
  end
  return b
end

function M.u16_le(data, pos)
  local b0, b1 = string.byte(data, pos, pos + 1)
  return b0 + b1 * 256
end

function M.u16_be(data, pos)
  local b0, b1 = string.byte(data, pos, pos + 1)
  return b0 * 256 + b1
end

function M.u16(data, pos)
  if state.big_endian then
    return M.u16_be(data, pos)
  end
  return M.u16_le(data, pos)
end

function M.i16_le(data, pos)
  local v = M.u16_le(data, pos)
  if v >= 32768 then
    return v - 65536
  end
  return v
end

function M.i16_be(data, pos)
  local v = M.u16_be(data, pos)
  if v >= 32768 then
    return v - 65536
  end
  return v
end

function M.i16(data, pos)
  if state.big_endian then
    return M.i16_be(data, pos)
  end
  return M.i16_le(data, pos)
end

function M.u32_le(data, pos)
  local b0, b1, b2, b3 = string.byte(data, pos, pos + 3)
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

function M.u32_be(data, pos)
  local b0, b1, b2, b3 = string.byte(data, pos, pos + 3)
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3
end

function M.u32(data, pos)
  if state.big_endian then
    return M.u32_be(data, pos)
  end
  return M.u32_le(data, pos)
end

function M.i32_le(data, pos)
  local v = M.u32_le(data, pos)
  if v >= 2147483648 then
    return v - 4294967296
  end
  return v
end

function M.i32_be(data, pos)
  local v = M.u32_be(data, pos)
  if v >= 2147483648 then
    return v - 4294967296
  end
  return v
end

function M.i32(data, pos)
  if state.big_endian then
    return M.i32_be(data, pos)
  end
  return M.i32_le(data, pos)
end

function M.f32_le(data, pos)
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

function M.f32_be(data, pos)
  local b0, b1, b2, b3 = string.byte(data, pos, pos + 3)
  local sign = 1
  if b0 >= 128 then
    sign = -1
    b0 = b0 - 128
  end
  local exponent = b0 * 2 + math.floor(b1 / 128)
  local mantissa = (b1 % 128) * 65536 + b2 * 256 + b3
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

function M.f32(data, pos)
  if state.big_endian then
    return M.f32_be(data, pos)
  end
  return M.f32_le(data, pos)
end

function M.f64_le(data, pos)
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

function M.f64_be(data, pos)
  local b0, b1, b2, b3, b4, b5, b6, b7 = string.byte(data, pos, pos + 7)
  local sign = 1
  if b0 >= 128 then
    sign = -1
    b0 = b0 - 128
  end
  local exponent = b0 * 16 + math.floor(b1 / 16)
  local hi_mant = (b1 % 16) * 281474976710656 + b2 * 1099511627776 + b3 * 4294967296
  local lo_mant = b4 * 16777216 + b5 * 65536 + b6 * 256 + b7
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

function M.f64(data, pos)
  if state.big_endian then
    return M.f64_be(data, pos)
  end
  return M.f64_le(data, pos)
end

return M
