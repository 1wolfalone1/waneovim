-- since this is just an example spec, don't actually load anything here and return an empty spec
-- stylua: ignore
if true then return {} end

-- every spec file under the "plugins" directory will be loaded automatically by lazy.nvim
--
-- In your plugin files, you can:
-- * add extra plugins
-- * disable/enabled LazyVim plugins
-- * override the configuration of LazyVim plugins
return {
  -- add gruvbox
  { "ellisonleao/gruvbox.nvim" },
  -- Configure LazyVim to load gruvbox
  -- change trouble config
  {
    "folke/trouble.nvim",
    -- opts will be merged with the parent spec
    opts = { use_diagnostic_signs = true },
  },

  -- disable trouble
  { "folke/trouble.nvim", enabled = false },
  -- override nvim-cmp and add cmp-emoji
  {
    "nvim-telescope/telescope.nvim",
    keys = {
      -- add a keymap to browse plugin files
      -- stylua: ignore
      {
        "<leader>fp",
        function() require("telescope.builtin").find_files({ cwd = require("lazy.core.config").options.root }) end,
        desc = "Find Plugin File",
      },
    },
    -- change some options
    opts = {
      defaults = {
        layout_strategy = "horizontal",
        layout_config = { prompt_position = "top" },
        sorting_strategy = "ascending",
        winblend = 0,
      },
    },
  },

  -- add pyright to lspconfig
  {
    "mfussenegger/nvim-dap",
    config = function() end,
  },
  -- add tsserver and setup with typescript.nvim instead of lspconfig
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "jose-elias-alvarez/typescript.nvim",
      init = function()
        require("lazyvim.util").lsp.on_attach(function(_, buffer)
          -- stylua: ignore
          vim.keymap.set( "n", "<leader>co", "TypescriptOrganizeImports", { buffer = buffer, desc = "Organize Imports" })
          vim.keymap.set("n", "<leader>cR", "TypescriptRenameFile", { desc = "Rename File", buffer = buffer })
        end)
      end,
    },
    ---@class PluginLspOpts
    opts = {
      ---@type lspconfig.options
      servers = {
        -- tsserver will be automatically installed with mason and loaded with lspconfig
        tsserver = {},
        jdtls = {},
      },
      inlay_hints = { enabled = false },
      -- you can do any additional lsp server setup here
      -- return true if you don't want this server to be setup with lspconfig
      ---@type table<string, fun(server:string, opts:_.lspconfig.options):boolean?>
      setup = {
        -- example to setup with typescript.nvim
        tsserver = function(_, opts)
          require("typescript").setup({ server = opts })
          return true
        end,
        jdtls = function()
          return true -- avoid duplicate servers
        end,
        -- Specify * to use this function as a fallback for any server
        -- ["*"] = function(server, opts) end,
      },
    },
    -- config = function()
    --   local capabilities = require("cmp_nvim_lsp").default_capabilities()
    --   local lspconfig = require("lspconfig")
    --   -- lua
    --   lspconfig.lua_ls.setup({
    --     capabilities = capabilities,
    --     settings = {
    --       Lua = {
    --         diagnostics = {
    --           globals = { "vim" },
    --         },
    --         workspace = {
    --           library = vim.api.nvim_get_runtime_file("", true),
    --           checkThirdParty = false,
    --         },
    --         telemetry = {
    --           enable = false,
    --         },
    --       },
    --     },
    --   })
    --   -- typescript
    --   lspconfig.ts_ls.setup({
    --     capabilities = capabilities,
    --   })
    --   -- Js
    --   lspconfig.eslint.setup({
    --     capabilities = capabilities,
    --   })
    --   -- zig
    --   -- lspconfig.zls.setup({
    --   --   capabilities = capabilities,
    --   -- })
    --   -- yaml
    --   -- lspconfig.yamlls.setup({
    --   --   capabilities = capabilities,
    --   -- })
    --   -- tailwindcss
    --   -- lspconfig.tailwindcss.setup({
    --   --   capabilities = capabilities,
    --   -- })
    --   -- golang
    --   lspconfig.gopls.setup({
    --     capabilities = capabilities,
    --   })
    --   lspconfig.pyright.setup({ capabilities = capabilities })
    --   --java
    --   lspconfig.jdtls.setup({
    --     settings = {
    --       java = {
    --         configuration = {
    --           runtimes = {
    --             {
    --               name = "JavaSE-17",
    --               path = "/usr/lib/jvm/java-17-openjdk-amd64",
    --               default = true,
    --             },
    --           },
    --         },
    --       },
    --     },
    --   })
    --   -- nix
    --   -- lspconfig.rnix.setup({ capabilities = capabilities })
    --   -- lsp kepmap setting
    --   vim.keymap.set("n", "K", vim.lsp.buf.hover, {})
    --   vim.keymap.set("n", "gi", vim.lsp.buf.implementation, {})
    --   vim.keymap.set("n", "gd", vim.lsp.buf.definition, {})
    --   vim.keymap.set("n", "gD", vim.lsp.buf.declaration, {})
    --   vim.keymap.set("n", "gr", vim.lsp.buf.references, {})
    --   vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, {})
    --   vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, {})
    --   -- list all methods in a file
    --   -- working with go confirmed, don't know about other, keep changing as necessary
    --   vim.keymap.set("n", "<leader>fm", function()
    --     local filetype = vim.bo.filetype
    --     local symbols_map = {
    --       python = "function",
    --       javascript = "function",
    --       typescript = "function",
    --       java = "class",
    --       lua = "function",
    --       go = { "method", "struct", "interface" },
    --     }
    --     local symbols = symbols_map[filetype] or "function"
    --     require("telescope.builtin").lsp_document_symbols({ symbols = symbols })
    --   end, {})
    -- end,
  },

  -- for typescript, LazyVim also includes extra specs to properly setup lspconfig,
  -- treesitter, mason and typescript.nvim. So instead of the above, you can use:
  { import = "lazyvim.plugins.extras.lang.typescript" },

  -- add more treesitter parsers
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "bash",
        "html",
        "javascript",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "python",
        "query",
        "regex",
        "tsx",
        "typescript",
        "vim",
        "yaml",
        "go",
        "java",
      },
    },
  },

  -- since `vim.tbl_deep_extend`, can only merge tables and not lists, the code above
  -- would overwrite `ensure_installed` with the new value.
  -- If you'd rather extend the default config, use the code below instead:
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- add tsx and treesitter
      vim.list_extend(opts.ensure_installed, {
        "tsx",
        "typescript",
      })
    end,
  },

  -- the opts function can also be used to change the default opts:
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, {
        function()
          return "😄"
        end,
      })
    end,
  },

  -- or you can return new options to override all the defaults
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function()
      return {
        --[[add your custom lualine config here]]
      }
    end,
  },

  -- use mini.starter instead of alpha
  { import = "lazyvim.plugins.extras.ui.mini-starter" },

  -- add jsonls and schemastore packages, and setup treesitter for json, json5 and jsonc
  { import = "lazyvim.plugins.extras.lang.json" },

  -- add any tools you want to have installed below
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "stylua",
        "shellcheck",
        "shfmt",
        "flake8",
      },
    },
  },
}
