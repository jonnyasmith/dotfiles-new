#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract fields
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // empty')
git_branch=$(git -C "${current_dir:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
# Mark the repo as dirty if there is any change at all (staged, unstaged, or
# untracked). --porcelain prints nothing for a clean tree, so any output = dirty.
git_dirty=""
if [ -n "$git_branch" ] && [ -n "$(git -C "${current_dir:-.}" status --porcelain 2>/dev/null)" ]; then
    git_dirty="*"
fi
context_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
context_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
exceeds_200k=$(echo "$input" | jq -r '.exceeds_200k_tokens // empty')
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_hour_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Color helpers
gray()   { printf '\033[38;5;245m%s\033[0m' "$1"; }
yellow() { printf '\033[38;5;221m%s\033[0m' "$1"; }
green()  { printf '\033[38;5;114m%s\033[0m' "$1"; }
orange() { printf '\033[38;5;215m%s\033[0m' "$1"; }
cyan()   { printf '\033[38;5;80m%s\033[0m' "$1"; }
pink()   { printf '\033[38;5;210m%s\033[0m' "$1"; }
red()    { printf '\033[38;5;203m%s\033[0m' "$1"; }
sep()    { gray " · "; }

# Format a raw token count as a compact human string: <1000 verbatim,
# otherwise rounded to the nearest thousand (e.g. 39271 -> "39K").
format_tokens() {
    local t="$1"
    if [ "$t" -ge 1000 ]; then
        printf "%dK" $(( (t + 500) / 1000 ))
    else
        printf "%d" "$t"
    fi
}

# Format a Unix-epoch reset timestamp for display in local time.
# Shows just the time (HH:MM) if it falls today, otherwise "Mon D, HH:MM".
format_reset() {
    local epoch="$1"
    # Only accept a plain integer epoch
    [[ "$epoch" =~ ^[0-9]+$ ]] || return
    if [ "$(date -r "$epoch" +%Y-%m-%d)" = "$(date +%Y-%m-%d)" ]; then
        date -r "$epoch" +%H:%M
    else
        date -r "$epoch" "+%b %e, %H:%M" | tr -s ' '
    fi
}

# Shorten home directory in path
if [[ "$current_dir" == "$HOME"* ]]; then
    display_dir="~${current_dir#$HOME}"
else
    display_dir="$current_dir"
fi

# Build status line output with separators
output=""

# Add model + effort if available
if [ -n "$model_name" ]; then
    if [ -n "$effort" ]; then
        output="$(yellow "$model_name $effort")"
    else
        output="$(yellow "$model_name")"
    fi
fi

# Add current directory
if [ -n "$display_dir" ]; then
    [ -n "$output" ] && output="$output$(sep)"
    output="$output$(green "$display_dir")"
fi

# Add git branch (only if in a git repo and branch exists)
if [ -n "$git_branch" ]; then
    [ -n "$output" ] && output="$output$(sep)"
    output="$output$(cyan "$git_branch")"
    [ -n "$git_dirty" ] && output="$output$(orange "$git_dirty")"
fi

# Add context usage as an absolute token count, coloured against the
# long-context pricing boundary: Anthropic bills premium input/output rates
# once a request exceeds 200K input tokens (the exceeds_200k_tokens flag).
# green = cheap tier, orange = approaching 200K, red = premium tier active.
# The 1M-window percentage is kept as a small gray hint (this is the old "% used").
if [ -n "$context_tokens" ]; then
    [ -n "$output" ] && output="$output$(sep)"
    tok_disp="$(format_tokens "$context_tokens")"
    if [ "$exceeds_200k" = "true" ]; then
        seg="$(red "${tok_disp} ctx")"
    elif [ "$context_tokens" -ge 150000 ]; then
        seg="$(orange "${tok_disp} ctx")"
    else
        seg="$(green "${tok_disp} ctx")"
    fi
    output="$output${seg}"
    [ -n "$context_used" ] && output="$output $(gray "($(printf "%.0f" "$context_used")%)")"
fi

# Add 5-hour rate limit remaining
if [ -n "$five_hour" ]; then
    [ -n "$output" ] && output="$output$(sep)"
    remaining=$((100 - ${five_hour%.*}))
    reset_time="$(format_reset "$five_hour_resets")"
    output="$output$(pink "5h ${remaining}%")"
    [ -n "$reset_time" ] && output="$output $(gray "(${reset_time})")"
fi

# Add 7-day rate limit remaining
if [ -n "$seven_day" ]; then
    [ -n "$output" ] && output="$output$(sep)"
    remaining=$((100 - ${seven_day%.*}))
    reset_time="$(format_reset "$seven_day_resets")"
    output="$output$(pink "weekly ${remaining}%")"
    [ -n "$reset_time" ] && output="$output $(gray "(${reset_time})")"
fi

# Print the output
[ -n "$output" ] && echo "$output"
