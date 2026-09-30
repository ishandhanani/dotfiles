# Run with local options so the age check works without changing shell behavior.
# The argument identifies the Home Manager package environment.
() {
  emulate -L zsh
  setopt extendedglob
  autoload -Uz compinit

  local dump="${ZDOTDIR:-$HOME}/.zcompdump-$ZSH_VERSION"
  local checked="$dump.checked" inputs="$dump.inputs"
  local signature="$1"$'\n'"${(F)fpath}"

  # A changed package environment or fpath can replace completions without
  # changing their count, which compinit's own dump check would miss.
  if [[ ! -s $dump || ! -r $inputs || "$(<$inputs)" != "$signature" ]]; then
    rm -f -- "$dump" "$dump.zwc" "$checked"
  fi

  if [[ ! -s $dump || ! -f $checked || -n $checked(#qN.mh+24) ]]; then
    compinit -d "$dump" || return
    if [[ -s $dump ]]; then
      print -r -- "$signature" > "$inputs"
      # compinit leaves an unchanged dump's mtime intact. Track validation
      # separately so it runs once a day instead of on every subsequent shell.
      touch -- "$checked"
    fi
  else
    compinit -C -d "$dump" || return
  fi

  if [[ -s $dump && ( ! -s $dump.zwc || $dump -nt $dump.zwc ) ]]; then
    # Publish atomically so another shell never reads partially written wordcode.
    local compiled="$dump.$$.zwc"
    zcompile "$compiled" "$dump" && mv -f -- "$compiled" "$dump.zwc"
  fi
} "$@"
