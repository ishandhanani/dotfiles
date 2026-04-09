#!/usr/bin/env bash
# Claude Code status line command
# Reads JSON from stdin and outputs a status line string

input=$(cat)

# --- Location and model ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
home="$HOME"
cwd="${cwd/#$home/~}"
model=$(echo "$input" | jq -r '.model.display_name // ""')

# --- Context window ---
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
  ctx_str=$(printf "ctx:%.0f%%" "$used")
else
  ctx_str=""
fi

# --- Helper: format seconds into a human-readable "Xh Ym" or "Ym" string ---
fmt_duration() {
  local secs="$1"
  if [ "$secs" -le 0 ] 2>/dev/null; then
    echo "now"
    return
  fi
  local h=$(( secs / 3600 ))
  local m=$(( (secs % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then
    printf '%dh %02dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

# --- Rate limits ---
# Extract fields
five_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_used=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

now=$(date +%s)
rate_str=""

if [ -n "$five_used" ] || [ -n "$week_used" ]; then
  rate_str=" | usage:"

  if [ -n "$five_used" ]; then
    five_rem=$(echo "$five_used" | awk '{printf "%.0f", 100 - $1}')
    if [ -n "$five_reset" ]; then
      five_secs=$(( five_reset - now ))
      five_time=$(fmt_duration "$five_secs")
      rate_str="$rate_str 5h:${five_rem}% rem(resets ${five_time})"
    else
      rate_str="$rate_str 5h:${five_rem}% rem"
    fi
  fi

  if [ -n "$week_used" ]; then
    week_rem=$(echo "$week_used" | awk '{printf "%.0f", 100 - $1}')
    if [ -n "$week_reset" ]; then
      week_secs=$(( week_reset - now ))
      week_time=$(fmt_duration "$week_secs")
      rate_str="$rate_str  7d:${week_rem}% rem(resets ${week_time})"
    else
      rate_str="$rate_str  7d:${week_rem}% rem"
    fi
  fi
fi

# --- Assemble output ---
# Build middle section (model + context)
mid="${model}"
[ -n "$ctx_str" ] && mid="${mid} ${ctx_str}"

printf '%s | %s%s' "$cwd" "$mid" "$rate_str"
