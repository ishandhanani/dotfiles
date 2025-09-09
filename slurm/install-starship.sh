#!/bin/bash

# Install starship into a slurm cluster 
# We cannot use the official script because it requires sudo

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)   TARGET="x86_64-unknown-linux-musl" ;;
  aarch64)  TARGET="aarch64-unknown-linux-musl" ;;
  *)        echo "Unsupported arch: $ARCH" ; exit 1 ;;
esac

curl -L "https://github.com/starship/starship/releases/latest/download/starship-${TARGET}.tar.gz" \
  -o /tmp/starship.tar.gz

mkdir -p "$HOME/.local/bin"
tar -xzf /tmp/starship.tar.gz -C "$HOME/.local/bin" starship
rm /tmp/starship.tar.gz

grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc \
  || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

grep -qxF 'eval "$(starship init bash)"' ~/.bashrc \
  || echo 'eval "$(starship init bash)"' >> ~/.bashrc

source ~/.bashrc
