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

  -- dpp_base/repos配下にクローン済みプラグインが1つもない状態を検知する。
  -- 初回起動(bootstrap直後)だけでなく、repos/を手動やキャッシュ掃除などで
  -- out-of-bandに消してしまったケースも同じ条件で拾える。
  -- Detects "no cloned plugins under dpp_base/repos yet" — covers both the
  -- initial bootstrap and repos/ having been wiped out of band (e.g. manual
  -- cache cleanup), not just first launch.
  local function dpp_repos_missing()
    return vim.fn.isdirectory(dpp_base .. '/repos') == 0
      or #vim.fn.glob(dpp_base .. '/repos/*', 0, 1) == 0
  end

  -- dpp#async_ext_action() はdenops経由で動くため、denops未起動時に呼ぶと
  -- 失敗する。:DppInstall/:DppUpdate/自動インストールの全呼び出し口はここを通す。
  -- dpp#async_ext_action() talks to denops; calling it before denops is up
  -- fails. Every entry point below (:DppInstall/:DppUpdate/auto-install)
  -- routes through this guard.
  local function dpp_run_installer(action, params)
    if vim.fn['denops#server#status']() ~= 'running' then
      vim.notify(
        'dpp: denops server is not running yet. '
          .. 'Wait for it to finish starting (see DenopsReady) and retry.',
        vim.log.levels.WARN
      )
      return
    end
    vim.fn['dpp#async_ext_action']('installer', action, params or {})
  end

  -- 自動インストールをトリガーしたかどうかを覚えておき、その場合だけ
  -- installer完了時に「再起動してね」通知を出す(手動:DppUpdateの度に
  -- 出るのは煩わしいため)。
  -- Remembers whether *this* run triggered the auto-install, so the
  -- "restart Neovim" notice only fires for that path — not on every manual
  -- :DppUpdate.
  local dpp_auto_install_pending = false

  local function dpp_auto_install_if_missing()
    if not dpp_repos_missing() then
      return
    end
    dpp_auto_install_pending = true
    vim.notify(
      'dpp: no plugins found under repos/. Auto-installing (this may take a while)...',
      vim.log.levels.INFO
    )
    dpp_run_installer('install', {})
  end

  vim.api.nvim_create_user_command('DppInstall', function()
    dpp_run_installer('install', {})
  end, { desc = 'Install missing dpp plugins (dpp-ext-installer#install)' })

  vim.api.nvim_create_user_command('DppUpdate', function(opts)
    -- NOTE (Decision Log D2): base-layer plugins (denops/ddc/ddu core, UI
    -- layer) are rev-pinned in TOML; bump them via an intentional rev-bump
    -- PR, not this command. dpp-protocol-git re-checks-out `rev`-pinned
    -- plugins after update, so an unqualified :DppUpdate does not move
    -- them in practice — but this command must not become the mechanism
    -- used to bump base-layer revs.
    -- 注(Decision Log D2): 基盤層(denops/ddc/ddu本体・UI層)はTOMLでrev固定
    -- されており、更新は意図的なrev bump PR経由が原則。dpp-protocol-gitは
    -- update後もrev固定プラグインを当該revへ再チェックアウトするため無条件
    -- 実行してもrevは動かないが、本コマンドを基盤層更新の手段として使わないこと。
    local params = {}
    if #opts.fargs > 0 then
      params.names = opts.fargs
    end
    dpp_run_installer('update', params)
  end, { nargs = '*', desc = 'Update dpp plugins (all, or the given plugin names)' })

  if vim.fn['dpp#min#load_state'](dpp_base) ~= 0 then
    -- state未生成(初回起動 or state破棄後): denops起動後にmake_state()で
    -- state(startup.vim/state.vim)を生成する。make_state成功後もrepos/が
    -- 空なことがある(#479実害)ため、Dpp:makeStatePost側で欠損チェックする。
    vim.api.nvim_create_autocmd('User', {
      pattern = 'DenopsReady',
      once = true,
      callback = function()
        vim.fn['dpp#make_state'](dpp_base, dpp_config_path)
      end,
    })
  else
    -- state生成済み(通常起動): make_state()は走らずDpp:makeStatePostも
    -- 発火しないため、repos/欠損はここでdenops起動後に一度だけチェックする。
    vim.api.nvim_create_autocmd('User', {
      pattern = 'DenopsReady',
      once = true,
      callback = dpp_auto_install_if_missing,
    })
  end

  vim.api.nvim_create_autocmd('User', {
    pattern = 'Dpp:makeStatePost',
    callback = function()
      vim.notify('dpp#make_state() done. Restart Neovim to load plugins.')
      dpp_auto_install_if_missing()
    end,
  })

  -- installer install/updateの完了通知(Dpp:ext:installer:updateDone)。
  -- 自動インストールをトリガーした時だけ再起動を促す。
  vim.api.nvim_create_autocmd('User', {
    pattern = 'Dpp:ext:installer:updateDone',
    callback = function()
      if dpp_auto_install_pending then
        dpp_auto_install_pending = false
        vim.notify(
          'dpp: initial plugin install finished. Restart Neovim to load them.',
          vim.log.levels.INFO
        )
      end
    end,
  })

  -- TOML/config.ts編集時にstateを自動再生成する(check_files)
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = { '*.toml', '*.lua', '*.vim', '*.ts' },
    callback = function()
      if #vim.fn['dpp#check_files']() > 0 then
        -- Pass the same explicit args as the initial DenopsReady make_state —
        -- argless make_state depends on dpp defaults and may target the wrong
        -- base/config. 初回生成時と同じ引数を明示して同一のstateを再生成する。
        vim.fn['dpp#make_state'](dpp_base, dpp_config_path)
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
