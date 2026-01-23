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

      " Limit viminfo to prevent slow startup
      " '10 = marks for 10 files, <50 = 50 lines per register, s10 = 10kb max item size
      " h = don't restore hlsearch, n = viminfo file location
      set viminfo='10,<50,s10,h
      
      " ALE - Optimized for performance
      let g:ale_lint_on_text_changed = 'normal'  " Only lint in normal mode, not while typing
      let g:ale_lint_delay = 300                 " Debounce linting by 300ms
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
