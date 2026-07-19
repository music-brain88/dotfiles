-- mise run nvim:ts-install から headless nvim (-u ~/.config/nvim/init.lua -l このファイル) で実行される。
-- ~/.config/nvim は home-manager 経由でNix storeへ個別シンボリックリンクされるため、worktree の
-- lua/treesitter_parsers.lua を即座に(マージ前でも)反映するには require ではなく cwd 相対の dofile を使う。
-- Invoked headless via `mise run nvim:ts-install`. ~/.config/nvim symlinks per-file into the Nix
-- store, so `require()` would not see worktree edits until nix:switch — dofile a repo-relative path instead.
local repo_root = arg[1]
if not repo_root then
  io.stderr:write("usage: nvim --headless -u ~/.config/nvim/init.lua -l install_treesitter_parsers.lua -- <repo_root>\n")
  os.exit(1)
end

local parsers = dofile(repo_root .. '/.config/nvim/lua/treesitter_parsers.lua')

local ts = require('nvim-treesitter')
ts.setup {}

local install_ok, install_err = pcall(function()
  ts.install(parsers, { summary = false }):wait(300000)
end)

-- インストール済みパーサは install() がスキップするだけで報告してくれないため、
-- .so の有無を自前でチェックして成功/失敗を出力する (silent skip 禁止)
-- install() silently skips already-installed parsers without reporting them,
-- so check for each .so directly and print an explicit success/failure summary.
local parser_dir = vim.fn.stdpath('data') .. '/site/parser'
local succeeded, failed = {}, {}
for _, name in ipairs(parsers) do
  if vim.fn.filereadable(parser_dir .. '/' .. name .. '.so') == 1 then
    table.insert(succeeded, name)
  else
    table.insert(failed, name)
  end
end

print('=== treesitter parser install result ===')
print(string.format('succeeded (%d): %s', #succeeded, table.concat(succeeded, ', ')))
if #failed > 0 then
  print(string.format('FAILED (%d): %s', #failed, table.concat(failed, ', ')))
end
if not install_ok then
  print('install() raised an error: ' .. tostring(install_err))
end

if #failed > 0 or not install_ok then
  os.exit(1)
end
