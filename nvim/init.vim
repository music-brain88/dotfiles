"                                           o8o                     .o8                           o8o               .ooooo.    .ooooo.   o8o          
"                                           `"'                    "888                           `"'              d88'   `8. d88'   `8. `YP          
"   ooo. .oo.  .oo.   oooo  oooo   .oooo.o oooo   .ooooo.           888oooo.  oooo d8b  .oooo.   oooo  ooo. .oo.   Y88..  .8' Y88..  .8'  '   .oooo.o 
"   `888P"Y88bP"Y88b  `888  `888  d88(  "8 `888  d88' `"Y8          d88' `88b `888""8P `P  )88b  `888  `888P"Y88b   `88888b.   `88888b.      d88(  "8 
"    888   888   888   888   888  `"Y88b.   888  888       8888888  888   888  888      .oP"888   888   888   888  .8'  ``88b .8'  ``88b     `"Y88b.  
"    888   888   888   888   888  o.  )88b  888  888   .o8          888   888  888     d8(  888   888   888   888  `8.   .88P `8.   .88P     o.  )88b 
"   o888o o888o o888o  `V88V"V8P' 8""888P' o888o `Y8bod8P'          `Y8bod8P' d888b    `Y888""8o o888o o888o o888o  `boood8'   `boood8'      8""888P' 
"                                                                                                                                                     
"                                                                                                                                                     
"                                                                                                                                                     
"                o8o                                                          .o88o.  o8o                                                             
"                `"'                                                          888 `"  `"'                                                             
"   oooo    ooo oooo  ooo. .oo.  .oo.         .ooooo.   .ooooo.  ooo. .oo.   o888oo  oooo   .oooooooo                                                 
"    `88.  .8'  `888  `888P"Y88bP"Y88b       d88' `"Y8 d88' `88b `888P"Y88b   888    `888  888' `88b                                                  
"     `88..8'    888   888   888   888       888       888   888  888   888   888     888  888   888                                                  
"      `888'     888   888   888   888       888   .o8 888   888  888   888   888     888  `88bod8P'                                                  
"       `8'     o888o o888o o888o o888o      `Y8bod8P' `Y8bod8P' o888o o888o o888o   o888o `8oooooo.                                                  
"                                                                                          d"     YD                                                  
"                                                                                          "Y88888P'                                                  
"

set ttimeoutlen=10

set encoding=utf-8
scriptencoding utf-8
set ambiwidth=double

set nowrap
set number
set title
set autoindent
set tabstop=2
set shiftwidth=2
set expandtab
set ignorecase
set smartcase
set wrapscan
set spell
set spelllang=en,cjk
set noswapfile

"clip board
set clipboard=unnamedplus
set background=dark


"dein Scripts-----------------------------
if &compatible
  set nocompatible               " Be iMproved
endif

" Required:
set runtimepath+=/home/arch/.cache/dein/repos/github.com/Shougo/dein.vim

" Required:
if dein#load_state('/home/arch/.cache/dein')
  call dein#begin('/home/arch/.cache/dein')

  " Let dein manage dein
  " Required:
  call dein#add('/home/arch/.cache/dein/repos/github.com/Shougo/dein.vim')
  call dein#add('neoclide/coc.nvim', {'merge':0, 'rev': 'release'})

  " Add or remove your plugins here like this:
  "call dein#add('Shougo/neosnippet.vim')
  "call dein#add('Shougo/neosnippet-snippets')
  let s:toml = '~/dotfiles/nvim/dein.toml'
  let s:lazy_toml = '~/dotfiles/nvim/dein_lazy.toml'
  call dein#load_toml(s:toml, {'lazy': 0})
  call dein#load_toml(s:lazy_toml, {'lazy': 1})


  " Required:
  call dein#end()
  call dein#save_state()
endif

" Required:
filetype plugin indent on
syntax enable

" If you want to install not installed plugins on startup.
"if dein#check_install()
"  call dein#install()
"endif

"End dein Scripts-------------------------
"-----------------------------------------------------------------------
"terminal setting
"-----------------------------------------------------------------------
tnoremap <silent> <ESC> <C-\><C-n>
nnoremap @t :tabe<CR>:terminal<CR>
" NERDtree setting
"
" NERDTress File highlighting
function! NERDTreeHighlightFile(extension, fg, bg, guifg, guibg)
 exec 'autocmd filetype nerdtree highlight ' . a:extension .' ctermbg='. a:bg .' ctermfg='. a:fg .' guibg='. a:guibg .' guifg='. a:guifg
 exec 'autocmd filetype nerdtree syn match ' . a:extension .' #^\s\+.*'. a:extension .'$#'
endfunction
call NERDTreeHighlightFile('py',     'yellow',  'none', 'yellow',  'none')
call NERDTreeHighlightFile('md',     'blue',    'none', '#3366FF', 'none')
call NERDTreeHighlightFile('yml',    'yellow',  'none', 'yellow',  'none')
call NERDTreeHighlightFile('config', 'yellow',  'none', 'yellow',  'none')
call NERDTreeHighlightFile('conf',   'yellow',  'none', 'yellow',  'none')
call NERDTreeHighlightFile('json',   'yellow',  'none', 'yellow',  'none')
call NERDTreeHighlightFile('html',   'yellow',  'none', 'yellow',  'none')
call NERDTreeHighlightFile('styl',   'cyan',    'none', 'cyan',    'none')
call NERDTreeHighlightFile('css',    'cyan',    'none', 'cyan',    'none')
call NERDTreeHighlightFile('rb',     'Red',     'none', 'red',     'none')
call NERDTreeHighlightFile('js',     'Red',     'none', '#ffa500', 'none')
call NERDTreeHighlightFile('php',    'Magenta', 'none', '#ff00ff', 'none')
call NERDTreeHighlightFile('vue',    'Green', 'none', '#42b883', 'none')


"-----------------------------------------------------------------------
" Air line cuctom
"-----------------------------------------------------------------------
let g:airline_powerline_fonts = 1
set laststatus=2
let g:airline_theme='onedark'
" タブバーをかっこよく
let g:airline#extensions#tabline#enabled = 1

"-----------------------------------------------------------------------
"tab setting
"-----------------------------------------------------------------------

function! LightlineFugitive()
 if &ft !~? 'vimfiler\|gundo' && exists('*fugitive#head')
   return fugitive#head()
 else
   return ''
 endif
endfunction

function! LightlineFileformat()
 return winwidth(0) > 70 ? &fileformat : ''
endfunction

function! LightlineFiletype()
 return winwidth(0) > 70 ? (&filetype !=# '' ? &filetype : 'no ft') : ''
endfunction

function! LightlineFileencoding()
 return winwidth(0) > 70 ? (&fenc !=# '' ? &fenc : &enc) : ''
endfunction

function! LightlineMode()
 return winwidth(0) > 60 ? lightline#mode() : ''
endfunction

set showtabline=2 " 常にタブラインを表示

" Anywhere SID.
function! s:SID_PREFIX()
 return matchstr(expand('<sfile>'), '<SNR>\d\+_\zeSID_PREFIX$')
endfunction

" The prefix key.
nnoremap    [Tag]   <Nop>
nmap    t [Tag]
" Tab jump
for n in range(1, 9)
 execute 'nnoremap <silent> [Tag]'.n  ':<C-u>tabnext'.n.'<CR>'
endfor
" t1 で1番左のタブ、t2 で1番左から2番目のタブにジャンプ

map <silent> [Tag]c :tablast <bar> tabnew<CR>
" tc 新しいタブを一番右に作る
map <silent> [Tag]x :tabclose<CR>
" tx タブを閉じる
map <silent> [Tag]n :tabnext<CR>
" tn 次のタブ
map <silent> [Tag]p :tabprevious<CR>
" tp 前のタブ

vmap <S-C-k> <Plug>(caw:hatpos:toggle)
