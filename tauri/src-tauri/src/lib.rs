use std::collections::HashMap;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, WindowEvent,
};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

mod convert;

// ── Shortcut registry ─────────────────────────────────────────────────────────
// Tracks profile_id → registered shortcut string so the old one can be
// unregistered automatically when the user assigns a new shortcut.

struct ShortcutRegistry(Mutex<HashMap<String, String>>);

// ── Live conversion config (pushed from JS on every settings change) ──────────

#[derive(Debug, Clone, serde::Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct TsvProfile {
    id:   String,
    tmpl: String,
    #[serde(default = "default_skip")]
    skip: String,
    #[serde(default)]
    trim_leading: bool,
}
fn default_skip() -> String { "referenced".to_string() }

#[derive(Debug, Default)]
struct ActiveConfig {
    flex_opts:    convert::FlexOpts,
    tsv_profiles: Vec<TsvProfile>,
}

struct AppState(Mutex<ActiveConfig>);

// ── Shortcut string normalisation ─────────────────────────────────────────────
// Converts our popup.js format ("Ctrl+Shift+1") to the format expected by
// tauri-plugin-global-shortcut ("super+shift+Digit1" on macOS,
// "ctrl+shift+Digit1" on Windows/Linux).
//
// popup.js maps Cmd → "Ctrl" on macOS (using e.metaKey), so we map "Ctrl"
// back to "super" on macOS so the same key combo is registered correctly.

fn normalize_shortcut(s: &str) -> String {
    s.split('+')
        .map(|part| match part.to_uppercase().as_str() {
            "CTRL" | "CONTROL" => {
                if cfg!(target_os = "macos") { "super".to_string() }
                else { "ctrl".to_string() }
            }
            "SHIFT"          => "shift".to_string(),
            "ALT"            => "alt".to_string(),
            "META" | "SUPER" => "super".to_string(),
            // Single ASCII letter → KeyA, KeyB, …
            key if key.len() == 1
                && key.chars().next().map_or(false, |c| c.is_ascii_alphabetic()) =>
            {
                format!("Key{}", key.to_uppercase())
            }
            // Single ASCII digit → Digit1, Digit2, …
            key if key.len() == 1
                && key.chars().next().map_or(false, |c| c.is_ascii_digit()) =>
            {
                format!("Digit{}", key)
            }
            // F1–F12, Space, Enter, Escape, Tab, etc. — pass through unchanged
            key => key.to_string(),
        })
        .collect::<Vec<_>>()
        .join("+")
}

// ── Conversion helpers ────────────────────────────────────────────────────────

/// Convert `text` using the config for `profile_id`.
/// Returns `None` if the config is missing, the text is empty, or conversion
/// produces no output.
fn convert_for_profile(profile_id: &str, text: &str, cfg: &ActiveConfig) -> Option<String> {
    if text.trim().is_empty() { return None; }

    if profile_id == "flex" {
        let blocks = convert::parse_flex_blocks(text);
        if blocks.is_empty() { return None; }
        let result = convert::render_flex_auto(&blocks, &cfg.flex_opts);
        if result.trim().is_empty() { return None; }
        Some(result)
    } else if profile_id == "flex-tsv" {
        let blocks = convert::parse_flex_blocks(text);
        if blocks.is_empty() { return None; }
        let result = convert::render_flex_tsv_auto(&blocks, &cfg.flex_opts);
        if result.trim().is_empty() { return None; }
        Some(result)
    } else {
        let profile = cfg.tsv_profiles.iter().find(|p| p.id == profile_id)?;
        let used_cols = if profile.skip == "referenced" {
            convert::referenced_cols(&profile.tmpl)
        } else {
            vec![]
        };

        let results: Vec<String> = text
            .lines()
            .filter(|l| !l.trim().is_empty())
            .filter_map(|line| {
                let mut fields = convert::parse_tsv_row(line);
                if profile.trim_leading {
                    if fields.len() >= 2 && fields[0].is_empty() && fields[1].is_empty() {
                        fields.remove(0);
                    }
                }
                if profile.skip == "referenced" && !used_cols.is_empty() {
                    let any_empty = used_cols.iter().any(|&n| {
                        fields.get(n.saturating_sub(1)).map_or(true, |f| f.is_empty())
                    });
                    if any_empty { return None; }
                }
                if profile.skip == "col1" && fields.first().map_or(true, |f| f.is_empty()) {
                    return None;
                }
                Some(convert::apply_row_template(&profile.tmpl, &fields))
            })
            .collect();

        if results.is_empty() { None } else { Some(results.join("\n")) }
    }
}

/// Type `text` directly at the current cursor position using enigo's virtual
/// keyboard, without touching the clipboard at all.
///
/// A 150 ms pause lets the triggering shortcut keys fully release before we
/// start typing, preventing modifier bleed.
/// On macOS this requires Accessibility permission:
/// System Settings → Privacy & Security → Accessibility.
///
/// On Windows, enigo accepts \r\n in a single text() call, so we inject the
/// whole block at once. On macOS/Linux, we split on \n and press Key::Return
/// between segments, which is required for newlines to register correctly.
fn type_text(text: &str) {
    use enigo::{Direction, Enigo, Key, Keyboard, Settings};

    thread::sleep(Duration::from_millis(150));
    if let Ok(mut en) = Enigo::new(&Settings::default()) {
        #[cfg(target_os = "windows")]
        {
            let windows_text = text.replace('\n', "\r\n");
            let _ = en.text(&windows_text);
        }

        #[cfg(not(target_os = "windows"))]
        for (i, segment) in text.split('\n').enumerate() {
            if i > 0 {
                let _ = en.key(Key::Return, Direction::Click);
            }
            if !segment.is_empty() {
                let _ = en.text(segment);
            }
        }
    }
}

// ── Tauri commands ────────────────────────────────────────────────────────────

/// Write text to the system clipboard. Called from the frontend via invoke().
#[tauri::command]
fn write_clipboard(text: String) -> Result<(), String> {
    let mut cb = arboard::Clipboard::new().map_err(|e| e.to_string())?;
    cb.set_text(text).map_err(|e| e.to_string())?;
    Ok(())
}

/// Push the current settings (FLEx opts + TSV profiles) from the frontend into
/// the Rust AppState so that global shortcut handlers can convert without the
/// webview being active.  Call this whenever settings change.
#[tauri::command]
fn sync_config(
    state:        tauri::State<AppState>,
    flex_opts:    convert::FlexOpts,
    tsv_profiles: Vec<TsvProfile>,
) -> Result<(), String> {
    let mut cfg = state.0.lock().unwrap();
    cfg.flex_opts    = flex_opts;
    cfg.tsv_profiles = tsv_profiles;
    Ok(())
}

/// Register a global OS shortcut for a profile.
/// When the shortcut fires the Rust backend reads the clipboard, converts it,
/// writes the result back, simulates a Cmd/Ctrl+V paste, then emits a
/// "profile-shortcut" event so the frontend can update its status display.
/// Passing an empty shortcut_str unregisters any existing shortcut for that profile.
#[tauri::command]
fn register_profile_shortcut(
    app:          AppHandle,
    registry:     tauri::State<ShortcutRegistry>,
    profile_id:   String,
    shortcut_str: String,
) -> Result<(), String> {
    let mut map = registry.0.lock().unwrap();

    // Unregister the old shortcut for this profile (if any)
    if let Some(old) = map.get(&profile_id) {
        let old_norm = normalize_shortcut(old);
        let _ = app.global_shortcut().unregister(old_norm.as_str());
    }
    map.remove(&profile_id);

    if shortcut_str.is_empty() {
        return Ok(());
    }

    let normalized = normalize_shortcut(&shortcut_str);
    let pid = profile_id.clone();

    app.global_shortcut()
        .on_shortcut(normalized.as_str(), move |app, _sc, event| {
            if event.state != ShortcutState::Pressed { return; }

            let app_state = app.state::<AppState>();
            let mut cb = match arboard::Clipboard::new() {
                Ok(c)  => c,
                Err(_) => return,
            };
            let text = match cb.get_text() {
                Ok(t) if !t.trim().is_empty() => t,
                _ => return,
            };

            // Convert in Rust — works even when the webview is hidden/throttled
            let cfg       = app_state.0.lock().unwrap();
            let converted = convert_for_profile(&pid, &text, &cfg);
            drop(cfg);

            drop(cb); // done reading clipboard

            if let Some(out) = converted {
                thread::spawn(move || type_text(&out));
                let _ = app.emit("profile-shortcut", serde_json::json!({
                    "profileId": &pid
                }));
            }
        })
        .map_err(|e| e.to_string())?;

    map.insert(profile_id, shortcut_str);
    Ok(())
}

// ── App entry point ───────────────────────────────────────────────────────────

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(ShortcutRegistry(Mutex::new(HashMap::new())))
        .manage(AppState(Mutex::new(ActiveConfig::default())))
        .setup(|app| {
            // ── System tray ────────────────────────────────────────────────────
            let show = MenuItem::with_id(app, "show", "Show LingTeX Tools", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit",               true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;

            // Use the small [ŋ] sidebar icon for the tray/menu-bar slot.
            // The large [liŋtɛx] icon is used for the app bundle (Dock, Finder, taskbar).
            let tray_image = tauri::include_image!("icons/tray-icon.png");

            TrayIconBuilder::new()
                .icon(tray_image)
                .menu(&menu)
                .tooltip("LingTeX Tools")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => show_window(app),
                    "quit" => app.exit(0),
                    _      => {}
                })
                .show_menu_on_left_click(false)
                .on_tray_icon_event(|tray, event| {
                    // Only respond to left-click release — Windows fires both
                    // Press and Release as separate Click events, so filtering
                    // to Up avoids the window flashing on and off.
                    if let TrayIconEvent::Click {
                        button:       MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event {
                        let app = tray.app_handle();
                        if let Some(win) = app.get_webview_window("main") {
                            if win.is_visible().unwrap_or(false) {
                                let _ = win.hide();
                            } else {
                                show_window(app);
                            }
                        }
                    }
                })
                .build(app)?;

            // ── Hide to tray on window close ───────────────────────────────────
            let win = app.get_webview_window("main").unwrap();
            let win_for_close = win.clone();
            win.on_window_event(move |event| {
                if let WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = win_for_close.hide();
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            write_clipboard,
            register_profile_shortcut,
            sync_config,
        ])
        .run(tauri::generate_context!())
        .expect("error running LingTeX Tools");
}

fn show_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.set_focus();
    }
}
