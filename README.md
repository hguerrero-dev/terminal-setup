# terminal-pretty

Instalador multi-distro que configura una terminal moderna, funcional y estética con un solo comando.

## Soportado

| Distribución          | Gestor |
|-----------------------|--------|
| Fedora / RHEL / CentOS | dnf    |
| Ubuntu / Debian       | apt    |
| Arch / Manjaro        | pacman |

## Qué instala

### Herramientas

| Categoría | Herramientas |
|-----------|-------------|
| Navegación | eza (ls moderno), yazi (file manager), zoxide (cd inteligente), fzf (búsqueda fuzzy) |
| Busqueda | ripgrep (grep rápido), fd (find rápido), tealdeer (tldr rápido) |
| Git | lazygit (TUI), delta (diff con colores), GitHub CLI |
| Prompt | starship (minimalista + info completa) |
| Lenguajes | nodejs + npm, python3 + pip, gcc/g++/make, php, go, java (JDK), rust (rustup) — instalados vía gestor; starship los detecta por directorio |
| Docker | docker engine + compose (servicio activado, usuario agregado al grupo), lazydocker (TUI), docker compose aliases |
| Calidad de vida | thefuck (corrige comandos), trash-cli (rm seguro), atuin (historial sincronizado) |
| Monitoreo | procs, bandwhich (red en tiempo real), tokei (líneas de código), hyperfine (benchmarks) |
| Terminal | tmux, fastfetch, httpie, pv, progress |

### Configuración

- **Starship prompt**: usuario, hostname, SO, git branch/usuario, batería, hora, duración de comandos, iconos Material Design
- **Konsole**: fuente CaskaydiaCove Nerd Font Mono + esquema Tokyo Night translúcido con blur (ajustable)
- **Zsh**: autosuggestions, syntax-highlighting, zsh-abbr, flechas inteligentes, zoxide lazy-load
- **Git**: delta como pager (diff side-by-side, números de línea)

## Instalación

```bash
git clone https://github.com/hguerrero-dev/terminal-pretty.git
cd terminal-pretty
./install.sh
```

El script usa sudo internamente para instalar paquetes. **No lo ejecutes con sudo directamente.**

Al finalizar (importante, si no NO verás cambios):
1. Cierra Konsole **por completo** (`kquitapp6 konsole`) y vuelve a abrirlo — una ventana/pestaña nueva no basta porque el proceso cachea los perfiles
2. Si el script cambió tu shell, cierra sesión y entra de nuevo (`chsh` aplica al login)
3. Verifica con: `echo "perfil=$KONSOLE_PROFILE_NAME shell=$0"` (debe mostrar tu zsh). El propio script imprime un bloque `Verificación` con ✓/✗
4. Ajusta la transparencia editando `~/.local/share/konsole/Transparent.colorscheme` (cambia el último número de `Color=26,27,38,ALPHA` — menor = más transparente)
5. Ejecuta `tldr -u` para caché de ejemplos de comandos

## Estructura

```
terminal-pretty/
├── README.md
├── install.sh                 ← punto de entrada
├── config/
│   ├── zshrc                  → ~/.zshrc
│   ├── aliases.zsh            → ~/.config/terminal-pretty/aliases.zsh
│   ├── starship.toml          → ~/.config/starship.toml
│   ├── fastfetch.jsonc        → ~/.config/fastfetch/config.jsonc
│   └── eza-config.yml         → ~/.config/eza/config.yml
└── konsole/
    ├── Nerd.profile           → ~/.local/share/konsole/
    └── Transparent.colorscheme → ~/.local/share/konsole/
```

## Personalización

### Ajustar transparencia (Konsole)

En `~/.local/share/konsole/Transparent.colorscheme`:
```ini
[Background]
Color=26,27,38,170   ← 0 (transparente) a 255 (opaco)
```

### Agregar lenguajes al prompt

En `~/.config/starship.toml`, agrega un módulo:
```toml
[lua]
symbol = "\uE620 "
format = "via [$symbol$version](cyan) "
```
Consulta los iconos disponibles en [Nerd Fonts Cheat Sheet](https://www.nerdfonts.com/cheatsheet).

### Comandos útiles instalados

| Comando | Descripción |
|---------|-------------|
| `ll` `lt` `tree` | ls moderno con iconos (eza) |
| `cat` | syntax highlighting (bat) |
| `z <directorio>` | cd inteligente (zoxide) |
| `Ctrl+T` / `Ctrl+R` | buscar archivos / historial (fzf) |
| `lazygit` | TUI para git |
| `lzd` | TUI para docker |
| `myip` | IP pública |
| `ff` | fastfetch |
| `rm` → `trash-put` | papelera segura |
| `fuck` | corregir último comando (thefuck) |

## Notas

- **Lenguajes en monorepo**: starship detecta lenguajes por archivos marcadores en el directorio actual (`package.json`, `go.mod`, `Cargo.toml`, etc.). Si estás en la raíz de un monorepo sin estos archivos, no mostrará nada.
- **Bandwhich**: puede necesitar sudo la primera vez si el `setcap` no funcionó.
- **Ejecutar de nuevo**: el script es idempotente — puede ejecutarse múltiples veces sin problema.

## Licencia

MIT
