--                                           o8o                     .o8                           o8o               .ooooo.    .ooooo.   o8o          
--                                           `"'                    "888                           `"'              d88'   `8. d88'   `8. `YP          
--   ooo. .oo.  .oo.   oooo  oooo   .oooo.o oooo   .ooooo.           888oooo.  oooo d8b  .oooo.   oooo  ooo. .oo.   Y88..  .8' Y88..  .8'  '   .oooo.o 
--   `888P"Y88bP"Y88b  `888  `888  d88(  "8 `888  d88' `"Y8          d88' `88b `888""8P `P  )88b  `888  `888P"Y88b   `88888b.   `88888b.      d88(  "8 
--    888   888   888   888   888  `"Y88b.   888  888       8888888  888   888  888      .oP"888   888   888   888  .8'  ``88b .8'  ``88b     `"Y88b.  
--    888   888   888   888   888  o.  )88b  888  888   .o8          888   888  888     d8(  888   888   888   888  `8.   .88P `8.   .88P     o.  )88b 
--   o888o o888o o888o  `V88V"V8P' 8""888P' o888o `Y8bod8P'          `Y8bod8P' d888b    `Y888""8o o888o o888o o888o  `boood8'   `boood8'      8""888P' 
--                                                                                                                                                     
--                                                                                                                                                     
--                                                                                                                                                     
--                o8o                                                          .o88o.  o8o                                                             
--                `"'                                                          888 `"  `"'                                                             
--   oooo    ooo oooo  ooo. .oo.  .oo.         .ooooo.   .ooooo.  ooo. .oo.   o888oo  oooo   .oooooooo                                                 
--    `88.  .8'  `888  `888P"Y88bP"Y88b       d88' `"Y8 d88' `88b `888P"Y88b   888    `888  888' `88b                                                  
--     `88..8'    888   888   888   888       888       888   888  888   888   888     888  888   888                                                  
--      `888'     888   888   888   888       888   .o8 888   888  888   888   888     888  `88bod8P'                                                  
--       `8'     o888o o888o o888o o888o      `Y8bod8P' `Y8bod8P' o888o o888o o888o   o888o `8oooooo.                                                  
--                                                                                          d"     YD                                                  
--                                                                                          "Y88888P'                                                  
--

-- dpp Scripts-----------------------------
-- dpp.vim (dein.vimの後継, #445/#472) の store パスは PR-1(#476)で Nix (home.sessionVariables)
-- から環境変数として供給される。dein時代のようなgit clone/mtime依存のbootstrapは行わない。
-- 罠: シェルが __HM_SESS_VARS_SOURCED を継承していると新しい環境変数が入らない場合がある。
--     その場合は再ログイン(またはシェル再起動)して hm-session-vars.sh を再読み込みすること。
-- NOTE: dpp.vim (dein.vim's successor, #445/#472) store paths are supplied as env vars
--       from Nix (home.sessionVariables) in PR-1 (#476). Unlike dein, there is no
--       git-clone/mtime-dependent bootstrap here.
-- TRAP: if the shell inherited __HM_SESS_VARS_SOURCED, new env vars may not be picked up.
--       Re-login (or restart the shell) to re-source hm-session-vars.sh if this fails.
local function dpp_env(name)
  local value = vim.env[name]
  if value == nil or value == '' then
    return nil
  end
  return value
end

local dpp_vim = dpp_env('NVIM_DPP_VIM')
local denops_vim = dpp_env('NVIM_DENOPS_VIM')
local dpp_ext_installer = dpp_env('NVIM_DPP_EXT_INSTALLER')
local dpp_ext_lazy = dpp_env('NVIM_DPP_EXT_LAZY')
local dpp_ext_toml = dpp_env('NVIM_DPP_EXT_TOML')
local dpp_protocol_git = dpp_env('NVIM_DPP_PROTOCOL_GIT')

if not (dpp_vim and denops_vim and dpp_ext_installer
    and dpp_ext_lazy and dpp_ext_toml and dpp_protocol_git) then
  vim.api.nvim_err_writeln(
    'dpp.vim: NVIM_DPP_*/NVIM_DENOPS_VIM environment variables are not set. '
      .. 'Re-login (or open a new shell) so home-manager session variables '
      .. 'are re-sourced, then restart Neovim. Starting with no plugins.'
  )
else
  -- NOTE: dpp#min#load_state() snapshots the *current* 'runtimepath' into
  -- g:dpp._init_runtimepath the first time it is called, and dpp#make_state()
  -- persists that snapshot (not the live rtp) into the generated startup.vim.
  -- So every store path we want available on *every* future session (not
  -- just this bootstrap run) must be prepended before the first
  -- dpp#min#load_state() call below — adding them only in the "state missing"
  -- branch would bake a denops-less runtimepath into state on first install
  -- and break DenopsReady on every subsequent normal startup.
  -- 注: dpp#min#load_state() は初回呼び出し時点の'runtimepath'をそのまま
  -- g:dpp._init_runtimepathへ記録し、dpp#make_state()はその(live rtpではなく)
  -- スナップショットをstartup.vimへ焼き込む。そのため今後の全セッションで
  -- 必要なstoreパスは、下のdpp#min#load_state()呼び出しより前に追加しないと、
  -- 初回install時にdenops抜きのruntimepathがstateに焼き込まれ、以後の通常
  -- 起動でDenopsReadyが発火しなくなる。
  vim.opt.runtimepath:prepend(dpp_vim)
  vim.opt.runtimepath:prepend(denops_vim)
  vim.opt.runtimepath:prepend(dpp_ext_installer)
  vim.opt.runtimepath:prepend(dpp_ext_lazy)
  vim.opt.runtimepath:prepend(dpp_ext_toml)
  vim.opt.runtimepath:prepend(dpp_protocol_git)

  local dpp_base = vim.env.HOME .. '/.cache/dpp'
  local dpp_config_path = vim.fn.stdpath('config') .. '/dpp/config.ts'

  if vim.fn['dpp#min#load_state'](dpp_base) ~= 0 then
    -- state未生成(初回起動 or state破棄後): denops起動後にmake_state()で
    -- state(startup.vim/state.vim)を生成する。
    vim.api.nvim_create_autocmd('User', {
      pattern = 'DenopsReady',
      once = true,
      callback = function()
        vim.fn['dpp#make_state'](dpp_base, dpp_config_path)
      end,
    })
  end

  vim.api.nvim_create_autocmd('User', {
    pattern = 'Dpp:makeStatePost',
    callback = function()
      vim.notify('dpp#make_state() done. Restart Neovim to load plugins.')
    end,
  })

  -- TOML/config.ts編集時にstateを自動再生成する(check_files)
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = { '*.toml', '*.lua', '*.vim', '*.ts' },
    callback = function()
      if #vim.fn['dpp#check_files']() > 0 then
        vim.fn['dpp#make_state']()
      end
    end,
  })
end
--End dpp Scripts-----------------------------


vim.o.termguicolors = true
vim.bo.autoread = true
vim.bo.tabstop = 2
vim.bo.expandtab = true

-- copilot init
vim.g.copilot_no_tab_maps = true

vim.cmd 'set clipboard+=unnamedplus'
vim.cmd 'set relativenumber'
vim.cmd 'set t_Co=256'
vim.cmd 'set ttimeoutlen=10'
vim.cmd 'set encoding=utf-8'
vim.cmd 'set sh=fish'
vim.cmd 'set nowrap'
vim.cmd 'set number'
vim.cmd 'set title'
vim.cmd 'set autoindent'
vim.cmd 'set list'
vim.cmd 'set shiftwidth=2'
vim.cmd 'set expandtab'
vim.cmd 'set ignorecase'
vim.cmd 'set smartcase'
vim.cmd 'set wrapscan'
vim.cmd 'set spell'
vim.cmd 'set spelllang=en,cjk'
vim.cmd 'set noswapfile'

-- vim.cmd 'set listchars=tab:»-,trail:-,eol:↲,extends:»,precedes:«,nbsp:%,space:␣'


-- vim.api.nvim_set_keymap('c', '<C-A>', '<HOME>' , {})
-- :cnoremap <C-F> <Right>
-- vim.api.nvim_set_keymap('c', '<C-F>', '<Right>', {})
-- :cnoremap <C-B> <Left>
-- vim.api.nvim_set_keymap('c', '<C-B>', '<Left>', {})

-- buffer
vim.api.nvim_set_keymap('n', '<C-j>', '<Cmd> bprev <CR>' , {})
vim.api.nvim_set_keymap('n', '<C-k>', '<Cmd> bnext <CR>', {})

-- tabline
vim.api.nvim_set_keymap('n', 'tc', '<Cmd> tabnew <CR>', {})
vim.api.nvim_set_keymap('n', 'tx', '<Cmd> tabclose <CR>', {})
vim.api.nvim_set_keymap('n', 'tn', '<Cmd> tabnext <CR>', {})
vim.api.nvim_set_keymap('n', 'tp', '<Cmd> tabprevious <CR>', {})
