mod commands;
mod crypto;
mod models;
mod netease;
mod store;

#[cfg(test)]
mod tests;

use commands::AppState;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let path = app.path().app_data_dir()?.join("state.json");
            let state = AppState::new(path).map_err(std::io::Error::other)?;
            app.manage(state);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::restore_session,
            commands::send_login_code,
            commands::login_with_code,
            commands::create_qr_login,
            commands::check_qr_login,
            commands::get_library,
            commands::get_collection_tracks,
            commands::get_stream_url,
            commands::save_playback_state,
            commands::load_playback_state,
            commands::logout,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
