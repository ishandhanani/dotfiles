{ config, pkgs, lib, ... }:

{
  programs.vim = {
    enable = true;
    
    # Only the plugins from your original vimrc
    plugins = with pkgs.vimPlugins; [
      ale
      vim-auto-save
      tabular
      jellybeans-vim
    ];
    
    # Your exact vimrc configuration
    extraConfig = ''
      set number
      syntax on
      colorscheme jellybeans
      
      " ALE 
      let g:ale_lint_on_text_changed = 'always'  
      let g:ale_lint_on_insert_leave = 1        
      " Make sure linting happens when entering a buffer and when saving
      let g:ale_lint_on_enter = 1              
      let g:ale_lint_on_save = 1              
      " Make sure highlighting is working properly
      let g:ale_set_highlights = 1
      " Make it look pretty
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
      let g:auto_save = 1  " enable AutoSave on Vim startup
    '';
  };
}
