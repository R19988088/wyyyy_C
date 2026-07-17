use crate::models::{SavedPosition, Session};
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
}

#[derive(Clone)]
pub(crate) struct Store {
    path: PathBuf,
    data: Arc<Mutex<PersistedState>>,
}

impl Store {
    pub(crate) fn open(path: PathBuf) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| format!("创建应用数据目录失败：{error}"))?;
        }
        let data = if path.exists() {
            let raw =
                fs::read_to_string(&path).map_err(|error| format!("读取本地状态失败：{error}"))?;
            serde_json::from_str(&raw).map_err(|error| format!("本地状态文件已损坏：{error}"))?
        } else {
            PersistedState::default()
        };
        Ok(Self {
            path,
            data: Arc::new(Mutex::new(data)),
        })
    }

    pub(crate) fn session(&self) -> Option<Session> {
        self.data
            .lock()
            .expect("store lock poisoned")
            .session
            .clone()
    }

    pub(crate) fn save_session(&self, session: Session) -> Result<(), String> {
        self.change(|data| data.session = Some(session))
    }

    pub(crate) fn clear_session(&self) -> Result<(), String> {
        self.change(|data| data.session = None)
    }

    pub(crate) fn save_playback(
        &self,
        profile_id: &str,
        collection_key: String,
        position: SavedPosition,
    ) -> Result<(), String> {
        if collection_key.trim().is_empty() || position.track_id.trim().is_empty() {
            return Err("播放位置缺少集合或曲目 ID".into());
        }
        if !position.position.is_finite() || position.position < 0.0 {
            return Err("播放位置必须是非负秒数".into());
        }
        self.change(|data| {
            data.playback
                .entry(profile_id.to_string())
                .or_default()
                .insert(collection_key, position);
        })
    }

    pub(crate) fn load_playback(&self, profile_id: &str) -> BTreeMap<String, SavedPosition> {
        self.data
            .lock()
            .expect("store lock poisoned")
            .playback
            .get(profile_id)
            .cloned()
            .unwrap_or_default()
    }

    fn change(&self, update: impl FnOnce(&mut PersistedState)) -> Result<(), String> {
        let mut data = self
            .data
            .lock()
            .map_err(|_| "本地状态锁已损坏".to_string())?;
        let mut next = data.clone();
        update(&mut next);
        let json =
            serde_json::to_vec(&next).map_err(|error| format!("序列化本地状态失败：{error}"))?;
        let parent = self
            .path
            .parent()
            .ok_or_else(|| "应用数据路径无效".to_string())?;
        let mut temporary = NamedTempFile::new_in(parent)
            .map_err(|error| format!("创建状态临时文件失败：{error}"))?;
        temporary
            .write_all(&json)
            .and_then(|_| temporary.as_file().sync_all())
            .map_err(|error| format!("写入本地状态失败：{error}"))?;
        temporary
            .persist(&self.path)
            .map_err(|error| format!("替换本地状态失败：{}", error.error))?;
        *data = next;
        Ok(())
    }
}
