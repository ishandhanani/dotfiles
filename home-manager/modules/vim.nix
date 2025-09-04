{ config, pkgs, lib, ... }:

{
  programs.vim = {
    enable = true;
    
    # Basic settings
    settings = {
      number = true;
      relativenumber = false;
      expandtab = true;
      tabstop = 4;
      shiftwidth = 4;
      mouse = "a";
      ignorecase = true;
      smartcase = true;
      undofile = true;
      undodir = ["$HOME/.vim/undo"];
      background = "dark";
    };
    
    # Plugins
    plugins = with pkgs.vimPlugins; [
      # Essential plugins
      vim-sensible
      
      # Linting and formatting
      ale
      
      # Auto-save
      vim-auto-save
      
      # Text manipulation
      tabular
      vim-surround
      vim-commentary
      
      # Markdown support
      vim-markdown
      
      # File navigation
      nerdtree
      fzf-vim
      
      # Git integration
      vim-fugitive
      vim-gitgutter
      
      # Colorscheme
      jellybeans-vim
      
      # Status line
      vim-airline
      vim-airline-themes
    ];
    
    # Vim configuration
    extraConfig = ''
      " Colorscheme
      colorscheme jellybeans
      
      " vim-plug compatibility layer (for existing configs)
      " Note: plugins are managed by Nix, this is just for compatibility
      call plug#begin()
      " Plugins are already loaded by Nix
      call plug#end()
      
      " File tree keybindings
      inoremap <c-b> <Esc>:w<cr>:Lex<cr>:vertical resize 30<cr>
      nnoremap <c-b> <Esc>:Lex<cr>:vertical resize 30<cr>
      
      " Terminal with cgpt (AI assistant)
      if executable('cgpt')
        nnoremap <C-l> :botright vertical terminal cgpt --no-history<CR><C-\><C-n>:vertical resize 50<CR>i
        inoremap <C-l> <Esc>:botright vertical terminal cgpt --no-history<CR><C-\><C-n>:vertical resize 50<CR>i
      endif
      
      " ALE Configuration
      let g:ale_lint_on_text_changed = 'always'
      let g:ale_lint_on_insert_leave = 1
      let g:ale_lint_on_enter = 1
      let g:ale_lint_on_save = 1
      let g:ale_set_highlights = 1
      let g:ale_sign_error = '✘'
      let g:ale_sign_warning = '⚠'
      
      " Python linting with ruff
      let g:ale_linters = { 'python': ['ruff'] }
      let g:ale_fixers = { 
      \   'python': ['ruff', 'ruff_format'],
      \   'javascript': ['eslint', 'prettier'],
      \   'typescript': ['eslint', 'prettier'],
      \   'json': ['prettier'],
      \   'markdown': ['prettier'],
      \}
      
      " VSCode-like keybindings for ALE
      nnoremap gr :ALEFindReferences<CR>
      nnoremap gn :ALERename<CR>
      nnoremap gi :ALEGoToImplementation<CR>
      nnoremap gd :ALEGoToDefinition<CR>
      nnoremap gp :ALEHover<CR>
      nnoremap gm :ALENext<CR>
      nnoremap gM :ALEPrevious<CR>
      nnoremap <leader>f :ALEFix<CR>
      
      " Auto-save configuration
      let g:auto_save = 1  " enable AutoSave on Vim startup
      let g:auto_save_silent = 1  " do not display the auto-save notification
      let g:auto_save_events = ["InsertLeave", "TextChanged"]
      
      " NERDTree configuration
      nnoremap <C-n> :NERDTreeToggle<CR>
      let NERDTreeShowHidden=1
      let NERDTreeIgnore=['\.pyc$', '__pycache__', '\.git$', 'node_modules']
      
      " FZF configuration
      nnoremap <C-p> :Files<CR>
      nnoremap <leader>b :Buffers<CR>
      nnoremap <leader>rg :Rg<CR>
      
      " Airline configuration
      let g:airline_powerline_fonts = 1
      let g:airline_theme = 'jellybeans'
      let g:airline#extensions#ale#enabled = 1
      
      " Better search highlighting
      set hlsearch
      nnoremap <silent> <leader><space> :nohlsearch<CR>
      
      " Quick save and quit
      nnoremap <leader>w :w<CR>
      nnoremap <leader>q :q<CR>
      nnoremap <leader>wq :wq<CR>
      
      " Better split navigation
      nnoremap <C-j> <C-w>j
      nnoremap <C-k> <C-w>k
      nnoremap <C-h> <C-w>h
      nnoremap <C-l> <C-w>l
      
      " Maintain visual mode after indenting
      vnoremap < <gv
      vnoremap > >gv
      
      " Move lines up and down
      nnoremap <A-j> :m .+1<CR>==
      nnoremap <A-k> :m .-2<CR>==
      vnoremap <A-j> :m '>+1<CR>gv=gv
      vnoremap <A-k> :m '<-2<CR>gv=gv
    '';
  };
  
  # Alternative: Neovim with more modern configuration
  programs.neovim = {
    enable = false;  # Set to true if you prefer neovim
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    
    plugins = with pkgs.vimPlugins; [
      # Modern plugin ecosystem
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      nvim-treesitter.withAllGrammars
      telescope-nvim
      gitsigns-nvim
      lualine-nvim
      
      # Colorscheme
      catppuccin-nvim
    ];
    
    extraConfig = ''
      lua << EOF
        -- Modern Neovim configuration would go here
        vim.opt.number = true
        vim.opt.relativenumber = true
        
        -- Setup plugins
        require('lualine').setup()
        require('gitsigns').setup()
      EOF
    '';
  };
}