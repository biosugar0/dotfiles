"--------------------
"" 基本的な設定
"--------------------
"バックアップ設定
set directory=$HOME/vimbackup/tmp
set backupdir=$HOME/vimbackup/backupfile
"画面設定
set number         " 行番号を表示する
set cursorline     " カーソル行の背景色を変える
set laststatus=2   " ステータス行を常に表示
set cmdheight=2    " メッセージ表示欄を2行確保
set showmatch      " 対応する括弧を強調表示
set helpheight=999 " ヘルプを画面いっぱいに開く
set list           " 不可視文字を表示
" ノーマルモード時だけ ; と : を入れ替える
nnoremap ; :
nnoremap : ;
" 不可視文字の表示記号指定
set listchars=tab:▸\ ,eol:↲,extends:❯,precedes:❮
"移動設定
set backspace=indent,eol,start "Backspaceキーの影響範囲に制限を設けない
set whichwrap=b,s,h,l,<,>,[,] "行頭行末の左右移動で行をまたぐ
set scrolloff=8                "上下8行の視界を確保
set sidescrolloff=16           " 左右スクロール時の視界を確保
set sidescroll=1               " 左右スクロールは一文字づつ行う
"ファイル処理関連
set confirm "保存されていないファイルがあるときは終了前に保存確認
set hidden "保存されていないファイルがあるときでも別のファイルを開くことが出来る
set autoread "外部でファイルに変更がされた場合は読みなおす
"検索設定
set hlsearch "検索文字列をハイライトする
set incsearch "インクリメンタルサーチを行う
set ignorecase "大文字と小文字を区別しない
set smartcase "大文字と小文字が混在した言葉で検索を行った場合に限り、大文字と小文字を区別する
set wrapscan "最後尾まで検索を終えたら次の検索で先頭に移る
"タブ、インデント設定
set expandtab "タブ入力を複数の空白入力に置き換える
set tabstop=4 "画面上でタブ文字が占める幅
set shiftwidth=4 "自動インデントでずれる幅
set softtabstop=4 "連続した空白に対してタブキーやバックスペースキーでカーソルが動く幅
set autoindent "改行時に前の行のインデントを継続する
set smartindent "改行時に入力された行の末尾に合わせて次の行のインデントを増減する
"コピペ関連
"OSのクリップボードをレジスタ指定無しで Yank, Put 出来るようにする
set clipboard=unnamed,unnamedplus
" マウスの入力を受け付ける
set mouse=
"コマンドライン関連
" コマンドラインモードでTABキーによるファイル名補完を有効にする
set wildmenu wildmode=list:longest,full
" コマンドラインの履歴を1000件保存する
set history=1000
"ビープ音関連
"ビープ音すべてを無効にする
set visualbell t_vb=
set noerrorbells "エラーメッセージの表示時にビープを鳴らさない
" ステータス
set statusline=%<%f\ %m%r%h%w%{'['.(&fenc!=''?&fenc:&enc).']['.&ff.']'}%=%l,%c%V%8P
set statusline+=[%p%%]\ [LEN=%L]
set laststatus=2 
set fileencoding=utf-8
"オートコメントアウト無効
au FileType * setlocal formatoptions-=ro

nnoremap t  <Nop>
nnoremap tt  <C-]> "飛ぶ」
nnoremap tj  :<C-u>tag<CR>  " 「進む」
nnoremap tk  :<C-u>pop<CR>  " 「戻る」
nnoremap tl  :<C-u>tags<CR> " 履歴一覧
"------------------------------------------------------


"color
set t_Co=256
"プラグイン設定
if &compatible
    set nocompatible
endif
set runtimepath^=~/.vim/repos/github.com/Shougo/dein.vim

call dein#begin(expand('~/.cache/dein'))
call dein#add('Shougo/neocomplete.vim')
call dein#end()
if dein#check_install()
    call dein#install()
endif
filetype plugin indent on
syntax enable   
