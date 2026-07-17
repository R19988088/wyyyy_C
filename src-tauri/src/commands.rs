use crate::models::{
    CollectionSummary, CollectionType, Profile, QrLoginChallenge, QrLoginCheck, SavedPosition,
    Session, Track,
};
use crate::netease::{NeteaseClient, QrLoginStatus};
use crate::store::Store;
use std::collections::BTreeMap;
use std::path::PathBuf;
use tauri::State;

pub struct AppState {
    api: NeteaseClient,
    login_api: NeteaseClient,
    store: Store,
}

impl AppState {
    pub(crate) fn new(path: PathBuf) -> Result<Self, String> {
        let store = Store::open(path)?;
        let api = NeteaseClient::new()?;
        if let Some(session) = store.session() {
            api.replace_cookies(session.cookies);
        }
        Ok(Self {
            api,
            login_api: NeteaseClient::new()?,
            store,
        })
    }
}

#[tauri::command]
pub async fn restore_session(state: State<'_, AppState>) -> Result<Option<Profile>, String> {
    let Some(session) = state.store.session() else {
        return Ok(None);
    };
    state.api.replace_cookies(session.cookies);
    match state.api.profile().await {
        Ok(profile) => {
            state.store.save_session(Session {
                profile: profile.clone(),
                cookies: state.api.cookies(),
            })?;
            Ok(Some(profile))
        }
        Err(error) if error.starts_with("登录已失效") => {
            state.api.clear_cookies();
            state.store.clear_session()?;
            Ok(None)
        }
        Err(error) => Err(error),
    }
}

#[tauri::command]
pub async fn send_login_code(
    phone: String,
    country_code: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    validate_phone(&phone, &country_code)?;
    state.login_api.send_captcha(&phone, &country_code).await
}

#[tauri::command]
pub async fn login_with_code(
    phone: String,
    country_code: String,
    code: String,
    state: State<'_, AppState>,
) -> Result<Profile, String> {
    validate_phone(&phone, &country_code)?;
    if code.trim().is_empty() || !code.chars().all(|character| character.is_ascii_digit()) {
        return Err("请输入数字验证码".into());
    }
    state
        .login_api
        .verify_and_login(&phone, &country_code, &code)
        .await?;
    complete_login(&state).await
}

#[tauri::command]
pub async fn create_qr_login(state: State<'_, AppState>) -> Result<QrLoginChallenge, String> {
    state.login_api.create_qr_login().await
}

#[tauri::command]
pub async fn check_qr_login(
    key: String,
    state: State<'_, AppState>,
) -> Result<QrLoginCheck, String> {
    if key.trim().is_empty() || key.len() > 256 {
        return Err("登录二维码 key 无效".into());
    }
    let status = state.login_api.check_qr_login(&key).await?;
    match status {
        QrLoginStatus::Expired => Ok(QrLoginCheck {
            status: "expired".into(),
            profile: None,
        }),
        QrLoginStatus::Waiting => Ok(QrLoginCheck {
            status: "waiting".into(),
            profile: None,
        }),
        QrLoginStatus::Scanned => Ok(QrLoginCheck {
            status: "scanned".into(),
            profile: None,
        }),
        QrLoginStatus::Confirmed => Ok(QrLoginCheck {
            status: "confirmed".into(),
            profile: Some(complete_login(&state).await?),
        }),
    }
}

async fn complete_login(state: &State<'_, AppState>) -> Result<Profile, String> {
    let cookies = state.login_api.cookies();
    if cookies.get("MUSIC_U").map_or(true, String::is_empty) {
        return Err("登录响应缺少 MUSIC_U Cookie".into());
    }
    state.api.replace_cookies(cookies);
    let profile = state.api.profile().await?;
    state.store.save_session(Session {
        profile: profile.clone(),
        cookies: state.api.cookies(),
    })?;
    Ok(profile)
}

#[tauri::command]
pub async fn get_library(
    category: String,
    state: State<'_, AppState>,
) -> Result<Vec<CollectionSummary>, String> {
    let session = require_session(&state.store)?;
    let profile_id = session
        .profile
        .id
        .parse::<u64>()
        .map_err(|_| "当前账号 ID 无效".to_string())?;
    let result = state
        .api
        .library_category(parse_collection_type(&category)?, profile_id)
        .await;
    expire_session_if_needed(&state, result)
}

#[tauri::command]
pub async fn get_collection_tracks(
    collection_type: String,
    collection_id: String,
    state: State<'_, AppState>,
) -> Result<Vec<Track>, String> {
    require_session(&state.store)?;
    let collection = CollectionSummary {
        id: collection_id,
        collection_type: parse_collection_type(&collection_type)?,
        title: String::new(),
        subtitle: String::new(),
        cover_url: String::new(),
        track_count: None,
    };
    let result = state.api.load_collection(collection).await;
    expire_session_if_needed(&state, result)
}

#[tauri::command]
pub async fn get_stream_url(
    collection_key: String,
    track_id: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    require_session(&state.store)?;
    if !collection_key.contains(':') {
        return Err("集合标识无效".into());
    }
    let id = track_id
        .parse::<u64>()
        .map_err(|_| format!("曲目 ID 无效：{track_id}"))?;
    let result = state.api.resolve_stream(id).await;
    expire_session_if_needed(&state, result)
}

#[tauri::command]
pub fn save_playback_state(
    collection_key: String,
    position: SavedPosition,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let session = require_session(&state.store)?;
    state
        .store
        .save_playback(&session.profile.id, collection_key, position)
}

#[tauri::command]
pub fn load_playback_state(
    state: State<'_, AppState>,
) -> Result<BTreeMap<String, SavedPosition>, String> {
    Ok(state
        .store
        .session()
        .map(|session| state.store.load_playback(&session.profile.id))
        .unwrap_or_default())
}

#[tauri::command]
pub fn logout(state: State<'_, AppState>) -> Result<(), String> {
    state.api.clear_cookies();
    state.login_api.clear_cookies();
    state.store.clear_session()
}

fn require_session(store: &Store) -> Result<Session, String> {
    store.session().ok_or_else(|| "尚未登录网易云音乐".into())
}

fn expire_session_if_needed<T>(
    state: &State<'_, AppState>,
    result: Result<T, String>,
) -> Result<T, String> {
    match result {
        Err(error) if error.contains("登录已失效") => {
            state.api.clear_cookies();
            state.store.clear_session()?;
            Err(error)
        }
        other => other,
    }
}

fn parse_collection_type(raw: &str) -> Result<CollectionType, String> {
    match raw {
        "album" => Ok(CollectionType::Album),
        "playlist" => Ok(CollectionType::Playlist),
        "podcast" => Ok(CollectionType::Podcast),
        _ => Err(format!("不支持的集合类型：{raw}")),
    }
}

fn validate_phone(phone: &str, country_code: &str) -> Result<(), String> {
    if !(6..=20).contains(&phone.len())
        || !phone.chars().all(|character| character.is_ascii_digit())
    {
        return Err("请输入有效手机号".into());
    }
    if country_code.is_empty()
        || country_code.len() > 4
        || !country_code
            .chars()
            .all(|character| character.is_ascii_digit())
    {
        return Err("请输入有效国家或地区代码".into());
    }
    Ok(())
}
