#!/usr/bin/env zsh
# Exercise the actual completion cache in isolated homes, without touching ~/.zcompdump.
set -eu
local_root=${0:A:h:h}
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/home" "$scratch/completions-a" "$scratch/completions-b"
printf '#compdef cache-test-a\n' > "$scratch/completions-a/_cache_test"
printf '#compdef cache-test-b\n' > "$scratch/completions-b/_cache_test"
export CACHE_TEST_HOME="$scratch/home" CACHE_TEST_LOG="$scratch/calls"
export CACHE_TEST_SOURCE="$local_root/functions/completion-init.zsh"

cat > "$scratch/start.zsh" <<'ZSH'
set -eu
export ZDOTDIR=$CACHE_TEST_HOME
[[ -z ${2:-} ]] || fpath=("$2" $fpath)
autoload -Uz compinit
autoload +X compinit
functions[_test_compinit]=$functions[compinit]
compinit() {
  print -r -- "$*" >> "$CACHE_TEST_LOG"
  _test_compinit "$@"
}
before=$options[extendedglob]
source "$CACHE_TEST_SOURCE" "$1"
[[ $options[extendedglob] == $before ]]
[[ -z ${3:-} ]] || [[ ${_comps[$3]:-} == _cache_test ]]
ZSH

dump="$CACHE_TEST_HOME/.zcompdump-$(zsh -fc 'print $ZSH_VERSION')"
run() { zsh -f "$scratch/start.zsh" "$@"; }
last_call() { tail -n 1 "$CACHE_TEST_LOG"; }

run generation-a
[[ -s $dump && -s $dump.zwc && -s $dump.inputs && -f $dump.checked ]]
[[ $(last_call) == '-d '* ]]
zsh -fc 'zcompile -t "$1" >/dev/null' -- "$dump.zwc"
print 'PASS: cold startup creates and compiles a validated cache'

run generation-a
[[ $(last_call) == '-C -d '* ]]
print 'PASS: warm startup reuses the cache with EXTENDED_GLOB initially off'

touch -t 200001010000 "$dump.checked"
touch -t 200001010000 "$dump"
touch -t 200001010001 "$dump.zwc"
zmodload zsh/stat
zstat -H compiled_before "$dump.zwc"
run generation-a
[[ $(last_call) == '-d '* ]]
run generation-a
[[ $(last_call) == '-C -d '* ]]
zstat -H compiled_after "$dump.zwc"
[[ $compiled_before[mtime] == $compiled_after[mtime] ]]
print 'PASS: expired cache is validated once, then returns to the fast path'
print 'PASS: validation of unchanged completions preserves the compiled dump'

run generation-b
[[ $(last_call) == '-d '* ]]
[[ $(<$dump.inputs) == generation-b$'\n'* ]]
print 'PASS: changing the package environment invalidates the cache'

run generation-b "$scratch/completions-a" cache-test-a
[[ $(last_call) == '-d '* ]]
run generation-b "$scratch/completions-b" cache-test-b
[[ $(last_call) == '-d '* ]]
run generation-b "$scratch/completions-b" cache-test-b
[[ $(last_call) == '-C -d '* ]]
print 'PASS: replacing fpath entries with the same file count rebuilds completion mappings'

rm "$dump"
run generation-b "$scratch/completions-b" cache-test-b
[[ $(last_call) == '-d '* && -s $dump && -s $dump.zwc ]]
print 'PASS: missing text dump is regenerated even when compiled cache exists'

rm "$dump.zwc"
run generation-b "$scratch/completions-b" cache-test-b
[[ $(last_call) == '-C -d '* && -s $dump.zwc ]]
print 'PASS: missing wordcode is rebuilt without rescanning completions'

# Failed validation must not authorize the fast path for the next shell.
touch -t 200001010000 "$dump.checked"
ZDOTDIR=$CACHE_TEST_HOME zsh -fc '
  compinit() { return 1; }
  source "$CACHE_TEST_SOURCE" generation-failed
  [[ ! -f $ZDOTDIR/.zcompdump-$ZSH_VERSION.checked ]]
'
print 'PASS: failed validation does not mark the cache as checked'
