-- nvim-treesitter でインストールするパーサの一覧 (唯一の情報源)
-- treesitter_settings.toml (dein 経由の起動時 require) と
-- scripts/install_treesitter_parsers.lua (mise タスクの dofile) の両方から参照される。
-- Single source of truth for the parser list — required by treesitter_settings.toml
-- at startup and dofile'd by the mise task script, so the list is never duplicated.
return {
  "lua",
  "rust",
  "python",
  "fish",
  "bash",
  "typescript",
  "svelte",
  "json",
  "go",
  "dockerfile",
  "html",
  "markdown",
  "markdown_inline",
  "toml",
  "make",
  "yaml",
  "jsonnet",
  "hurl",
  "vim",
  "vimdoc",
  "query",
  "regex",
  "css",
}
