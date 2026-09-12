#!/usr/bin/env bash
# terminal-pretty — installador multi-distro
# NO ejecutar con sudo directamente; el script usa sudo internamente cuando lo necesita.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONF="$HOME/.config"
mkdir -p "$BIN_DIR"
# Asegurar que los binarios instalados sean visibles en esta misma sesión
export PATH="$BIN_DIR:$PATH"

# ---- Colores ----
R='\033[0;31m' Y='\033[0;33m' G='\033[0;32m' B='\033[1m' NC='\033[0m'
info()  { printf "${G}>>> ${NC}%s\n" "$*"; }
warn()  { printf "${Y}⚠️   ${NC}%s\n" "$*"; }
err()   { printf "${R}✖  ${NC}%s\n" "$*" >&2; }
FAILED=()

# ---- Si lo corren como root abortar ----
[[ $EUID -eq 0 ]] && err "NO lo corras con sudo. El script pide sudo internamente." && exit 1

# ================================================================
# 1. DETECCION DE DISTRIBUCION
# ================================================================
[[ -r /etc/os-release ]] && . /etc/os-release
ID="${ID:-unknown}"
ID_LIKE="${ID_LIKE:-}"
PM=""   # dnf|apt|pacman|zypper
PM_FAMILY=""  # nombre legible

case "$ID $ID_LIKE" in
  *fedora*|*rhel*|*centos*)   PM=dnf;     PM_FAMILY="Fedora / RHEL" ;;
  *debian*|*ubuntu*)          PM=apt;     PM_FAMILY="Debian / Ubuntu" ;;
  *arch*|*manjaro*|*endeavour*) PM=pacman; PM_FAMILY="Arch" ;;
  *suse*)                     PM=zypper;  PM_FAMILY="openSUSE" ;;
  *)                          PM=apt;     PM_FAMILY="desconocido, intentando apt"; warn "Distro no reconocida ($ID). Se intentará apt." ;;
esac

info "Distribución: $ID ($PM_FAMILY) → gestor: $PM"

# ---- Funcion para instalar paquetes ----
pm_install() {
  case $PM in
    dnf)    sudo dnf install -y "$@" ;;
    apt)    sudo apt-get install -y --no-install-recommends "$@" ;;
    pacman) sudo pacman -S --needed --noconfirm "$@" ;;
    zypper) sudo zypper install -y --no-confirm "$@" ;;
  esac
}

pm_update() {
  case $PM in
    dnf)    sudo dnf check-update -q || true ;;
    apt)    sudo apt-get update -qq ;;
    pacman) sudo pacman -Sy ;;
    zypper) sudo zypper refresh -q || true ;;
  esac
}

# ---- Instalar herramienta o fallar con warning ----
try_tool() {
  local cmd="$1"
  local fedora_pkg="${2:-}" debian_pkg="${3:-}" arch_pkg="${4:-}"
  command -v "$cmd" &>/dev/null && return 0

  local pkg=""
  case $PM in
    dnf)    pkg="$fedora_pkg" ;;
    apt)    pkg="$debian_pkg" ;;
    pacman) pkg="$arch_pkg" ;;
    zypper) pkg="$fedora_pkg" ;;  # openSUSE suele usar nombres similares a Fedora
  esac

  if [[ -z "$pkg" || "$pkg" == "-" ]]; then
    warn "$cmd no disponible en repos de $PM_FAMILY"
    FAILED+=("$cmd")
    return 1
  fi

  info "Instalando $cmd ($pkg)..."
  if pm_install "$pkg"; then
    if ! command -v "$cmd" &>/dev/null; then
      warn "$cmd instalado pero no encontrado en PATH tras instalar $pkg"
      FAILED+=("$cmd")
    fi
  else
    warn "Error al instalar $pkg"
    FAILED+=("$cmd")
  fi
}

# ---- Arquitectura ----
ARCH_HOST=$(uname -m)
case "$ARCH_HOST" in
  x86_64|amd64)  ARCH_GH="x86_64"; ARCH_GH_ALT="amd64"; ARCH_LAZY="x86_64"; ARCH_YAZI="x86_64" ;;
  aarch64|arm64) ARCH_GH="aarch64"; ARCH_GH_ALT="arm64"; ARCH_LAZY="arm64"; ARCH_YAZI="aarch64" ;;
  *)              err "Arquitectura no soportada: $ARCH_HOST"; exit 1 ;;
esac

# ---- Helper: latest release tag de GitHub ----
# Nota: se ignora el exit code de curl a propósito. Con `set -o pipefail`,
# `grep -m1` cierra el pipe antes de que curl termine (SIGPIPE → exit 23)
# aunque el tag ya se haya recibido bien. Lo que importa es que el tag
# no esté vacío.
gh_tag() {
  local _tag
  set +o pipefail
  _tag=$(curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | grep -m1 '"tag_name"' | cut -d'"' -f4)
  set -o pipefail
  [[ -n "$_tag" ]] || return 1
  printf '%s\n' "$_tag"
}

# ---- Helper: descargar tar.gz de GitHub y extraer binario(s) ----
# dl_gh_tar <repo> <asset_pattern> <binarios...>
dl_gh_tar() {
  local repo="$1" asset="$2"; shift 2
  local tag; tag=$(gh_tag "$repo") || { warn "No se pudo obtener release de $repo"; FAILED+=("$@"); return 1; }
  local url="https://github.com/$repo/releases/download/$tag/$asset"
  info "Descargando $repo $tag..."
  local tmpdir; tmpdir=$(mktemp -d)
  if ! curl -fsSL "$url" -o "$tmpdir/pkg.tar.gz" 2>/dev/null; then
    warn "No se pudo descargar $url"
    rm -rf "$tmpdir"
    FAILED+=("$@")
    return 1
  fi
  tar xzf "$tmpdir/pkg.tar.gz" -C "$tmpdir" 2>/dev/null || {
    warn "No se pudo extraer $asset"
    rm -rf "$tmpdir"
    FAILED+=("$@")
    return 1
  }
  for bin in "$@"; do
    local found
    found=$(find "$tmpdir" -name "$bin" -type f | head -1)
    if [[ -n "$found" ]]; then
      install -m 755 "$found" "$BIN_DIR/$bin"
    else
      warn "Binario $bin no encontrado en $repo"
      FAILED+=("$bin")
    fi
  done
  rm -rf "$tmpdir"
}

# ================================================================
# 2. BASE TOOLS (dependencies for everything else)
# ================================================================
info "Actualizando índices del gestor de paquetes..."
pm_update

case $PM in
  dnf)    sudo dnf install -y -q git curl wget unzip tar gzip ca-certificates fontconfig zsh ;;
  apt)    sudo apt-get install -y --no-install-recommends git curl wget unzip tar gzip ca-certificates fontconfig zsh ;;
  pacman) sudo pacman -S --needed --noconfirm git curl wget unzip tar fontconfig zsh ;;
  zypper) sudo zypper install -y --no-confirm git curl wget unzip tar gzip ca-certificates fontconfig zsh ;;
esac

# ---- Symlinks Debian/Ubuntu (fdfind->fd, batcat->bat) ----
if [[ "$PM" == "apt" ]]; then
  command -v fd &>/dev/null || command -v fdfind &>/dev/null && {
    mkdir -p "$BIN_DIR"
    command -v fd &>/dev/null || ln -sf "$(command -v fdfind)" "$BIN_DIR/fd" 2>/dev/null || true
  }
  command -v bat &>/dev/null || command -v batcat &>/dev/null && {
    mkdir -p "$BIN_DIR"
    command -v bat &>/dev/null || ln -sf "$(command -v batcat)" "$BIN_DIR/bat" 2>/dev/null || true
  }
fi

# ================================================================
# 3. HERRAMIENTAS PRINCIPALES (via repos)
# ================================================================
info "Instalando herramientas de los repos..."

#                     cmd         fedora          debian              arch
try_tool zsh          zsh          zsh              zsh
try_tool eza          eza          eza              eza
try_tool bat          bat          bat              bat
try_tool fd           fd-find      fd-find          fd
try_tool fzf          fzf          fzf              fzf
try_tool zoxide       zoxide       zoxide           zoxide
try_tool rg           ripgrep      ripgrep          ripgrep
try_tool delta        git-delta    git-delta        git-delta
try_tool http         httpie       httpie           httpie
try_tool gh           gh           gh               github-cli
try_tool atuin        atuin        atuin            atuin
try_tool thefuck      thefuck      thefuck          thefuck
try_tool trash-put    trash-cli    trash-cli        trash-cli
try_tool procs        procs        procs            procs
try_tool tokei        tokei        tokei            tokei
try_tool hyperfine    hyperfine    hyperfine        hyperfine
try_tool pv           pv           pv               pv
try_tool progress     progress     progress         progress
try_tool tmux         tmux         tmux             tmux
try_tool fastfetch    fastfetch    fastfetch        fastfetch
try_tool tldr         tealdeer     tealdeer         tealdeer

# ---- Symlinks post-instalación (Debian/Ubuntu renombra binarios) ----
if [[ "$PM" == "apt" ]]; then
  command -v fd &>/dev/null || [[ -x /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind "$BIN_DIR/fd" 2>/dev/null || true
  command -v bat &>/dev/null || [[ -x /usr/bin/batcat ]] && ln -sf /usr/bin/batcat "$BIN_DIR/bat" 2>/dev/null || true
fi

# ================================================================
# 4. BINARIOS DESDE GITHUB (multi-arch, siempre en BIN_DIR)
# ================================================================
info "Descargando binarios desde GitHub..."

# ---- starship ----
if [[ ! -x "$BIN_DIR/starship" ]] && ! command -v starship &>/dev/null; then
  info "Instalando starship..."
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$BIN_DIR" 2>/dev/null || \
    dl_gh_tar starship/starship "starship-${ARCH_GH}-unknown-linux-gnu.tar.gz" starship
fi

# ---- fastfetch (fallback si repos no lo tienen) ----
if ! command -v fastfetch &>/dev/null && [[ ! -x "$BIN_DIR/fastfetch" ]]; then
  info "fastfetch no está en repos — descargando binario..."
  dl_gh_tar fastfetch-cli/fastfetch "fastfetch-linux-${ARCH_GH_ALT}.tar.gz" fastfetch 2>/dev/null && \
    sudo install -m 755 "$BIN_DIR/fastfetch" /usr/local/bin/fastfetch 2>/dev/null || true
fi

# ---- lazygit (asset: lazygit_<VER-sin-v>_linux_<x86_64|arm64>.tar.gz) ----
if ! command -v lazygit &>/dev/null && [[ ! -x "$BIN_DIR/lazygit" ]]; then
  LAZY_TAG=$(gh_tag jesseduffield/lazygit) || LAZY_TAG=""
  if [[ -n "$LAZY_TAG" ]]; then
    dl_gh_tar jesseduffield/lazygit "lazygit_${LAZY_TAG#v}_linux_${ARCH_LAZY}.tar.gz" lazygit || true
  else
    warn "No se pudo obtener release de lazygit"
    FAILED+=("lazygit")
  fi
fi

# ---- lazydocker (asset: lazydocker_<VER-sin-v>_Linux_<x86_64|arm64>.tar.gz) ----
if ! command -v lazydocker &>/dev/null && [[ ! -x "$BIN_DIR/lazydocker" ]]; then
  LZD_TAG=$(gh_tag jesseduffield/lazydocker) || LZD_TAG=""
  if [[ -n "$LZD_TAG" ]]; then
    dl_gh_tar jesseduffield/lazydocker "lazydocker_${LZD_TAG#v}_Linux_${ARCH_LAZY}.tar.gz" lazydocker || true
  else
    warn "No se pudo obtener release de lazydocker"
    FAILED+=("lazydocker")
  fi
fi

# ---- yazi ----
if ! command -v yazi &>/dev/null && [[ ! -x "$BIN_DIR/yazi" ]]; then
  info "Descargando yazi..."
  YAZI_VER=$(gh_tag sxyazi/yazi) || true
  if [[ -n "$YAZI_VER" ]]; then
    YAZI_TMP=$(mktemp -d)
    if curl -fsSL "https://github.com/sxyazi/yazi/releases/download/${YAZI_VER}/yazi-${ARCH_YAZI}-unknown-linux-gnu.zip" \
      -o "$YAZI_TMP/yazi.zip" 2>/dev/null && \
       unzip -qo "$YAZI_TMP/yazi.zip" -d "$YAZI_TMP" 2>/dev/null; then
      YAZI_BIN=$(find "$YAZI_TMP" -name yazi -type f | head -1)
      YA_BIN=$(find "$YAZI_TMP" -name ya -type f | head -1)
      [[ -n "$YAZI_BIN" ]] && install -m 755 "$YAZI_BIN" "$BIN_DIR/yazi"
      [[ -n "$YA_BIN" ]] && install -m 755 "$YA_BIN" "$BIN_DIR/ya"
      [[ -z "$YAZI_BIN" ]] && { warn "Binario yazi no encontrado en el zip"; FAILED+=("yazi"); }
    else
      warn "No se pudo descargar yazi ${YAZI_VER}"
      FAILED+=("yazi")
    fi
    rm -rf "$YAZI_TMP"
  else
    warn "No se pudo obtener release de yazi"
    FAILED+=("yazi")
  fi
fi

# ---- doggo (asset: doggo-linux-<x86_64|aarch64>.tar.gz) ----
if ! command -v doggo &>/dev/null && [[ ! -x "$BIN_DIR/doggo" ]]; then
  dl_gh_tar mr-karan/doggo "doggo-linux-${ARCH_GH}.tar.gz" doggo || true
fi

# ---- bandwhich (asset: bandwhich-<TAG-con-v>-<arch>-unknown-linux-gnu.tar.gz) ----
if ! command -v bandwhich &>/dev/null && [[ ! -x "$BIN_DIR/bandwhich" ]]; then
  BW_TAG=$(gh_tag imsnif/bandwhich) || BW_TAG=""
  if [[ -n "$BW_TAG" ]]; then
    dl_gh_tar imsnif/bandwhich "bandwhich-${BW_TAG}-${ARCH_GH}-unknown-linux-gnu.tar.gz" bandwhich || true
  else
    warn "No se pudo obtener release de bandwhich"
    FAILED+=("bandwhich")
  fi
  # Permite capturar tráfico sin sudo
  [[ -x "$BIN_DIR/bandwhich" ]] && sudo setcap 'cap_net_raw,cap_net_admin+eip' "$BIN_DIR/bandwhich" 2>/dev/null || true
fi

# ================================================================
# 5. FUENTES NERD FONTS
# ================================================================
# Sin -q: con `set -o pipefail`, `grep -q` cierra el pipe antes de que
# fc-list termine (SIGPIPE) y la tubería reportaría fallo aunque haya match.
if [[ -n "$(fc-list 2>/dev/null | grep 'CaskaydiaCove Nerd' || true)" ]]; then
  info "CaskaydiaCove Nerd Font ya instalada ✓"
else
  info "Descargando CaskaydiaCove Nerd Font..."
  CURL=$(gh_tag ryanoasis/nerd-fonts) || CURL=""
  FONT_DIR=$(mktemp -d)
  if [[ -z "$CURL" ]]; then
    warn "No se pudo obtener release de nerd-fonts"
    FAILED+=("nerd-fonts")
  elif curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${CURL}/CascadiaCode.tar.xz" \
    -o "$FONT_DIR/fonts.tar.xz" && \
    tar xJf "$FONT_DIR/fonts.tar.xz" -C "$FONT_DIR" --wildcards '*.ttf' && \
    mkdir -p "$HOME/.local/share/fonts/CaskaydiaNF" && \
    find "$FONT_DIR" -name '*.ttf' -exec mv {} "$HOME/.local/share/fonts/CaskaydiaNF/" \; && \
    fc-cache -f "$HOME/.local/share/fonts/CaskaydiaNF/"; then
    info "Fuentes instaladas ✓"
  else
    warn "Error al instalar fuentes"
    FAILED+=("nerd-fonts")
  fi
  rm -rf "$FONT_DIR"
fi

# ================================================================
# 6. ZSH + OH MY ZSH + PLUGINS
# ================================================================
if command -v zsh &>/dev/null; then
  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    info "Cambiando shell por defecto a zsh..."
    chsh -s "$(command -v zsh)" 2>/dev/null && info "Shell cambiado ✓ (aplica en el próximo login)" || warn "No se pudo cambiar shell. Ejecuta manualmente: chsh -s \$(which zsh)"
  else
    info "zsh ya es el shell por defecto ✓"
  fi
else
  warn "zsh no está instalado, no se puede cambiar el shell por defecto"
  FAILED+=("zsh")
fi

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  info "Instalando Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 2>/dev/null || true
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/plugins"

clone_plugin() {
  local repo="$1" name="$2"
  if [[ ! -d "$ZSH_CUSTOM/plugins/$name" ]]; then
    info "Clonando $name..."
    git clone --depth=1 --recurse-submodules -q "https://github.com/$repo" "$ZSH_CUSTOM/plugins/$name" 2>/dev/null || true
  fi
}

clone_plugin zsh-users/zsh-autosuggestions    zsh-autosuggestions
clone_plugin zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting
clone_plugin olets/zsh-abbr                    zsh-abbr

# Corrección: el submodule de zsh-abbr (.gitmodules es un archivo, no un directorio)
# También repara clones viejos hechos sin --recurse-submodules.
if [[ -f "$ZSH_CUSTOM/plugins/zsh-abbr/.gitmodules" ]]; then
  if [[ ! -f "$ZSH_CUSTOM/plugins/zsh-abbr/zsh-job-queue/zsh-job-queue.plugin.zsh" ]]; then
    info "Descargando submodule de zsh-abbr..."
    git -C "$ZSH_CUSTOM/plugins/zsh-abbr" submodule update --init --recursive 2>/dev/null || true
  fi
fi

# ================================================================
# 7. COPIAR CONFIGURACIONES
# ================================================================
info "Copiando configuraciones..."

backup_and_copy() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  [[ -f "$dst" ]] && cp "$dst" "$dst.bak.$(date +%s)"
  cp "$src" "$dst"
}

# ---- Shell ----
backup_and_copy "$SRC_DIR/config/zshrc"       "$HOME/.zshrc"

# ---- Aliases ----
backup_and_copy "$SRC_DIR/config/aliases.zsh"  "$CONF/terminal-pretty/aliases.zsh"

# ---- Starship ----
backup_and_copy "$SRC_DIR/config/starship.toml" "$CONF/starship.toml"

# ---- Fastfetch ----
backup_and_copy "$SRC_DIR/config/fastfetch.jsonc" "$CONF/fastfetch/config.jsonc"

# ---- eza ----
backup_and_copy "$SRC_DIR/config/eza-config.yml" "$CONF/eza/config.yml"

# ---- fzf extras ----
if [[ ! -f "$CONF/fzf/key-bindings.zsh" ]]; then
  info "Descargando fzf extras..."
  mkdir -p "$CONF/fzf"
  FZF_RAW="https://raw.githubusercontent.com/junegunn/fzf/master/shell"
  curl -fsSL "$FZF_RAW/key-bindings.zsh"    -o "$CONF/fzf/key-bindings.zsh"    2>/dev/null || true
  curl -fsSL "$FZF_RAW/completion.zsh"      -o "$CONF/fzf/completion.zsh"      2>/dev/null || true
fi

# ---- Konsole (solo si está instalado) ----
if command -v konsole &>/dev/null || [[ -d "$HOME/.local/share/konsole" ]]; then
  info "Configurando Konsole..."
  mkdir -p "$HOME/.local/share/konsole"
  backup_and_copy "$SRC_DIR/konsole/Nerd.profile"              "$HOME/.local/share/konsole/Nerd.profile"
  backup_and_copy "$SRC_DIR/konsole/Transparent.colorscheme"   "$HOME/.local/share/konsole/Transparent.colorscheme"

  KRC="$HOME/.config/konsolerc"
  mkdir -p "$(dirname "$KRC")"
  [[ ! -f "$KRC" ]] && printf '[General]\nConfigVersion=1\n\n[UiSettings]\nColorScheme=\n' > "$KRC"
  if ! grep -q '^DefaultProfile=' "$KRC"; then
    printf '\n[Desktop Entry]\nDefaultProfile=Nerd.profile\n' >> "$KRC"
  fi
fi

# ================================================================
# 8. GIT GLOBAL CONFIG
# ================================================================
info "Configurando git..."
if [[ -t 0 ]]; then
  read -rp "  Git user name [hguerrero-dev]: " GIT_NAME
  GIT_NAME="${GIT_NAME:-hguerrero-dev}"
  read -rp "  Git email   [hguerrero.dev@proton.me]: " GIT_EMAIL
  GIT_EMAIL="${GIT_EMAIL:-hguerrero.dev@proton.me}"
else
  GIT_NAME="${GIT_NAME:-hguerrero-dev}"
  GIT_EMAIL="${GIT_EMAIL:-hguerrero.dev@proton.me}"
fi

[[ -z "$(git config --global user.name 2>/dev/null)" ]] && git config --global user.name  "$GIT_NAME"
[[ -z "$(git config --global user.email 2>/dev/null)" ]] && git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main 2>/dev/null

# ---- Git delta (diff con colores) ----
if command -v delta &>/dev/null; then
  git config --global core.pager "delta"
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.side-by-side true
  git config --global delta.line-numbers true
fi

# ================================================================
# 9. POST-INSTALACION
# ================================================================
# ---- tealdeer cache ----
command -v tldr &>/dev/null && info "Actualizando cache de tldr..." && tldr -u 2>/dev/null || true

# ---- zsh completions rebuild ----
rm -f "$HOME/.zcompdump"* 2>/dev/null

# ================================================================
# RESUMEN
# ================================================================
echo ""
printf "${B}============================================================${NC}\n"
printf "${B}  terminal-pretty — Instalación completada${NC}\n"
printf "${B}============================================================${NC}\n"
echo ""

if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf "${Y}⚠️  Estas herramientas no se pudieron instalar (puedes instalarlas manualmente):${NC}\n"
  _seen=""
  for f in "${FAILED[@]}"; do
    [[ "$_seen" == *"|$f|"* ]] && continue
    _seen+="|$f|"
    printf "   ${R}✗${NC} $f\n"
  done
  unset _seen
  echo ""
fi

printf "${G}Próximos pasos:${NC}\n"
echo "  1. Abre una NUEVA ventana de Konsole / terminal"
echo "  2. Si usas Konsole, ajusta la transparencia editando:"
echo "     ~/.local/share/konsole/Transparent.colorscheme"
echo "     (cambia el último número en Color=r,g,b,ALPHA — menor = más transparente)"
echo ""
printf "${G}Archivos instalados:${NC}\n"
echo "  ~/.zshrc                          → shell"
echo "  ~/.config/terminal-pretty/        → aliases"
echo "  ~/.config/starship.toml           → prompt"
echo "  ~/.config/fastfetch/config.jsonc  → neofetch"
echo "  ~/.config/eza/config.yml          → ls moderno"
echo "  ~/.config/konsolerc               → fuente + perfil Nerd"
echo "  ~/.local/share/konsole/           → transparencia (Tokyo Night)"
echo ""
echo "Ejecuta 'tldr -u' si quieres caché de ejemplos de comandos."
echo ""
