local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
-- calculate workspace dir
local workspace_dir = vim.fn.stdpath "data" .. "/site/java/workspace-root/" .. project_name
-- get the mason install path
local install_path = require("mason-registry").get_package("jdtls"):get_install_path()
-- get the debug adapter install path
local debug_install_path = require("mason-registry").get_package("java-debug-adapter"):get_install_path()
local lombok_path = install_path .. '/lombok.jar'
local path_to_lsp_server = install_path .. "/config_linux"
local bundles = {
  vim.fn.glob(debug_install_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar", 1),
}
local on_attach = function(client, bufnr)
  local border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
  local bufopts = { noremap = true, silent = true, buffer = bufnr }
  local opts = { noremap = true, silent = true }
  vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
  vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
  vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
end


local capabilities = vim.lsp.protocol.make_client_capabilities()

local config = {
  cmd = {
    install_path .. "/bin/jdtls",
    "-Declipse.application=org.eclipse.jdt.ls.core.id1",
    "-Dosgi.bundles.defaultStartLevel=4",
    "-Declipse.product=org.eclipse.jdt.ls.core.product",
    "-Dlog.protocol=true",
    "-Dlog.level=ALL",
    "-Xms1g",
    "--jvm-arg=-javaagent:" .. "/d/clone/lombok.jar",
    -- "-Xbootclasspath/a:" .. lombok_path,
    "-jar",
    vim.fn.glob(install_path .. "/plugins/org.eclipse.equinox.launcher_*.jar"),
    "--add-modules=ALL-SYSTEM",
    "--add-opens",
    "java.base/java.util=ALL-UNNAMED",
    "--add-opens",
    "java.base/java.lang=ALL-UNNAMED",
    '-configuration', path_to_lsp_server,
    "-data",
    workspace_dir,
  },
  root_dir = require('jdtls.setup').find_root({ '.git', 'mvnw', 'gradlew', 'pom.xml', 'build.gradle' }),
  capabilities = capabilities,
  settings = {
    java = {
      eclipse = {
        downloadSources = true,
      },
      configuration = {
        updateBuildConfiguration = "interactive",
      },
      maven = {
        downloadSources = true,
        updateSnapshots = true,
      },
    },
  },
  on_attach = on_attach,
  init_options = {
    bundles = bundles,
  },
}
require("jdtls").start_or_attach(config)
