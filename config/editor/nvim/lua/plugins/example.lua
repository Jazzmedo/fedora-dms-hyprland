-- since this is just an example spec, don't actually load anything here and return an empty spec
-- stylua: ignore
-- every spec file under the "plugins" directory will be loaded automatically by lazy.nvim
--
-- In your plugin files, you can:
-- * add extra plugins
-- * disable/enabled LazyVim plugins
return {


  -- ==========================================
  -- 1. ADD YOUR CUSTOM FORMATTER ASSIGNMENTS
  -- ==========================================
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
      -- Frontend / Web Development (Prettier handles these beautifully)
        html = { "prettier" },
        css = { "prettier" },
        javascript = { "prettier" },
        javascriptjsx = { "prettier" },
        typescript = { "prettier" },
        typescriptjsx = { "prettier" },
        -- Data Formats / Configurations
        json = { "prettier" },
        jsonc = { "prettier" }, -- JSON with comments
        yaml = { "prettier" },
        yml = { "prettier" },
        markdown = { "prettier" },

        -- Python (Black is the industry standard, ruff is an incredibly fast alternative)
        python = { "black" },

        -- Backend / Systems (Optional bonus additions)
        lua = { "stylua" },
        bash = { "shfmt" },
        sh = { "shfmt" },
        cpp = { "clang-format" },
        c = { "clang-format" },

      },
    },
  },

  {
  "nvim-neo-tree/neo-tree.nvim",
  opts = function(_, opts)
    -- 1. Move it to the right side
    opts.window = opts.window or {}
    opts.window.position = "right"

    -- 2. Force real-time updates for new files and Git changes
    opts.filesystem = opts.filesystem or {}
    opts.filesystem.use_libuv_file_watcher = true -- Watches filesystem events natively
    opts.filesystem.follow_current_file = { enabled = true } -- Keeps tree in sync with open buffer
    -- 3. Ensure Git tracking is active and updates automatically
    opts.git_status = {
      enabled = true,
      window = {
        position = "right",
      },
    }

      opts.log_level = "error"
    end,
  },

  -- ==========================================
  -- 2. TELL MASON TO AUTO-INSTALL PRETTIER
  -- ==========================================
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- Ensure our list exists so we can safely add tools to it
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "stylua",
        "shellcheck",
        "shfmt",
        "flake8",
        "prettier", -- Added prettier here so Mason installs it cleanly
      })
    end,
  },
  {
    "okuuva/auto-save.nvim",
    version = "^1.0.0",
    cmd = "ASToggle",
    event = { "InsertLeave", "TextChanged" },
    keys = {
      -- Shortcut to manually toggle auto-save on/off completely
      { "<leader>un", "<cmd>ASToggle<CR>", desc = "Toggle Auto-Save" },
    },
    opts = {
      enabled = true,
      trigger_events = {
        immediate_save = { "BufLeave", "FocusLost", "QuitPre", "VimSuspend" },
        defer_save = { "InsertLeave", "TextChanged" },
        cancel_deferred_save = { "InsertEnter" },
      },
      -- Custom condition to prevent annoying errors in system buffers
      condition = function(buf)
        local filetype = vim.fn.getbufvar(buf, "&filetype")
        -- Don't auto-save inside neo-tree, lazygit, or floating prompts
        local excluded_filetypes = { "neo-tree", "lazygit", "TelescopePrompt", "harpoon" }
        
        if vim.tbl_contains(excluded_filetypes, filetype) then
          return false
        end
        
        -- Don't save special or unmodifiable buffers
        if vim.fn.getbufvar(buf, "&buftype") ~= "" or vim.fn.getbufvar(buf, "&modifiable") ~= 1 then
          return false
        end
        return true
      end,
      debounce_delay = 1000, -- Delay in milliseconds before saving after you stop typing
    },
    config = function(_, opts)
      local autosave = require("auto-save")
      autosave.setup(opts)

      -- Register beautifully with LazyVim's Snacks toggle system!
      -- You can switch it off/on now using your UI options toggles
      if pcall(require, "snacks") then
        require("snacks.toggle").new({
          name = "Auto Save",
          get = function()
            return autosave.enabled()
          end,
          set = function(state)
            if state then
              autosave.on()
            else
              autosave.off()
            end
          end,
        }):map("<leader>uv") -- Maps it right into LazyVim's standard toggle prefix (<leader>u)
      end
    end,
  },
  {
    "folke/snacks.nvim",
    opts = {
      -- Ensure terminal features are enabled in Snacks
      terminal = { enabled = true },
    },
    keys = {
      {
        "<leader>kd", -- You can change this to any keybind you prefer (e.g., <leader>ld)
        function()
          Snacks.terminal("lazydocker", {
            win = {
              width = 0.8,
              height = 0.8,
              border = "rounded",
            },
          })
        end,
        desc = "LazyDocker",
      },
    },
  },
  -- 1. Transparently open/save .ipynb files as markdown
  {
    "GCBallesteros/jupytext.vim",
    lazy = false,
    config = function()
      vim.g.jupytext_fmt = "markdown"
    end,
  },

  -- 2. The Jupyter kernel client for running code cells
  {
    "benlubas/molten-nvim",
    version = "^1.0.0", -- use version tags for stability
    dependencies = { "3rd/image.nvim" },
    init = function()
      -- These must be set before molten loads
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_output_win_max_height = 20
    end,
  }
}
