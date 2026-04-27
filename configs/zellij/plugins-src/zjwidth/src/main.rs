// zjwidth — width-aware sidecar for zjstatus.
//
// Watches PaneUpdate, finds the zjstatus alt-bar pane (matched by plugin_url
// containing "zjstatus.wasm"), bins its pane_columns into a tier, and pipes a
// tier-appropriate format string to that pane via pipe_message_to_plugin.
// zjstatus's `format_left = "{pipe_altbar}"` consumes the piped content with
// `pipe_altbar_rendermode "dynamic"` so the SGR markup in the format string is
// honored.
//
// Why a sidecar: zjstatus has no internal width clamp and never emits cursor
// positioning between renders, so any format string longer than `cols` wraps
// inside the 1-row pane and scrolls the bar — the "spiral". The fix has to
// keep emitted bytes <= cols. zjstatus's render() doesn't expose pane width to
// format strings, so the only way to get width-aware content is to compute it
// in another plugin and pipe it in.
//
// Layout requirements:
//   - zjstatus's `format_left "{pipe_altbar}"` (and matching format_center/right "")
//   - `pipe_altbar_format "{output}"`, `pipe_altbar_rendermode "dynamic"`
//   - zjwidth loaded as a background plugin via `load_plugins`

use std::collections::BTreeMap;
use zellij_tile::prelude::*;

#[derive(Default)]
struct State {
    last_tier: Option<u8>,
    last_pid: Option<u32>,
}

register_plugin!(State);

const PALETTE_BG_PAGE: &str = "#1C1C1C";
const PALETTE_BG_TILE: &str = "#32291B";
const PALETTE_KEY: &str = "#00B3B3";
const PALETTE_LBL: &str = "#5A5A5A";

fn key_section(key: &str, label: &str) -> String {
    format!(
        "#[fg={bg_page},bg={bg_tile}]#[fg={lbl},bg={bg_tile}] #[fg={key_color},bg={bg_tile},bold]{key}#[fg={lbl},bg={bg_tile}]#[fg={lbl},bg={bg_tile},bold] {label} #[fg={bg_tile},bg={bg_page}]",
        bg_page = PALETTE_BG_PAGE,
        bg_tile = PALETTE_BG_TILE,
        lbl = PALETTE_LBL,
        key_color = PALETTE_KEY,
        key = key,
        label = label,
    )
}

fn build_format(sections: &[(&str, &str)]) -> String {
    let mut s = format!(
        "#[fg={lbl},bg={bg},bold] Alt + ",
        lbl = PALETTE_LBL,
        bg = PALETTE_BG_PAGE,
    );
    for (key, label) in sections {
        s.push_str(&key_section(key, label));
    }
    s
}

fn pick_tier_and_format(cols: usize) -> (u8, String) {
    let full: &[(&str, &str)] = &[
        ("\u{2190}\u{2191}\u{2193}\u{2192}", "FOCUS"),
        ("n", "NEW"),
        ("f", "FLOAT"),
        ("p", "GROUP"),
        ("+", "GROW"),
        ("-", "SHRNK"),
        ("[/]", "LAYOUT"),
        ("i/o", "MOVE TAB"),
        ("w", "WINCH"),
    ];
    let t4: &[(&str, &str)] = &[
        ("\u{2190}\u{2191}\u{2193}\u{2192}", "FOCUS"),
        ("n", "NEW"),
        ("f", "FLOAT"),
        ("p", "GROUP"),
        ("+", "GROW"),
        ("-", "SHRNK"),
        ("[/]", "LAYOUT"),
        ("w", "WINCH"),
    ];
    let t3: &[(&str, &str)] = &[
        ("\u{2190}\u{2191}\u{2193}\u{2192}", "FOCUS"),
        ("n", "NEW"),
        ("f", "FLOAT"),
        ("+", "GROW"),
        ("-", "SHRNK"),
    ];
    let t2: &[(&str, &str)] = &[
        ("\u{2190}\u{2191}\u{2193}\u{2192}", "FOCUS"),
        ("n", "NEW"),
        ("f", "FLOAT"),
    ];
    let t1: &[(&str, &str)] = &[
        ("\u{2190}\u{2191}\u{2193}\u{2192}", "FOCUS"),
    ];
    let t0_str = format!(
        "#[fg={lbl},bg={bg},bold] Alt+\u{2026} ",
        lbl = PALETTE_LBL,
        bg = PALETTE_BG_PAGE,
    );

    if cols >= 144 {
        (5, build_format(full))
    } else if cols >= 120 {
        (4, build_format(t4))
    } else if cols >= 80 {
        (3, build_format(t3))
    } else if cols >= 50 {
        (2, build_format(t2))
    } else if cols >= 28 {
        (1, build_format(t1))
    } else {
        (0, t0_str)
    }
}

fn find_zjstatus_pane(manifest: &PaneManifest) -> Option<(u32, String, usize)> {
    for panes in manifest.panes.values() {
        for p in panes {
            if !p.is_plugin || p.is_floating || p.is_suppressed {
                continue;
            }
            if let Some(url) = p.plugin_url.as_deref() {
                if url.contains("zjstatus.wasm") {
                    return Some((p.id, url.to_string(), p.pane_columns));
                }
            }
        }
    }
    None
}

fn send_pipe(plugin_id: u32, plugin_url: &str, format: &str) {
    let payload = format!("zjstatus::pipe::pipe_altbar::{}", format);
    pipe_message_to_plugin(
        MessageToPlugin::new("zjstatus_altbar")
            .with_plugin_url(plugin_url)
            .with_destination_plugin_id(plugin_id)
            .with_payload(payload),
    );
}

impl ZellijPlugin for State {
    fn load(&mut self, _config: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::MessageAndLaunchOtherPlugins,
        ]);
        subscribe(&[EventType::PaneUpdate, EventType::PermissionRequestResult]);
    }

    fn update(&mut self, event: Event) -> bool {
        if let Event::PaneUpdate(manifest) = event {
            if let Some((pid, url, cols)) = find_zjstatus_pane(&manifest) {
                let (tier, fmt) = pick_tier_and_format(cols);
                let pid_changed = self.last_pid != Some(pid);
                if Some(tier) != self.last_tier || pid_changed {
                    self.last_tier = Some(tier);
                    self.last_pid = Some(pid);
                    send_pipe(pid, &url, &fmt);
                }
            }
        }
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {}
}
