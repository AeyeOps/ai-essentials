# Ghostty Session Launcher

Transparent tmux under Ghostty on Linux so a Ghostty crash is cheap to recover
from: every Ghostty surface (window, tab, native split) lands in its own tmux
session through a single fzf screen that names the new session, lists detached
sessions, and can pull selected detached sessions back in **as panes**.

## How it works

- A guard in your shell rc (`~/.zshrc`/`~/.bashrc`) `exec`s the launcher for any
  interactive Ghostty shell not already inside tmux — so it fires for new
  windows, tabs, and native `alt+d` splits, and no-ops everywhere else.
- The launcher shows **one fzf screen**:
  - The editable input line is pre-filled with a 3-word petname and **is** the
    new session's name — type to rename.
  - **Detached** sessions are listed (each row shows `Nw Np · cwd · when`).
    `Tab` marks them; marked sessions are pulled into your new window **as
    panes** (flattened and tiled), the selective form of tmux's `Prefix + P`.
  - **Active** sessions are shown dimmed and view-only — `Tab` is disabled on
    them (you can still preview their windows/panes).
  - `Enter` opens; `Esc` closes the surface.
- Native splits stay native (`alt+d` / `alt+shift+d`); each split is a new shell
  with `$TMUX` unset, so it gets its own recoverable session.

## Files

| File | Role |
|------|------|
| `ghostty-tmux-launch` | The launcher (zsh) — deployed to `~/.config/ghostty/` |
| `ghostty-tmux-launch.bash` | Bash port (deployed instead when zsh is absent) |
| `aeo-launcher.conf` | Split keybinds + desktop-gated decoration fix; included by the main config |
| `config.full` | Opinionated full config (Full option only) |
| `rc-snippet.zsh` / `rc-snippet.bash` | The rc guard + integration-source blocks the installer appends |

## Install options

The installer offers two ways to adopt the launcher.

### Integrate (additive — keeps your config)

Adds the launcher without rewriting your look/feel:

- Deploys the launcher.
- Appends `config-file = aeo-launcher.conf` to your existing
  `~/.config/ghostty/config` (creating a minimal one if absent).
- Appends the rc guard + integration blocks (marker-fenced, idempotent).
- Appends only the 3 Ghostty lines to your tmux config.

Because a Ghostty `config-file` include **overrides the parent config on
conflict**, this still changes these keys if you already set them:
`keybind = alt+d`, `keybind = alt+shift+d`, and, when needed, Ghostty
decoration keys (`window-decoration`, plus `gtk-titlebar` on Plasma/KWin).
Everything else — theme, font, colors — is untouched.

**Revert:** delete the marker-fenced blocks from your rc files and remove the
`config-file = aeo-launcher.conf` line from your Ghostty config. Nothing was
overwritten.

### Full AEO (opinionated — replaces config)

Installs the curated AEO experience as a bundle (AEO tmux + AEO Ghostty config +
launcher). This **replaces** `~/.config/tmux/tmux.conf` and overwrites the
AEO-managed Ghostty config (theme TokyoNight Night, OLED-black background,
font-size 9, scroll multiplier, the split keybinds, and the decoration fix).

Before any write, the installer prints exactly which files it will replace, makes
a timestamped backup of each (`*.bak.<stamp>`), and generates a
`restore-<stamp>.sh` that puts the backups back and strips the rc blocks — a
one-command rollback whose path is shown before you confirm.

**Revert:** run the `restore-<stamp>.sh` printed at install time. With more than
one install, use the most recent one.

## Decoration mouse-offset fix

Ghostty's GTK client-side-decoration shadow margins can desync the mouse→cell
mapping, so clicks and text selection can drift by both columns and rows. On
Plasma/KWin, the least-invasive fix is `window-decoration = server` plus
`gtk-titlebar = false`: KWin owns the resize frame/titlebar and Ghostty does not
add GTK CSD extents.

For tiling WMs without usable server-side decorations, the installer can enable
the borderless fallback `window-decoration = none`. That fallback zeroes frame
extents, but it also removes all window decorations, so Plasma/KWin does not use
it. To diagnose by hand, run `xprop _GTK_FRAME_EXTENTS` and click the Ghostty
window: nonzero left/top values are the horizontal/vertical offsets, in pixels
(roughly one cell per column/row of drift).

## Requirements

- Ghostty, tmux 3.4+, and a tmux config with the `xterm-ghostty` terminfo entry
  (ncurses 6.5-20241228+). On a remote host without it:
  `infocmp -x xterm-ghostty | ssh HOST -- tic -x -`.
- `fzf` **0.45+** — the conditional `Tab` (mark detached only) uses fzf's
  `transform` action. Older fzf degrades to a plain `Tab` with no error. The
  installer pins the resolved fzf path in the rc guard so the right binary is
  used even before your rc edits `PATH`.
- zsh and/or bash (the launcher runs under its own shebang regardless of which
  shell `exec`s it).
