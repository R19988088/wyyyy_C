use crate::crypto::{eapi_encrypt, weapi_encrypt};
use crate::models::{CollectionSummary, CollectionType, Profile, QrLoginChallenge, Track};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use qrcode::render::svg;
use qrcode::QrCode;
use reqwest::header::{HeaderMap, ACCEPT, ACCEPT_LANGUAGE, COOKIE, REFERER, SET_COOKIE};
use reqwest::{Client, RequestBuilder, Url};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap};
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 10; wyyyy) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum QrLoginStatus {
    Expired,
    Waiting,
    Scanned,
    Confirmed,
}

pub(crate) struct NeteaseClient {
    http: Client,
    cookies: Mutex<BTreeMap<String, String>>,
    qr_login_key: tokio::sync::Mutex<Option<String>>,
    device_id: String,
}

impl NeteaseClient {
    pub(crate) fn new() -> Result<Self, String> {
        let http = Client::builder()
            .user_agent(USER_AGENT)
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|error| format!("创建网络客户端失败：{error}"))?;
        Ok(Self {
            http,
            cookies: Mutex::new(BTreeMap::new()),
            qr_login_key: tokio::sync::Mutex::new(None),
            device_id: random_hex(16),
        })
    }

    pub(crate) fn replace_cookies(&self, cookies: BTreeMap<String, String>) {
        *self.cookies.lock().expect("cookie lock poisoned") = cookies;
    }

    pub(crate) fn clear_cookies(&self) {
        self.cookies.lock().expect("cookie lock poisoned").clear();
    }

    pub(crate) fn cookies(&self) -> BTreeMap<String, String> {
        let mut cookies = self.cookies.lock().expect("cookie lock poisoned").clone();
        cookies
            .entry("deviceId".into())
            .or_insert_with(|| self.device_id.clone());
        cookies.entry("os".into()).or_insert_with(|| "pc".into());
        cookies
            .entry("appver".into())
            .or_insert_with(|| "8.10.35".into());
        cookies
    }

    pub(crate) async fn send_captcha(&self, phone: &str, country_code: &str) -> Result<(), String> {
        self.clear_cookies();
        let raw = self
            .post_weapi(
                "https://interface.music.163.com/weapi/sms/captcha/sent",
                json!({ "cellphone": phone, "ctcode": country_code }),
                true,
            )
            .await?;
        ensure_api_ok(&raw, "发送验证码")
    }

    pub(crate) async fn verify_and_login(
        &self,
        phone: &str,
        country_code: &str,
        code: &str,
    ) -> Result<(), String> {
        let verified = self
            .post_weapi(
                "https://interface.music.163.com/weapi/sms/captcha/verify",
                json!({ "cellphone": phone, "captcha": code, "ctcode": country_code }),
                true,
            )
            .await?;
        ensure_api_ok(&verified, "校验验证码")?;

        let login = self
            .post_eapi(
                "https://interface.music.163.com/eapi/w/login/cellphone",
                json!({
                    "phone": phone,
                    "countrycode": country_code,
                    "remember": "true",
                    "type": "1",
                    "captcha": code
                }),
                true,
            )
            .await?;
        ensure_api_ok(&login, "登录")?;
        if self.cookies().get("MUSIC_U").map_or(true, String::is_empty) {
            return Err("登录响应缺少 MUSIC_U Cookie，请重试".into());
        }
        self.ensure_session().await
    }

    pub(crate) async fn create_qr_login(&self) -> Result<QrLoginChallenge, String> {
        let mut active_key = self.qr_login_key.lock().await;
        self.clear_cookies();
        let raw = self
            .post_weapi(
                "https://music.163.com/weapi/login/qrcode/unikey",
                json!({ "type": 3 }),
                true,
            )
            .await?;
        let key = parse_qr_key(&raw)?;
        *active_key = Some(key.clone());
        Ok(QrLoginChallenge {
            image_data_url: qr_data_url(&key)?,
            key,
        })
    }

    pub(crate) async fn check_qr_login(&self, key: &str) -> Result<QrLoginStatus, String> {
        let active_key = self.qr_login_key.lock().await;
        if active_key.as_deref() != Some(key) {
            return Err("登录二维码已失效".into());
        }
        let raw = self
            .post_weapi(
                "https://music.163.com/weapi/login/qrcode/client/login",
                json!({ "key": key, "type": 3 }),
                true,
            )
            .await?;
        parse_qr_login_status(&raw)
    }

    pub(crate) async fn profile(&self) -> Result<Profile, String> {
        let raw = self
            .post_weapi(
                "https://music.163.com/weapi/w/nuser/account/get",
                json!({}),
                true,
            )
            .await?;
        parse_account(&raw)
    }

    pub(crate) async fn library_category(
        &self,
        collection_type: CollectionType,
        profile_id: u64,
    ) -> Result<Vec<CollectionSummary>, String> {
        match collection_type {
            CollectionType::Playlist => {
                let raw = self
                    .post_weapi(
                        "https://music.163.com/weapi/user/playlist",
                        json!({
                            "uid": profile_id.to_string(),
                            "offset": "0",
                            "limit": "1000",
                            "includeVideo": "true"
                        }),
                        true,
                    )
                    .await?;
                let (mut created, subscribed) = parse_playlists(&raw, profile_id)?;
                created.extend(subscribed);
                Ok(created)
            }
            CollectionType::Album => {
                let raw = self
                    .post_weapi(
                        "https://music.163.com/weapi/album/sublist",
                        json!({ "offset": "0", "limit": "1000", "total": "true" }),
                        true,
                    )
                    .await?;
                parse_albums(&raw)
            }
            CollectionType::Podcast => {
                let raw = self
                    .post_weapi(
                        "https://music.163.com/weapi/djradio/get/subed",
                        json!({ "offset": "0", "limit": "1000", "total": "true" }),
                        true,
                    )
                    .await?;
                parse_podcasts(&raw)
            }
        }
    }

    pub(crate) async fn load_collection(
        &self,
        collection: CollectionSummary,
    ) -> Result<Vec<Track>, String> {
        let id = parse_id(&collection.id, "集合")?;
        match collection.collection_type {
            CollectionType::Playlist => {
                let raw = self
                    .post_plain(
                        "https://music.163.com/api/v6/playlist/detail",
                        BTreeMap::from([
                            ("id".into(), id.to_string()),
                            ("n".into(), "100000".into()),
                            ("s".into(), "8".into()),
                        ]),
                        true,
                    )
                    .await?;
                let parsed = parse_playlist_detail(&raw)?;
                if parsed.track_ids.is_empty() {
                    return Ok(parsed.tracks);
                }
                let known: std::collections::HashSet<u64> = parsed
                    .tracks
                    .iter()
                    .filter_map(|track| track.id.parse().ok())
                    .collect();
                let missing: Vec<u64> = parsed
                    .track_ids
                    .iter()
                    .copied()
                    .filter(|track_id| !known.contains(track_id))
                    .collect();
                let mut tracks = parsed.tracks;
                for page in missing.chunks(300) {
                    tracks.extend(self.song_details(page).await?);
                }
                Ok(merge_tracks(&parsed.track_ids, tracks))
            }
            CollectionType::Album => {
                let raw = self
                    .post_weapi(
                        &format!("https://interface.music.163.com/weapi/v1/album/{id}"),
                        json!({ "n": "100000", "s": "8" }),
                        true,
                    )
                    .await?;
                parse_album_detail(&raw)
            }
            CollectionType::Podcast => {
                let raw = self
                    .post_weapi(
                        "https://music.163.com/weapi/dj/program/byradio",
                        json!({
                            "radioId": id.to_string(),
                            "offset": "0",
                            "limit": "1000",
                            "asc": "false"
                        }),
                        true,
                    )
                    .await?;
                parse_podcast_detail(&raw, collection)
            }
        }
    }

    pub(crate) async fn resolve_stream(&self, track_id: u64) -> Result<String, String> {
        let eapi = self
            .post_eapi(
                "https://interface.music.163.com/eapi/song/enhance/player/url/v1",
                json!({
                    "ids": format!("[{track_id}]"),
                    "level": "lossless",
                    "encodeType": "flac"
                }),
                true,
            )
            .await?;
        if let Ok(url) = parse_playback_url(&eapi) {
            return Ok(url);
        }

        let fallback = self
            .post_weapi(
                "https://music.163.com/weapi/song/enhance/player/url",
                json!({ "ids": format!("[{track_id}]"), "br": "320000" }),
                true,
            )
            .await?;
        parse_playback_url(&fallback)
    }

    async fn song_details(&self, ids: &[u64]) -> Result<Vec<Track>, String> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        let c = ids.iter().map(|id| json!({ "id": id })).collect::<Vec<_>>();
        let raw = self
            .post_weapi(
                "https://music.163.com/weapi/v3/song/detail",
                json!({
                    "c": serde_json::to_string(&c).map_err(|error| format!("序列化曲目 ID 失败：{error}"))?,
                    "ids": serde_json::to_string(ids).map_err(|error| format!("序列化曲目 ID 失败：{error}"))?
                }),
                true,
            )
            .await?;
        parse_song_details(&raw)
    }

    async fn ensure_session(&self) -> Result<(), String> {
        let request = self.with_headers(self.http.get("https://music.163.com/"), true)?;
        self.send(request).await.map(|_| ())
    }

    async fn post_weapi(
        &self,
        url: &str,
        payload: Value,
        use_cookies: bool,
    ) -> Result<String, String> {
        let mut target = Url::parse(url).map_err(|error| format!("网易云接口地址无效：{error}"))?;
        let csrf = if use_cookies {
            self.cookies().get("__csrf").cloned().unwrap_or_default()
        } else {
            String::new()
        };
        target.query_pairs_mut().append_pair("csrf_token", &csrf);
        let form = weapi_encrypt(&payload)?;
        let request = self.with_headers(self.http.post(target).form(&form), use_cookies)?;
        self.send(request).await
    }

    async fn post_eapi(
        &self,
        url: &str,
        payload: Value,
        use_cookies: bool,
    ) -> Result<String, String> {
        let target = Url::parse(url).map_err(|error| format!("网易云接口地址无效：{error}"))?;
        let cookies = if use_cookies {
            self.cookies()
        } else {
            BTreeMap::new()
        };
        let (payload, header) = eapi_payload(payload, &cookies, &self.device_id)?;
        let form = BTreeMap::from([("params", eapi_encrypt(target.path(), &payload)?)]);
        let request = self
            .with_headers(self.http.post(target).form(&form), false)?
            .header(COOKIE, cookie_header(&header));
        self.send(request).await
    }

    async fn post_plain(
        &self,
        url: &str,
        form: BTreeMap<String, String>,
        use_cookies: bool,
    ) -> Result<String, String> {
        let request = self.with_headers(self.http.post(url).form(&form), use_cookies)?;
        self.send(request).await
    }

    fn with_headers(
        &self,
        request: RequestBuilder,
        use_cookies: bool,
    ) -> Result<RequestBuilder, String> {
        let request = request
            .header(ACCEPT, "*/*")
            .header(ACCEPT_LANGUAGE, "zh-CN,zh-Hans;q=0.9")
            .header(REFERER, "https://music.163.com/");
        if !use_cookies {
            return Ok(request);
        }
        let header = cookie_header(&self.cookies());
        if header.is_empty() {
            Ok(request)
        } else {
            Ok(request.header(COOKIE, header))
        }
    }

    async fn send(&self, request: RequestBuilder) -> Result<String, String> {
        let response = request
            .send()
            .await
            .map_err(|error| format!("网络请求失败：{error}"))?;
        let status = response.status();
        self.absorb_headers(response.headers());
        let body = response
            .text()
            .await
            .map_err(|error| format!("读取网易云响应失败：{error}"))?;
        if status.is_success() {
            Ok(body)
        } else {
            Err(format!(
                "网易云请求失败（HTTP {}）：{}",
                status.as_u16(),
                message_from_body(&body)
            ))
        }
    }

    fn absorb_headers(&self, headers: &HeaderMap) {
        let values = headers
            .get_all(SET_COOKIE)
            .iter()
            .filter_map(|value| value.to_str().ok());
        let updates = extract_set_cookie_values(values);
        let mut cookies = self.cookies.lock().expect("cookie lock poisoned");
        for (name, value) in updates {
            if value.is_empty() {
                cookies.remove(&name);
            } else {
                cookies.insert(name, value);
            }
        }
        if !cookies.is_empty() {
            cookies.entry("os".into()).or_insert_with(|| "pc".into());
            cookies
                .entry("appver".into())
                .or_insert_with(|| "8.10.35".into());
        }
    }
}

pub(crate) fn eapi_payload(
    mut payload: Value,
    cookies: &BTreeMap<String, String>,
    fallback_device_id: &str,
) -> Result<(Value, BTreeMap<String, String>), String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let mut header: BTreeMap<String, String> = BTreeMap::from([
        (
            "osver".into(),
            cookie_or(
                cookies,
                "osver",
                "Microsoft-Windows-10-Professional-build-22631-64bit",
            ),
        ),
        (
            "deviceId".into(),
            cookie_or(cookies, "deviceId", fallback_device_id),
        ),
        ("os".into(), cookie_or(cookies, "os", "pc")),
        ("appver".into(), cookie_or(cookies, "appver", "8.10.35")),
        (
            "versioncode".into(),
            cookie_or(cookies, "versioncode", "140"),
        ),
        ("mobilename".into(), cookie_or(cookies, "mobilename", "")),
        (
            "buildver".into(),
            cookie_or(cookies, "buildver", &now.as_secs().to_string()),
        ),
        (
            "resolution".into(),
            cookie_or(cookies, "resolution", "1920x1080"),
        ),
        ("__csrf".into(), cookie_or(cookies, "__csrf", "")),
        ("channel".into(), cookie_or(cookies, "channel", "netease")),
        (
            "requestId".into(),
            format!("{}_{:04}", now.as_millis(), random_u16() % 10_000),
        ),
    ]);
    for name in ["MUSIC_U", "MUSIC_A"] {
        if let Some(value) = cookies.get(name).filter(|value| !value.is_empty()) {
            header.insert(name.into(), value.clone());
        }
    }
    let object = payload
        .as_object_mut()
        .ok_or_else(|| "EAPI 请求参数必须是 JSON 对象".to_string())?;
    object.insert(
        "header".into(),
        Value::Object(Map::from_iter(
            header
                .iter()
                .map(|(name, value)| (name.clone(), Value::String(value.clone()))),
        )),
    );
    Ok((payload, header))
}

fn cookie_or(cookies: &BTreeMap<String, String>, name: &str, fallback: &str) -> String {
    cookies
        .get(name)
        .filter(|value| !value.is_empty())
        .cloned()
        .unwrap_or_else(|| fallback.to_string())
}

fn cookie_header(cookies: &BTreeMap<String, String>) -> String {
    cookies
        .iter()
        .filter(|(_, value)| !value.is_empty())
        .map(|(name, value)| format!("{name}={value}"))
        .collect::<Vec<_>>()
        .join("; ")
}

fn random_hex(bytes: usize) -> String {
    use rand::RngCore;

    let mut value = vec![0_u8; bytes];
    rand::thread_rng().fill_bytes(&mut value);
    hex::encode(value)
}

fn random_u16() -> u16 {
    use rand::RngCore;

    rand::thread_rng().next_u32() as u16
}

pub(crate) fn extract_set_cookie_values<'a>(
    values: impl IntoIterator<Item = &'a str>,
) -> BTreeMap<String, String> {
    values
        .into_iter()
        .filter_map(|value| value.split(';').next())
        .filter_map(|pair| pair.trim().split_once('='))
        .filter(|(name, _)| !name.trim().is_empty())
        .map(|(name, value)| (name.trim().to_string(), value.trim().to_string()))
        .collect()
}

pub(crate) fn parse_qr_key(raw: &str) -> Result<String, String> {
    let root = parse_root(raw, "二维码 key")?;
    if code(&root) != Some(200) {
        return Err(format!("创建登录二维码失败：{}", api_message(&root)));
    }
    clean_string(root.get("unikey"))
        .or_else(|| {
            root.get("data")
                .and_then(|data| clean_string(data.get("unikey")))
        })
        .ok_or_else(|| "二维码响应缺少 unikey".to_string())
}

pub(crate) fn parse_qr_login_status(raw: &str) -> Result<QrLoginStatus, String> {
    let root = parse_root(raw, "二维码状态")?;
    match code(&root) {
        Some(800) => Ok(QrLoginStatus::Expired),
        Some(801) => Ok(QrLoginStatus::Waiting),
        Some(802) => Ok(QrLoginStatus::Scanned),
        Some(803) => Ok(QrLoginStatus::Confirmed),
        _ => Err(format!("检查登录二维码失败：{}", api_message(&root))),
    }
}

pub(crate) fn qr_data_url(key: &str) -> Result<String, String> {
    let url = format!("https://music.163.com/login?codekey={key}");
    let code =
        QrCode::new(url.as_bytes()).map_err(|error| format!("生成登录二维码失败：{error}"))?;
    let svg = code
        .render::<svg::Color>()
        .min_dimensions(256, 256)
        .dark_color(svg::Color("#171717"))
        .light_color(svg::Color("#ffffff"))
        .build();
    Ok(format!("data:image/svg+xml;base64,{}", BASE64.encode(svg)))
}

pub(crate) fn parse_account(raw: &str) -> Result<Profile, String> {
    let root = parse_root(raw, "账号信息")?;
    match code(&root) {
        Some(200) => {}
        Some(301) => return Err(format!("登录已失效：{}", api_message(&root))),
        _ => return Err(format!("获取账号信息失败：{}", api_message(&root))),
    }
    let profile = root
        .get("profile")
        .and_then(Value::as_object)
        .ok_or_else(|| "账号响应缺少 profile".to_string())?;
    let id = value_u64(profile.get("userId")).ok_or_else(|| "账号响应缺少 userId".to_string())?;
    Ok(Profile {
        id: id.to_string(),
        nickname: profile
            .get("nickname")
            .and_then(Value::as_str)
            .unwrap_or("网易云用户")
            .to_string(),
        avatar_url: clean_string(profile.get("avatarUrl")).map(normalize_https),
    })
}

pub(crate) fn parse_playlists(
    raw: &str,
    profile_id: u64,
) -> Result<(Vec<CollectionSummary>, Vec<CollectionSummary>), String> {
    let root = successful_root(raw, "个人歌单")?;
    let items = root
        .get("playlist")
        .and_then(Value::as_array)
        .ok_or_else(|| "歌单响应缺少 playlist".to_string())?;
    let mut created = Vec::new();
    let mut subscribed = Vec::new();
    for item in items {
        let Some(id) = value_u64(item.get("id")) else {
            continue;
        };
        let title = clean_string(item.get("name")).unwrap_or_default();
        if title.is_empty() {
            continue;
        }
        let creator = item.get("creator");
        let creator_id = creator
            .and_then(|value| value_u64(value.get("userId")))
            .unwrap_or_default();
        let summary = CollectionSummary {
            id: id.to_string(),
            collection_type: CollectionType::Playlist,
            title,
            subtitle: creator
                .and_then(|value| clean_string(value.get("nickname")))
                .unwrap_or_default(),
            cover_url: clean_string(item.get("coverImgUrl"))
                .map(normalize_https)
                .unwrap_or_default(),
            track_count: value_u64(item.get("trackCount"))
                .and_then(|value| u32::try_from(value).ok()),
        };
        if creator_id == profile_id {
            created.push(summary);
        } else {
            subscribed.push(summary);
        }
    }
    Ok((created, subscribed))
}

pub(crate) fn parse_albums(raw: &str) -> Result<Vec<CollectionSummary>, String> {
    let root = successful_root(raw, "收藏专辑")?;
    let items = root
        .get("data")
        .and_then(Value::as_array)
        .or_else(|| root.get("playlist").and_then(Value::as_array))
        .ok_or_else(|| "专辑响应缺少 data".to_string())?;
    Ok(items
        .iter()
        .filter_map(|item| {
            let info = item.get("dataInfo");
            let data = info.and_then(|value| value.get("data")).unwrap_or(item);
            let id = value_u64(data.get("id"))?;
            let title = clean_string(data.get("name"))?;
            let cover = info
                .and_then(|value| clean_string(value.get("picUrl")))
                .or_else(|| clean_string(data.get("picUrl")))
                .or_else(|| clean_string(data.get("blurPicUrl")))
                .map(normalize_https)
                .unwrap_or_default();
            let subtitle = data
                .get("artists")
                .and_then(Value::as_array)
                .map(|items| artist_names(items))
                .unwrap_or_default();
            Some(CollectionSummary {
                id: id.to_string(),
                collection_type: CollectionType::Album,
                title,
                subtitle,
                cover_url: cover,
                track_count: value_u64(data.get("size"))
                    .or_else(|| value_u64(data.get("songCount")))
                    .and_then(|value| u32::try_from(value).ok()),
            })
        })
        .collect())
}

pub(crate) fn parse_podcasts(raw: &str) -> Result<Vec<CollectionSummary>, String> {
    let root = successful_root(raw, "订阅播客")?;
    let data = root.get("data");
    let items = root
        .get("djRadios")
        .and_then(Value::as_array)
        .or_else(|| data.and_then(Value::as_array))
        .or_else(|| {
            data.and_then(|value| value.get("djRadios"))
                .and_then(Value::as_array)
        })
        .or_else(|| {
            data.and_then(|value| value.get("list"))
                .and_then(Value::as_array)
        })
        .ok_or_else(|| "播客响应缺少列表".to_string())?;
    Ok(items
        .iter()
        .filter_map(|item| {
            let id = value_u64(item.get("id")).or_else(|| value_u64(item.get("radioId")))?;
            let title =
                clean_string(item.get("name")).or_else(|| clean_string(item.get("title")))?;
            let subtitle = item
                .get("dj")
                .and_then(|value| clean_string(value.get("nickname")))
                .or_else(|| {
                    item.get("creator")
                        .and_then(|value| clean_string(value.get("nickname")))
                })
                .unwrap_or_default();
            Some(CollectionSummary {
                id: id.to_string(),
                collection_type: CollectionType::Podcast,
                title,
                subtitle,
                cover_url: clean_string(item.get("picUrl"))
                    .or_else(|| clean_string(item.get("coverUrl")))
                    .map(normalize_https)
                    .unwrap_or_default(),
                track_count: value_u64(item.get("programCount"))
                    .or_else(|| value_u64(item.get("trackCount")))
                    .and_then(|value| u32::try_from(value).ok()),
            })
        })
        .collect())
}

pub(crate) struct ParsedPlaylist {
    pub(crate) track_ids: Vec<u64>,
    pub(crate) tracks: Vec<Track>,
}

pub(crate) fn parse_playlist_detail(raw: &str) -> Result<ParsedPlaylist, String> {
    let root = successful_root(raw, "歌单详情")?;
    let playlist = root
        .get("playlist")
        .ok_or_else(|| "歌单详情缺少 playlist".to_string())?;
    let tracks = playlist
        .get("tracks")
        .and_then(Value::as_array)
        .map(|items| items.iter().filter_map(parse_track).collect())
        .unwrap_or_default();
    let track_ids = playlist
        .get("trackIds")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| value_u64(item.get("id")))
                .collect()
        })
        .unwrap_or_default();
    Ok(ParsedPlaylist { track_ids, tracks })
}

pub(crate) fn parse_album_detail(raw: &str) -> Result<Vec<Track>, String> {
    let root = successful_root(raw, "专辑详情")?;
    let fallback = root
        .get("album")
        .and_then(|album| clean_string(album.get("picUrl")))
        .map(normalize_https);
    let songs = root
        .get("songs")
        .and_then(Value::as_array)
        .ok_or_else(|| "专辑详情缺少 songs".to_string())?;
    Ok(songs
        .iter()
        .filter_map(|item| parse_track_with_cover(item, fallback.clone()))
        .collect())
}

pub(crate) fn parse_podcast_detail(
    raw: &str,
    summary: CollectionSummary,
) -> Result<Vec<Track>, String> {
    let root = successful_root(raw, "播客节目")?;
    let programs = root
        .get("programs")
        .and_then(Value::as_array)
        .or_else(|| {
            root.get("data")
                .and_then(|value| value.get("programs"))
                .and_then(Value::as_array)
        })
        .ok_or_else(|| "播客响应缺少 programs".to_string())?;
    Ok(programs
        .iter()
        .filter_map(|program| {
            let song = program.get("mainSong")?;
            let id = value_u64(song.get("id")).or_else(|| value_u64(program.get("mainSongId")))?;
            let title =
                clean_string(program.get("name")).or_else(|| clean_string(song.get("name")))?;
            let duration_ms = value_u64(song.get("duration"))
                .or_else(|| value_u64(song.get("dt")))
                .unwrap_or_default();
            let artist = song
                .get("ar")
                .and_then(Value::as_array)
                .or_else(|| song.get("artists").and_then(Value::as_array))
                .map(|items| artist_names(items))
                .filter(|name| !name.is_empty())
                .or_else(|| {
                    program
                        .get("dj")
                        .and_then(|value| clean_string(value.get("nickname")))
                })
                .unwrap_or_else(|| summary.subtitle.clone());
            let cover = clean_string(program.get("coverUrl"))
                .or_else(|| {
                    program
                        .get("radio")
                        .and_then(|value| clean_string(value.get("picUrl")))
                })
                .or_else(|| {
                    song.get("album")
                        .and_then(|value| clean_string(value.get("picUrl")))
                })
                .map(normalize_https)
                .or_else(|| (!summary.cover_url.is_empty()).then(|| summary.cover_url.clone()));
            Some(Track {
                id: id.to_string(),
                title,
                artist,
                duration: duration_ms as f64 / 1000.0,
                cover_url: cover,
            })
        })
        .collect())
}

pub(crate) fn parse_song_details(raw: &str) -> Result<Vec<Track>, String> {
    let root = successful_root(raw, "曲目详情")?;
    let songs = root
        .get("songs")
        .and_then(Value::as_array)
        .ok_or_else(|| "曲目详情缺少 songs".to_string())?;
    Ok(songs.iter().filter_map(parse_track).collect())
}

pub(crate) fn merge_tracks(ids: &[u64], tracks: Vec<Track>) -> Vec<Track> {
    let mut by_id: HashMap<u64, Track> = tracks
        .into_iter()
        .filter_map(|track| track.id.parse().ok().map(|id| (id, track)))
        .collect();
    ids.iter().filter_map(|id| by_id.remove(id)).collect()
}

pub(crate) fn parse_playback_url(raw: &str) -> Result<String, String> {
    let root = parse_root(raw, "播放地址")?;
    if code(&root) == Some(301) {
        return Err("登录已失效，请重新登录".into());
    }
    if code(&root) != Some(200) {
        return Err(format!("获取播放地址失败：{}", api_message(&root)));
    }
    let data = match root.get("data") {
        Some(Value::Array(items)) => items.first(),
        Some(value @ Value::Object(_)) => Some(value),
        _ => None,
    }
    .ok_or_else(|| "播放响应缺少 data".to_string())?;
    clean_string(data.get("url"))
        .filter(|url| !url.eq_ignore_ascii_case("null"))
        .map(normalize_https)
        .ok_or_else(|| {
            if value_u64(data.get("fee")).unwrap_or_default() > 0 {
                "该曲目当前账号无播放权限".into()
            } else {
                "网易云未返回可播放地址".into()
            }
        })
}

fn parse_track(value: &Value) -> Option<Track> {
    parse_track_with_cover(value, None)
}

fn parse_track_with_cover(value: &Value, fallback_cover: Option<String>) -> Option<Track> {
    let id = value_u64(value.get("id"))?;
    let title = clean_string(value.get("name"))?;
    let artists = value
        .get("ar")
        .and_then(Value::as_array)
        .or_else(|| value.get("artists").and_then(Value::as_array))
        .map(|items| artist_names(items))
        .unwrap_or_default();
    let album = value.get("al").or_else(|| value.get("album"));
    let duration_ms = value_u64(value.get("dt"))
        .or_else(|| value_u64(value.get("duration")))
        .unwrap_or_default();
    Some(Track {
        id: id.to_string(),
        title,
        artist: artists,
        duration: duration_ms as f64 / 1000.0,
        cover_url: album
            .and_then(|item| clean_string(item.get("picUrl")))
            .map(normalize_https)
            .or(fallback_cover),
    })
}

fn artist_names(items: &[Value]) -> String {
    items
        .iter()
        .filter_map(|artist| clean_string(artist.get("name")))
        .collect::<Vec<_>>()
        .join(" / ")
}

fn ensure_api_ok(raw: &str, action: &str) -> Result<(), String> {
    let root = parse_root(raw, action)?;
    if code(&root) == Some(200) {
        Ok(())
    } else {
        Err(format!("{action}失败：{}", api_message(&root)))
    }
}

fn successful_root(raw: &str, action: &str) -> Result<Value, String> {
    let root = parse_root(raw, action)?;
    match code(&root) {
        Some(200) => Ok(root),
        Some(301) => Err(format!("登录已失效：{}", api_message(&root))),
        _ => Err(format!("{action}失败：{}", api_message(&root))),
    }
}

fn parse_root(raw: &str, action: &str) -> Result<Value, String> {
    serde_json::from_str(raw).map_err(|error| format!("解析{action}响应失败：{error}"))
}

fn code(root: &Value) -> Option<u64> {
    value_u64(root.get("code"))
}

fn api_message(root: &Value) -> String {
    clean_string(root.get("msg"))
        .or_else(|| clean_string(root.get("message")))
        .unwrap_or_else(|| {
            format!(
                "接口返回 code={}",
                code(root)
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "unknown".into())
            )
        })
}

fn message_from_body(raw: &str) -> String {
    serde_json::from_str::<Value>(raw)
        .ok()
        .map(|root| api_message(&root))
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| raw.chars().take(200).collect())
}

fn value_u64(value: Option<&Value>) -> Option<u64> {
    match value? {
        Value::Number(number) => number.as_u64(),
        Value::String(text) => text.parse().ok(),
        _ => None,
    }
}

fn clean_string(value: Option<&Value>) -> Option<String> {
    value?
        .as_str()
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_string)
}

fn normalize_https(url: String) -> String {
    if let Some(rest) = url.strip_prefix("http://") {
        format!("https://{rest}")
    } else {
        url
    }
}

fn parse_id(raw: &str, kind: &str) -> Result<u64, String> {
    raw.parse().map_err(|_| format!("{kind} ID 无效：{raw}"))
}
