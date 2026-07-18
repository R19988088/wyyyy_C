use crate::models::{CollectionSummary, SavedPosition, Session, Track};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tempfile::NamedTempFile;

#[derive(Clone, Default, Serialize, Deserialize)]
struct PersistedState {
    session: Option<Session>,
    #[serde(default)]
    playback: BTreeMap<String, BTreeMap<String, SavedPosition>>,
    #[serde(default)]
    libraries: BTreeMap<String, BTreeMap<String, Vec<CollectionSummary>>>,
    #[serde(default)]
    library_versions: BTreeMap<String, BTreeMap<String, u32>>,
    #[serde(default)]
    tracks: BTreeMap<String, BTreeMap<String, Vec<Track>>>,
}

#[derive(Clone)]
pub(crate) struct Store {
    path: PathBuf,
    data: Arc<Mutex<PersistedState>>,
}

impl Store {
    pub(crate) fn open(path: PathBuf) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|e| format!("创建应用数据目录失败：{e}"))?;
        }
        let data = if path.exists() {
            serde_json::from_slice(&fs::read(&path).map_err(|e| format!("读取本地状态失败：{e}"))?)
                .map_err(|e| format!("本地状态文件已损坏：{e}"))?
        } else {
            PersistedState::default()
        };
        Ok(Self {
            path,
            data: Arc::new(Mutex::new(data)),
        })
    }

    pub(crate) fn session(&self) -> Option<Session> {
        self.data.lock().ok()?.session.clone()
    }
    pub(crate) fn save_session(&self, value: Session) -> Result<(), String> {
        self.change(|s| s.session = Some(value))
    }
    pub(crate) fn clear_session(&self) -> Result<(), String> {
        self.change(|s| s.session = None)
    }

    pub(crate) fn session_matches(&self, expected: &Session) -> bool {
        self.session().as_ref() == Some(expected)
    }

    pub(crate) fn clear_session_if_matches(&self, expected: &Session) -> Result<bool, String> {
        let mut cleared = false;
        self.change(|state| {
            if state.session.as_ref() == Some(expected) {
                state.session = None;
                cleared = true;
            }
        })?;
        Ok(cleared)
    }

    pub(crate) fn save_playback(
        &self,
        account: &str,
        key: String,
        value: SavedPosition,
    ) -> Result<(), String> {
        if key.trim().is_empty()
            || value.track_id.trim().is_empty()
            || !value.position.is_finite()
            || value.position < 0.0
        {
            return Err("播放位置无效".into());
        }
        self.change(|s| {
            s.playback
                .entry(account.into())
                .or_default()
                .insert(key, value);
        })
    }
    pub(crate) fn load_playback(&self, account: &str) -> BTreeMap<String, SavedPosition> {
        self.data
            .lock()
            .ok()
            .and_then(|s| s.playback.get(account).cloned())
            .unwrap_or_default()
    }
    pub(crate) fn save_library(
        &self,
        account: &str,
        category: &str,
        value: Vec<CollectionSummary>,
    ) -> Result<(), String> {
        self.change(|s| {
            s.libraries
                .entry(account.into())
                .or_default()
                .insert(category.into(), value);
            s.library_versions
                .entry(account.into())
                .or_default()
                .insert(category.into(), 1);
        })
    }
    pub(crate) fn library_is_current(&self, account: &str, category: &str) -> bool {
        self.data
            .lock()
            .ok()
            .and_then(|state| state.library_versions.get(account)?.get(category).copied())
            == Some(1)
    }
    pub(crate) fn load_library(
        &self,
        account: &str,
        category: &str,
    ) -> Option<Vec<CollectionSummary>> {
        self.data
            .lock()
            .ok()?
            .libraries
            .get(account)?
            .get(category)
            .cloned()
    }
    pub(crate) fn save_tracks(
        &self,
        account: &str,
        key: &str,
        value: Vec<Track>,
    ) -> Result<(), String> {
        self.change(|s| {
            s.tracks
                .entry(account.into())
                .or_default()
                .insert(key.into(), value);
        })
    }
    pub(crate) fn load_tracks(&self, account: &str, key: &str) -> Option<Vec<Track>> {
        self.data
            .lock()
            .ok()?
            .tracks
            .get(account)?
            .get(key)
            .cloned()
    }

    pub(crate) fn clear_metadata_cache(&self, account: &str) -> Result<(), String> {
        self.change(|state| {
            state.libraries.remove(account);
            state.library_versions.remove(account);
            state.tracks.remove(account);
        })
    }

    fn change(&self, update: impl FnOnce(&mut PersistedState)) -> Result<(), String> {
        let mut data = self
            .data
            .lock()
            .map_err(|_| "本地状态锁已损坏".to_string())?;
        let mut next = data.clone();
        update(&mut next);
        let parent = self
            .path
            .parent()
            .ok_or_else(|| "应用数据路径无效".to_string())?;
        let bytes = serde_json::to_vec(&next).map_err(|e| format!("序列化本地状态失败：{e}"))?;
        let mut temporary =
            NamedTempFile::new_in(parent).map_err(|e| format!("创建状态临时文件失败：{e}"))?;
        temporary
            .write_all(&bytes)
            .and_then(|_| temporary.as_file().sync_all())
            .map_err(|e| format!("写入本地状态失败：{e}"))?;
        temporary
            .persist(&self.path)
            .map_err(|e| format!("替换本地状态失败：{}", e.error))?;
        *data = next;
        Ok(())
    }
}
