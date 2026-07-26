-- lua_add {{{
-- noice.nvimの設定
require("noice").setup({
  cmdline = {
    enabled = true,
    view = "cmdline_popup",
    format = {
      -- 日本語で
      -- conceal: (default=true) cmdlineの中でパターンにマッチするテキストを隠します。
      -- view： (デフォルトはcmdlineビュー)
      -- opts: ビューに渡されるオプション
      -- icon_hl_group: アイコンのhl_groupを指定する。
      -- title: 空文字列か何かに設定する。
      cmdline = { pattern = "^:", icon = "", lang = "vim" },
      search_down = { kind = "search", pattern = "^/", icon = " ", lang = "regex" },
      search_up = { kind = "search", pattern = "^%?", icon = " ", lang = "regex" },
      filter = { pattern = "^:%s*!", icon = "$", lang = "bash" },
      lua = { pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" }, icon = "", lang = "lua" },
      help = { pattern = "^:%s*he?l?p?%s+", icon = "" },
      input = { view = "cmdline_input", icon = "󰥻 " }, -- Used by input()
      -- lua = false, -- to disable a format, set to `false`
    },
    position = {
      row = math.floor(vim.opt.lines:get() * 0.95), -- 画面最下部近くに配置
      col = "50%",
    },
    opts = {
      size = {
        width = "60%",
        height = "auto",
      },
      border = {
        style = "rounded",
        padding = { 0, 1 },
      },
      win_options = {
        winhighlight = {
          Normal = "NoiceCmdline",
          IncSearch = "",
          Search = "",
        },
      },
      position = {
        row = "95%",
        col = "50%",
      },
    },
  },
  messages = {
    enabled = true,
    view = "notify",
    view_error = "notify",
    view_warn = "notify",
    view_history = "messages",
    view_search = false,  -- 検索カウンターを無効化（dduの表示と競合を避けるため）
  },
  views = {
    cmdline_popup = {
      border = {
        style = "rounded",
      },
    },
    mini = {
      position = {
        row = -2,  -- 下から2行目
        col = "100%", -- 右端
      },
      size = {
        width = "auto",
        height = "auto",
      },
      border = {
        style = "none",
      },
    },
  },
  routes = {
    -- dduのフィルター入力中はメッセージを表示しない
    {
      filter = {
        event = "msg_show",
        find = "^%d+ lines yanked$",
      },
      opts = { skip = true },
    },
    {
      filter = {
        event = "msg_show",
        kind = "",
        cond = function()
          -- dduのフィルターウィンドウがアクティブな場合はスキップ
          return vim.fn.win_gettype() == "popup"
        end,
      },
      opts = { skip = true },
    },
  },
  -- LSP関連の設定
  lsp = {
    progress = {
      enabled = true,
      view = "mini",
    },
    override = {
      ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
      ["vim.lsp.util.stylize_markdown"] = true,
    },
    hover = {
      enabled = true,
      view = "hover",

    },
    signature = {
      enabled = true,
      view = "hover",
      opts = {
        size = {
          max_width = 80,
          max_height = 20,
        },

      },
    },
  },
  presets = {
    bottom_search = false,
    command_palette = false,
    long_message_to_split = true,
    lsp_doc_border = true,
  },
})

-- ハイライトの設定
vim.api.nvim_set_hl(0, "NoiceCmdline", { link = "Normal" })
vim.api.nvim_set_hl(0, "NoiceCmdlinePopup", { link = "Normal" })
vim.api.nvim_set_hl(0, "NoiceCmdlinePrompt", { link = "Statement" })
-- }}}
