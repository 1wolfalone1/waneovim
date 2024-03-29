


vim.g.transparent_groups = vim.list_extend(vim.g.transparent_groups or {}, {
  extra_groups = {
    "NormalFloat", -- plugins which have float panel such as Lazy, Mason, LspInfo
    "NvimTreeNormal" -- NvimTree
  },
})
-- vimscript: let g:transparent_groups = extend(get(g:, 'transparent_groups', []), ["ExtraGroup"])
return require("transparent").setup({ -- Optional, you don't have to run setup.
  groups = { -- table: default groups
    'Normal', 'NormalNC', 'Comment', 'Constant', 'Special', 'Identifier',
    'Statement', 'PreProc', 'Type', 'Underlined', 'Todo', 'String', 'Function',
    'Conditional', 'Repeat', 'Operator', 'Structure', 'LineNr', 'NonText',
    'SignColumn', 'CursorLineNr', 'StatusLine', 'StatusLineNC',
    'EndOfBuffer',
  },
  extra_groups = {
    "NormalFloat", -- plugins which have float panel such as Lazy, Mason, LspInfo
    "NvimTreeNormal", -- NvimTree
    "Completion",
    "Cmp",
  }, -- table: additional groups that should be cleared
  exclude_groups = {
    "CursorLine"
  }, -- table: groups you don't want to clear
})

