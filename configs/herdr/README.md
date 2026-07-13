# Herdr

Agent multiplexer (herdr.dev) config for the AI dev stack: tmux-safe prefix,
tokyo-night on pure-black panels, system-notification toasts, and full
session/pane persistence across server restarts.

`scripts/setup-ai-dev-stack.sh` (section 7b) deploys all of this — binary,
config, integrations, agent skill, plugins, completions, DISPLAY fallback —
with an md5 pre-check that silently skips when current. The steps below are
the manual equivalent.

## Files

| File | Role |
|------|------|
| `config.toml` | Deployed to `~/.config/herdr/config.toml` |
| `zshenv-display-snippet.zsh` | `.zshenv` block — derives `DISPLAY` for panes when unset (GUI tools inside herdr otherwise lack it) |

## Install

```sh
curl -fsSL https://herdr.dev/install.sh | sh
mkdir -p ~/.config/herdr && cp config.toml ~/.config/herdr/config.toml

# hook-based agent state detection (per machine — hooks embed absolute paths)
herdr integration install claude
herdr integration install pi
herdr integration install codex
herdr integration install opencode

# lets agents drive herdr panes via its socket API (self-gates on HERDR_ENV=1)
npx -y skills add ogulcancelik/herdr --skill herdr -g

# plugins
herdr plugin install cloudmanic/herdr-plus --yes
herdr plugin install smarzban/herdr-file-viewer --yes   # builds from source, needs rustc >= 1.96
herdr plugin install yuk1ty/herdr-spreader --yes

# zsh completions — fpath dir must be added BEFORE the shell's single compinit
mkdir -p ~/.zsh/completions && herdr completion zsh > ~/.zsh/completions/_herdr
```

Reload config into a running server: `herdr server reload-config`.

## Notes

- Never run tmux/zellij *inside* a herdr pane — it breaks agent state
  detection. herdr inside tmux works; the `ctrl+a` prefix avoids tmux's
  `ctrl+b`.
- `pane_history = true` writes pane scrollback to disk under
  `~/.config/herdr/` — secrets printed in terminals persist across restarts.
  Set it `false` on shared or sensitive hosts.
- Integrations write machine-specific absolute paths into agent settings
  (e.g. `~/.claude/settings.json`) — rerun `herdr integration install` per
  machine; never sync those files across hosts.
- No grok integration exists as of herdr 0.7.3; grok runs as a plain pane.
- Remote attach from another mesh node: `herdr --remote ssh://<user>@<ip>`.
