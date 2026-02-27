# hexinspector.nvim

A floating hex editor and binary data inspector for Neovim.

## Features

- Floating hex view with address, hex bytes, and ASCII columns
- Side panel data inspector (uint8/16/32, int8/16/32, float32/64, binary)
- Vertex buffer template overlays (Pos+Color, Pos+UV+Normal, RGBA8888, etc.)
- Visual byte selection with yank/delete/fill
- Hex byte search with wrap-around
- Find and replace hex patterns
- Insert and delete bytes
- Undo/redo stack (up to 200 levels)
- Streaming mode for files larger than 64MB
- Clipboard integration

## Requirements

- Neovim >= 0.9.0

## Installation

### lazy.nvim

```lua
{
  "Punity122333/hexinspector.nvim",
  cmd = { "HexEdit", "HexInspect" },
  keys = {
    { "<leader>zx", function() require("hexinspector").open() end, desc = "Hex Editor" },
    {
      "<leader>zX",
      function()
        vim.ui.input({ prompt = "File path: ", default = vim.fn.expand("%:p") }, function(input)
          if input and input ~= "" then
            require("hexinspector").open(input)
          end
        end)
      end,
      desc = "Hex Editor (Pick File)",
    },
  },
  opts = {},
}
```

### packer.nvim

```lua
use {
  "Punity122333/hexinspector.nvim",
  config = function()
    require("hexinspector").setup({})
  end,
}
```

## Usage

```
:HexEdit [path]
:HexInspect [path]
```

If no path is given, the current buffer's file is opened.

## Keybindings

| Key | Action |
|-----|--------|
| `e` | Edit byte (hex) |
| `E` | Edit byte (ASCII) |
| `m` | Edit multi-byte |
| `I` | Insert bytes |
| `x` | Delete byte(s) |
| `v` | Visual select |
| `y` | Yank bytes |
| `p` | Paste bytes |
| `F` | Fill range |
| `R` | Replace pattern |
| `w` | Write to disk |
| `u` | Undo |
| `U` | Redo |
| `g` | Jump to offset |
| `/` | Search hex bytes |
| `n` | Next match |
| `T` | Cycle vertex template |
| `t` | Pick vertex template |
| `<C-d>` | Page down |
| `<C-u>` | Page up |
| `G` | Jump to end |
| `gg` | Jump to start |
| `q` | Quit |

## License

MIT
