#!/bin/bash
# Claude Code Status Line - Based on Starship "Myth Dark Pointed" theme
# Colors from starship.toml:
# - Username: #3388FF (blue)
# - Hostname: #AFD700 (yellow-green)
# - Directory: #6F6A70 (gray)
# - Git branch: #96ab5f (green)
# - Git status: #E0B25D (yellow)
# - Accent: #FF6AC1 (pink)

input=$(cat)

# Extract JSON values
model=$(echo "$input" | jq -r '.model.display_name')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir')

# Calculate context window usage
usage=$(echo "$input" | jq '.context_window.current_usage')
context_info=""
if [ "$usage" != "null" ]; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    size=$(echo "$input" | jq '.context_window.context_window_size')
    if [ "$size" != "null" ] && [ "$size" -gt 0 ] 2>/dev/null; then
        pct=$((current * 100 / size))
        context_info=$(printf "💭 %d%%" "$pct")
    fi
fi

# Get username and hostname
username=$(whoami)
hostname=$(hostname -s 2>/dev/null || hostname)

# Get directory (show relative to project if in project, otherwise show ~)
if [ -n "$project_dir" ] && [ "$current_dir" != "$project_dir" ]; then
    display_dir="${current_dir#$project_dir/}"
    if [ "$display_dir" = "$current_dir" ]; then
        display_dir=$(echo "$current_dir" | sed "s|^$HOME|~|")
    fi
else
    display_dir=$(echo "$current_dir" | sed "s|^$HOME|~|")
fi

# Replace ~ with  icon like starship config
display_dir=$(echo "$display_dir" | sed 's|^~| |')

# Get git branch if in a git repo
git_info=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
        # Check for uncommitted changes (like starship's git_status)
        git_status=""
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            git_status=" 📝"
        fi
        # Green color for git branch like starship (#96ab5f)
        git_info=$(printf " \033[2;38;5;149m %s\033[0m%s" "$branch" "$git_status")
    fi
fi

# Separator (Starship Pointed style)
sep="\033[2;38;5;242m\033[0m"

# Build status line with colors matching Starship theme (dim for subtlety)
# Pink accent at start (#FF6AC1 -> 38;5;205)
# Blue for username (#3388FF -> 38;5;33)
# Yellow-green for hostname (#AFD700 -> 38;5;148)
# Gray for directory (#6F6A70 -> 38;5;242)
# Purple for model
printf "\033[38;5;205m⚡\033[0m %s \033[2;38;5;33m %s\033[0m\033[2;38;5;242m@\033[0m\033[2;38;5;148m💻 %s\033[0m %s \033[2;38;5;242m%s\033[0m%s %s \033[2;38;5;135m🧠 %s\033[0m \033[2;38;5;244m%s\033[0m" \
    "$sep" "$username" "$hostname" "$sep" "$display_dir" "$git_info" "$sep" "$model" "$context_info"
