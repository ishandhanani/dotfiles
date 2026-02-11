{ config, pkgs, lib, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    extraPackages = with pkgs; [
      ruff
      rust-analyzer
    ];
  };

  xdg.configFile."nvim" = {
    source = ../config/nvim;
    recursive = true;
  };
}
