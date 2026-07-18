use crate::cache::AudioCache;
use crate::models::{
    CollectionSummary, CollectionType, PlaybackRecord, Profile, QrLoginChallenge, QrLoginCheck,
    SavedPosition, Session, Track,
};
use crate::netease::{NeteaseClient, QrLoginStatus};
use crate::store::Store;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

struct App {
    api: NeteaseClient,
    login_api: NeteaseClient,
    store: Store,
    audio: AudioCache,
    revision: Mutex<u64>,
}

static APP: OnceLock<Arc<App>> = OnceLock::new();

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryResult {
    pub items: Vec<CollectionSummary>,
    pub from_cache: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TracksResult {
    pub items: Vec<Track>,
    pub from_cache: bool,
}

pub fn initialize(data_directory: String) -> Result<(), String> {
    let root = PathBuf::from(data_directory);
    let store = Store::open(root.join("state.json"))?;
    let api = NeteaseClient::new()?;
    if let Some(session) = store.session() {
        api.replace_cookies(session.cookies);
    }
    APP.set(Arc::new(App {
        api,
        login_api: NeteaseClient::new()?,
        store,
        audio: AudioCache::new(root.join("audio"))?,
        revision: Mutex::new(0),
    }))
    .map_err(|_| "Rust Core 已初始化".to_string())
}

pub async fn restore_session() -> Result<Option<Profile>, String> {
    let app = app()?;
    let Some(session) = app.store.session() else {
        return Ok(None);
    };
    app.api.replace_cookies(session.cookies);
    match app.api.profile().await {
        Ok(profile) => {
            let mut revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
            app.store.save_session(Session {
                profile: profile.clone(),
                cookies: app.api.cookies(),
            })?;
            *revision += 1;
            Ok(Some(profile))
        }
        Err(error) if error.starts_with("登录已失效") => {
            let mut revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
            app.api.clear_cookies();
            app.store.clear_session()?;
            *revision += 1;
            Ok(None)
        }
        Err(_) => Ok(Some(session.profile)),
    }
}

pub async fn send_login_code(phone: String, country_code: String) -> Result<(), String> {
    validate_phone(&phone, &country_code)?;
    app()?.login_api.send_captcha(&phone, &country_code).await
}

pub async fn login_with_code(
    phone: String,
    country_code: String,
    code: String,
) -> Result<Profile, String> {
    validate_phone(&phone, &country_code)?;
    if code.is_empty() || !code.bytes().all(|b| b.is_ascii_digit()) {
        return Err("请输入数字验证码".into());
    }
    let app = app()?;
    app.login_api
        .verify_and_login(&phone, &country_code, &code)
        .await?;
    complete_login(&app).await
}

pub async fn create_qr_login() -> Result<QrLoginChallenge, String> {
    app()?.login_api.create_qr_login().await
}

pub async fn check_qr_login(key: String) -> Result<QrLoginCheck, String> {
    if key.trim().is_empty() || key.len() > 256 {
        return Err("登录二维码 key 无效".into());
    }
    let app = app()?;
    let (status, profile) = match app.login_api.check_qr_login(&key).await? {
        QrLoginStatus::Expired => ("expired", None),
        QrLoginStatus::Waiting => ("waiting", None),
        QrLoginStatus::Scanned => ("scanned", None),
        QrLoginStatus::Confirmed => ("confirmed", Some(complete_login(&app).await?)),
    };
    Ok(QrLoginCheck {
        status: status.into(),
        profile,
    })
}

pub async fn get_library(category: String) -> Result<LibraryResult, String> {
    let app = app()?;
    let (session, revision) = session_snapshot(&app)?;
    let account = session.profile.id.clone();
    let kind = parse_collection_type(&category)?;
    if let Some(items) = app.store.load_library(&account, &category) {
        let refresh_app = app.clone();
        tokio::spawn(async move {
            let _ = refresh_library(refresh_app, session, revision, category, kind).await;
        });
        return Ok(LibraryResult {
            items,
            from_cache: true,
        });
    }
    let items = refresh_library(app, session, revision, category, kind).await?;
    Ok(LibraryResult {
        items,
        from_cache: false,
    })
}

pub async fn refresh_library_now(category: String) -> Result<Vec<CollectionSummary>, String> {
    let app = app()?;
    let (session, revision) = session_snapshot(&app)?;
    let kind = parse_collection_type(&category)?;
    refresh_library(app, session, revision, category, kind).await
}

pub async fn get_collection_tracks(
    collection_type: String,
    collection_id: String,
) -> Result<TracksResult, String> {
    let app = app()?;
    let (session, revision) = session_snapshot(&app)?;
    let account = session.profile.id.clone();
    let kind = parse_collection_type(&collection_type)?;
    let key = collection_key(&collection_type, &collection_id)?;
    if let Some(items) = app.store.load_tracks(&account, &key) {
        let refresh_app = app.clone();
        tokio::spawn(async move {
            let _ = refresh_tracks(refresh_app, session, revision, key, kind, collection_id).await;
        });
        return Ok(TracksResult {
            items,
            from_cache: true,
        });
    }
    let items = refresh_tracks(app, session, revision, key, kind, collection_id).await?;
    Ok(TracksResult {
        items,
        from_cache: false,
    })
}

pub async fn refresh_collection_tracks_now(
    collection_type: String,
    collection_id: String,
) -> Result<Vec<Track>, String> {
    let app = app()?;
    let (session, revision) = session_snapshot(&app)?;
    let kind = parse_collection_type(&collection_type)?;
    let key = collection_key(&collection_type, &collection_id)?;
    refresh_tracks(app, session, revision, key, kind, collection_id).await
}

pub async fn get_stream_url(collection_key: String, track_id: String) -> Result<String, String> {
    let app = app()?;
    let (session, revision) = session_snapshot(&app)?;
    validate_collection_key(&collection_key)?;
    let id = track_id
        .parse()
        .map_err(|_| format!("曲目 ID 无效：{track_id}"))?;
    let client = client_for_session(&session)?;
    expire_snapshot_if_needed(&app, &session, revision, client.resolve_stream(id).await)
}

pub fn save_playback_state(collection_key: String, position: SavedPosition) -> Result<(), String> {
    let app = app()?;
    validate_collection_key(&collection_key)?;
    let account = require_session(&app)?.profile.id;
    app.store.save_playback(&account, collection_key, position)
}

pub fn load_playback_state() -> Result<Vec<PlaybackRecord>, String> {
    let app = app()?;
    Ok(app
        .store
        .session()
        .map(|s| app.store.load_playback(&s.profile.id))
        .unwrap_or_default()
        .into_iter()
        .map(|(collection_key, position)| PlaybackRecord {
            collection_key,
            position,
        })
        .collect())
}

pub fn lookup_audio_cache(track_id: String) -> Result<Option<String>, String> {
    let app = app()?;
    let account = require_session(&app)?.profile.id;
    Ok(app
        .audio
        .lookup(&account, &track_id)
        .map(|p| p.to_string_lossy().into_owned()))
}

pub fn write_audio_cache(track_id: String, bytes: Vec<u8>) -> Result<String, String> {
    let app = app()?;
    let account = require_session(&app)?.profile.id;
    let _revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    app.audio
        .write(&account, &track_id, &bytes)
        .map(|p| p.to_string_lossy().into_owned())
}

pub async fn cache_audio_track(collection_key: String, track_id: String) -> Result<String, String> {
    let app = app()?;
    validate_collection_key(&collection_key)?;
    let (session, revision) = session_snapshot(&app)?;
    let account = session.profile.id.clone();
    if let Some(path) = app.audio.lookup(&account, &track_id) {
        return Ok(path.to_string_lossy().into_owned());
    }
    let id = track_id
        .parse()
        .map_err(|_| format!("曲目 ID 无效：{track_id}"))?;
    let client = client_for_session(&session)?;
    let url = expire_snapshot_if_needed(&app, &session, revision, client.resolve_stream(id).await)?;
    let response = reqwest::get(url)
        .await
        .map_err(|e| format!("下载音频失败：{e}"))?
        .error_for_status()
        .map_err(|e| format!("下载音频失败：{e}"))?;
    let bytes = response
        .bytes()
        .await
        .map_err(|e| format!("读取音频数据失败：{e}"))?;
    let current_revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    if *current_revision != revision || !app.store.session_matches(&session) {
        return Err("账号或缓存状态已变更".into());
    }
    app.audio
        .write(&account, &track_id, &bytes)
        .map(|path| path.to_string_lossy().into_owned())
}

pub fn audio_cache_size() -> Result<u64, String> {
    let app = app()?;
    let account = require_session(&app)?.profile.id;
    app.audio.size(&account)
}

pub fn clear_audio_cache() -> Result<(), String> {
    let app = app()?;
    let account = require_session(&app)?.profile.id;
    let mut revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    app.audio.clear(&account)?;
    *revision += 1;
    Ok(())
}

pub fn clear_media_cache() -> Result<(), String> {
    let app = app()?;
    let account = require_session(&app)?.profile.id;
    let mut revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    app.audio.clear(&account)?;
    app.store.clear_metadata_cache(&account)?;
    *revision += 1;
    Ok(())
}

pub fn logout() -> Result<(), String> {
    let app = app()?;
    let mut revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    app.api.clear_cookies();
    app.login_api.clear_cookies();
    app.store.clear_session()?;
    *revision += 1;
    Ok(())
}

async fn complete_login(app: &App) -> Result<Profile, String> {
    let cookies = app.login_api.cookies();
    if cookies.get("MUSIC_U").map_or(true, String::is_empty) {
        return Err("登录响应缺少 MUSIC_U Cookie".into());
    }
    app.api.replace_cookies(cookies);
    let profile = app.api.profile().await?;
    let mut revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    app.store.save_session(Session {
        profile: profile.clone(),
        cookies: app.api.cookies(),
    })?;
    *revision += 1;
    Ok(profile)
}

async fn refresh_library(
    app: Arc<App>,
    session: Session,
    revision: u64,
    category: String,
    kind: CollectionType,
) -> Result<Vec<CollectionSummary>, String> {
    let profile_id = session
        .profile
        .id
        .parse()
        .map_err(|_| "当前账号 ID 无效".to_string())?;
    let client = client_for_session(&session)?;
    let items = expire_snapshot_if_needed(
        &app,
        &session,
        revision,
        client.library_category(kind, profile_id).await,
    )?;
    let current_revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    if *current_revision != revision || !app.store.session_matches(&session) {
        return Err("账号或缓存状态已变更".into());
    }
    app.store
        .save_library(&session.profile.id, &category, items.clone())?;
    Ok(items)
}

async fn refresh_tracks(
    app: Arc<App>,
    session: Session,
    revision: u64,
    key: String,
    kind: CollectionType,
    id: String,
) -> Result<Vec<Track>, String> {
    let summary = CollectionSummary {
        id,
        collection_type: kind,
        title: String::new(),
        subtitle: String::new(),
        cover_url: String::new(),
        track_count: None,
    };
    let client = client_for_session(&session)?;
    let items = expire_snapshot_if_needed(
        &app,
        &session,
        revision,
        client.load_collection(summary).await,
    )?;
    let current_revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    if *current_revision != revision || !app.store.session_matches(&session) {
        return Err("账号或缓存状态已变更".into());
    }
    app.store
        .save_tracks(&session.profile.id, &key, items.clone())?;
    Ok(items)
}

fn app() -> Result<Arc<App>, String> {
    APP.get()
        .cloned()
        .ok_or_else(|| "Rust Core 尚未初始化".into())
}
fn require_session(app: &App) -> Result<Session, String> {
    app.store
        .session()
        .ok_or_else(|| "尚未登录网易云音乐".into())
}
fn session_snapshot(app: &App) -> Result<(Session, u64), String> {
    let revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
    Ok((require_session(app)?, *revision))
}
fn client_for_session(session: &Session) -> Result<NeteaseClient, String> {
    let client = NeteaseClient::new()?;
    client.replace_cookies(session.cookies.clone());
    Ok(client)
}
fn expire_snapshot_if_needed<T>(
    app: &App,
    session: &Session,
    revision: u64,
    result: Result<T, String>,
) -> Result<T, String> {
    if matches!(&result, Err(error) if error.contains("登录已失效")) {
        let mut current_revision = app.revision.lock().map_err(|_| "会话锁已损坏")?;
        if *current_revision == revision && app.store.clear_session_if_matches(session)? {
            app.api.clear_cookies();
            *current_revision += 1;
        }
    }
    result
}
fn parse_collection_type(raw: &str) -> Result<CollectionType, String> {
    match raw {
        "album" => Ok(CollectionType::Album),
        "playlist" => Ok(CollectionType::Playlist),
        "podcast" => Ok(CollectionType::Podcast),
        _ => Err(format!("不支持的集合类型：{raw}")),
    }
}
fn collection_key(kind: &str, id: &str) -> Result<String, String> {
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
        return Err(format!("集合 ID 无效：{id}"));
    }
    Ok(format!("{kind}:{id}"))
}
fn validate_collection_key(key: &str) -> Result<(), String> {
    let Some((kind, id)) = key.split_once(':') else {
        return Err("集合标识无效".into());
    };
    parse_collection_type(kind)?;
    collection_key(kind, id).map(|_| ())
}
fn validate_phone(phone: &str, country_code: &str) -> Result<(), String> {
    if !(6..=20).contains(&phone.len()) || !phone.bytes().all(|b| b.is_ascii_digit()) {
        return Err("请输入有效手机号".into());
    }
    if country_code.is_empty()
        || country_code.len() > 4
        || !country_code.bytes().all(|b| b.is_ascii_digit())
    {
        return Err("请输入有效国家或地区代码".into());
    }
    Ok(())
}
