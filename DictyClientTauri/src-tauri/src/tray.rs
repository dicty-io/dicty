use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager,
};

pub fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let toggle_record = MenuItem::with_id(app, "toggle_record", "Start / Stop Dictation", true, None::<&str>)?;
    let open_main = MenuItem::with_id(app, "open_main", "Open Dicty Studio...", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Dicty", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&toggle_record, &open_main, &quit])?;

    let mut builder = TrayIconBuilder::new()
        .menu(&menu)
        .show_menu_on_left_click(true)
        .tooltip("Dicty AI Voice Assistant");

    // High-resolution anti-aliased 64x64 RGBA icon buffer for high-DPI Windows tray
    const TRAY_RGBA_64: &[u8] = include_bytes!("../icons/tray-icon-64.rgba");
    let tray_image = tauri::image::Image::new(TRAY_RGBA_64, 64, 64);
    builder = builder.icon(tray_image);

    let tray = builder
        .on_menu_event(|app, event| match event.id.as_ref() {
            "toggle_record" => {
                let _ = app.emit("dicty:toggle-recording", ());
            }
            "open_main" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.unminimize();
                    let _ = window.set_focus();
                }
            }
            "quit" => {
                let state = app.state::<crate::engine::EngineState>();
                crate::engine::stop_engine(&state);
                std::process::exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::DoubleClick {
                button: MouseButton::Left,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.unminimize();
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)?;

    // Keep the tray icon alive so it is never dropped
    app.manage(tray);

    Ok(())
}
