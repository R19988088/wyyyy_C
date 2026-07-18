use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use tempfile::NamedTempFile;

#[derive(Clone)]
pub(crate) struct AudioCache {
    root: PathBuf,
}

impl AudioCache {
    pub(crate) fn new(root: PathBuf) -> Result<Self, String> {
        fs::create_dir_all(&root).map_err(|e| format!("创建音频缓存目录失败：{e}"))?;
        Ok(Self { root })
    }

    pub(crate) fn write(&self, account: &str, track: &str, data: &[u8]) -> Result<PathBuf, String> {
        validate_id(account, "账号")?;
        validate_id(track, "曲目")?;
        let dir = self.root.join(account);
        fs::create_dir_all(&dir).map_err(|e| format!("创建账号缓存目录失败：{e}"))?;
        let target = dir.join(format!("{track}.audio"));
        let mut temporary =
            NamedTempFile::new_in(&dir).map_err(|e| format!("创建音频临时文件失败：{e}"))?;
        temporary
            .write_all(data)
            .and_then(|_| temporary.as_file().sync_all())
            .map_err(|e| format!("写入音频缓存失败：{e}"))?;
        temporary
            .persist(&target)
            .map_err(|e| format!("替换音频缓存失败：{}", e.error))?;
        Ok(target)
    }

    pub(crate) fn lookup(&self, account: &str, track: &str) -> Option<PathBuf> {
        if validate_id(account, "账号").is_err() || validate_id(track, "曲目").is_err() {
            return None;
        }
        let path = self.root.join(account).join(format!("{track}.audio"));
        path.is_file().then_some(path)
    }

    pub(crate) fn size(&self, account: &str) -> Result<u64, String> {
        validate_id(account, "账号")?;
        directory_size(&self.root.join(account))
    }

    pub(crate) fn clear(&self, account: &str) -> Result<(), String> {
        validate_id(account, "账号")?;
        let path = self.root.join(account);
        if path.exists() {
            fs::remove_dir_all(path).map_err(|e| format!("清理音频缓存失败：{e}"))?;
        }
        Ok(())
    }
}

fn validate_id(id: &str, kind: &str) -> Result<(), String> {
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
        Err(format!("{kind} ID 无效"))
    } else {
        Ok(())
    }
}

fn directory_size(path: &Path) -> Result<u64, String> {
    if !path.exists() {
        return Ok(0);
    }
    fs::read_dir(path)
        .map_err(|e| format!("读取音频缓存失败：{e}"))?
        .try_fold(0, |total, entry| {
            let entry = entry.map_err(|e| format!("读取音频缓存项失败：{e}"))?;
            let metadata = entry
                .metadata()
                .map_err(|e| format!("读取音频缓存大小失败：{e}"))?;
            Ok(total
                + if metadata.is_file() {
                    metadata.len()
                } else {
                    0
                })
        })
}
