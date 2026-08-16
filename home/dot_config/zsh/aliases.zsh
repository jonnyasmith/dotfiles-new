alias reload='source ~/.zshrc'

# Detect which `ls` flavor is in use
if ls --color > /dev/null 2>&1; then # GNU `ls`
    colorflag="--color"
else # OS X `ls`
    colorflag="-G"
fi

# bat detects a non-tty and emits plain undecorated text, so `cat file | …`
# and `$(cat file)` are unchanged; `command cat` bypasses. Guarded because a
# shell started before `mise bootstrap` has no bat and must not lose cat.
command -v bat >/dev/null 2>&1 && alias cat="bat --paging=never"

alias g="git"
alias lg="lazygit"
alias y="yarn"
alias h="history"
alias clean-orig="find . -name '*.orig' -delete"

alias ga='git a .'
alias gcm='git cm'
alias gf='git f'
alias gd='git d'
alias gll='git l -20'
alias gm='git m'
alias gp='git p'
alias gr='git r'
alias gs='git s'
alias push='git push'

alias wtc='worktree create'
alias wtr='worktree remove'
alias wtl='worktree list'

git_fetch_all() {
    original_dir=$(pwd)
    cd ~/dev && for dir in */; do
        if [ -d "$dir/.git" ]; then
            echo ""
            echo "\e[33mfetching $dir\e[0m"
            (cd "$dir" && git fetch --all)
        fi
    done
    cd "$original_dir"
}

alias fa='git_fetch_all'

gac_fn() {
    git add -A
    git commit -m "$*"
}

alias gac='noglob gac_fn'

alias d='docker'
# `docker compose`, not the retired v1 binary: Debian and Fedora install
# docker-compose-plugin, and nothing on macOS ships a `docker-compose`.
alias dc='docker compose'
alias k='kubectl'

alias ..='cd ..'
alias ...='cd ../..'
alias ....="cd ../../.."
alias .....="cd ../../../.."

# lsd emits plain undecorated output to a non-tty, so `ls | …` is unchanged,
# and `command ls` bypasses. Guarded like the bat alias above: a shell started
# before `mise bootstrap` has no lsd and must not lose ls. $colorflag is not
# passed through — lsd colours by default, and its `-G` means --gitsort.
if command -v lsd > /dev/null 2>&1; then
    alias ls="lsd"
    alias la="ls -AF"
else
    alias la="ls -AF ${colorflag}"
fi
alias ll="ls -l"
alias lla="ls -la"
alias lld="ls -l | grep ^d"
alias rmf="rm -rf"

alias weather='curl v2.wttr.in'

alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h -c'

alias ip="dig +short myip.opendns.com @resolver1.opendns.com"
alias ips="ifconfig -a | perl -nle'/(\d+\.\d+\.\d+\.\d+)/ && print $1'"

# One of @janmoesen’s ProTip™s
for method in GET HEAD POST PUT DELETE TRACE OPTIONS; do
    alias "$method"="lwp-request -m '$method'"
done
