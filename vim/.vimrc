set number
syntax on
:colorscheme jellybeans

" vim-plug
call plug#begin()

Plug 'dense-analysis/ale'
Plug '907th/vim-auto-save'
Plug 'godlygeek/tabular'
Plug 'preservim/vim-markdown'

call plug#end()

" File tree
inoremap <c-b> <Esc>:w<cr>:Lex<cr>:vertical resize 30<cr>
nnoremap <c-b> <Esc>:Lex<cr>:vertical resize 30<cr>

" Cursor-like cgpt
nnoremap <C-l> :botright vertical terminal cgpt --no-history<CR><C-\><C-n>:vertical resize 50<CR>i
inoremap <C-l> <Esc>:botright vertical terminal cgpt --no-history<CR><C-\><C-n>:vertical resize 50<CR>i

" ALE 
let g:ale_lint_on_text_changed = 'always'  
let g:ale_lint_on_insert_leave = 1        
let g:ale_lint_on_enter = 1              
let g:ale_lint_on_save = 1              
let g:ale_set_highlights = 1
let g:ale_sign_error = '✘'
let g:ale_sign_warning = '⚠'

" Python linting and fixing
let g:ale_linters = { "python": ["ruff"] }
let g:ale_fixers = { "python": ["ruff", "ruff_format"] }

" My VSCode bindings
nnoremap gr :ALEFindReferences<CR>
nnoremap gn :ALERename<CR>
nnoremap gi :ALEGoToImplementation<CR>
nnoremap gp :ALEHover<CR>
nnoremap gm :ALENext<CR>

" Auto-save 
let g:auto_save = 1