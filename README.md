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
  opts = {
    -- All options are optional. Shown below are the defaults.
    -- bytes_per_line = 24,
    -- max_undo = 200,
    -- max_memory_file = 64 * 1024 * 1024,
    -- colors = {
    --   bg           = "#1a1b26",
    --   info_bg      = "#1a1b26",
    --   border       = "#115e72",
    --   addr         = "#565f89",
    --   hex          = "#c0caf5",
    --   ascii        = "#9ece6a",
    --   null         = "#3b4261",
    --   cursor_bg    = "#28344a",
    --   cursor_line_bg = "#1e2030",
    --   float        = "#ff9e64",
    --   int          = "#bb9af7",
    --   uint         = "#7dcfff",
    --   title        = "#7aa2f7",
    --   search       = "#f7768e",
    --   modified     = "#f7768e",
    --   selection_bg = "#2d4f67",
    -- },
  },
}
```

### packer.nvim

```lua
use {
  "Punity122333/hexinspector.nvim",
  config = function()
    require("hexinspector").setup({
      -- colors = { bg = "#282828", hex = "#ebdbb2" },
    })
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
