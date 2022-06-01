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

-- dein Scripts-----------------------------
local dein_dir = vim.env.HOME .. '/.cache/dein'
local dein_repo_dir = dein_dir .. '/repos/github.com/Shougo/dein.vim'
if not string.match(vim.o.runtimepath, '/dein.vim') then
  if vim.fn.isdirectory(dein_repo_dir) ~= 1 then
    os.execute('git clone https://github.com/Shougo/dein.vim '..dein_repo_dir)
  end
  vim.o.runtimepath = dein_repo_dir .. ',' .. vim.o.runtimepath 
end

if vim.call('dein#load_state', dein_dir) == 1 then
  local dein_toml_dir = vim.env.HOME .. '/dotfiles/.config/nvim'
  local dein_toml = dein_toml_dir .. '/dein.toml'
  local style_toml = dein_toml_dir .. '/style.toml'
  local dein_toml_lazy = dein_toml_dir .. '/dein_lazy.toml'

  vim.call('dein#begin', dein_dir, {vim.fn.expand('<sfile>'), dein_toml, dein_toml_lazy, style_toml})
  vim.call('dein#load_toml', dein_toml, {lazy = 0})
  vim.call('dein#load_toml', style_toml, {lazy = 0})
  vim.call('dein#load_toml', dein_toml_lazy, {lazy = 1})


  vim.call('dein#end')
  vim.call('dein#save_state')
end

vim.api.nvim_set_var('dein#auto_recache', 1)
vim.api.nvim_set_var('dein#enable_notification', 1)
-- vim.api.nvim_set_var('dein#install_github_api_token', 'github token')

--End dein Scripts-----------------------------

vim.cmd 'set relativenumber'
vim.cmd 'set t_Co=256'
vim.cmd 'set ttimeoutlen=10'
vim.cmd 'set encoding=utf-8'
vim.cmd 'set sh=fish'
vim.cmd 'set nowrap'
vim.cmd 'set number'
vim.cmd 'set title'
vim.cmd 'set autoindent'
vim.cmd 'set tabstop=2'
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
