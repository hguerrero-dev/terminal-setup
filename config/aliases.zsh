# ---- terminal-pretty aliases (multi-distro) ----

# ---- eza (ls con iconos) ----
if command -v eza >/dev/null 2>&1; then
  alias ls="eza --icons=auto"
  alias ll="eza -la --icons=auto --git"
  alias la="eza -a --icons=auto"
  alias lt="eza --tree --level=2 --icons=auto"
  alias tree="eza --tree --icons=auto"
fi

# ---- bat (cat con syntax highlighting) ----
if command -v bat >/dev/null 2>&1; then
  alias cat="bat --paging=never"
elif command -v batcat >/dev/null 2>&1; then
  alias cat="batcat --paging=never"
fi

# ---- busqueda ----
[[ $(command -v rg) ]] && alias rgil="rg -i"

# ---- red ----
command -v doggo >/dev/null 2>&1 && alias dig="doggo"
alias myip="curl -s ifconfig.me && echo"

# ---- rm seguro (trash-cli) ----
command -v trash-put >/dev/null 2>&1 && alias rm="trash-put"

# ---- tmux ----
alias tnew="tmux new -s"
alias ta="tmux attach -t"
alias tl="tmux ls"

# ---- docker / compose ----
[[ $(command -v docker) ]] && alias d="docker" && alias dc="docker compose" && alias dcu="docker compose up -d" && alias dcd="docker compose down" && alias dcl="docker compose logs -f"
command -v lazydocker >/dev/null 2>&1 && alias lzd="lazydocker"

# ---- git ----
[[ $(command -v git) ]] && alias g="git" && alias gs="git status" && alias gl="git log --oneline --graph --decorate"

# ---- sistema ----
alias ports="ss -tulanp"
alias df="df -h"
alias free="free -h"

# ---- misc ----
alias ff="fastfetch --pipe false"
