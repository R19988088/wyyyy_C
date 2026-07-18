use crate::cache::AudioCache;
use crate::models::{CollectionSummary, CollectionType, Profile, Session, Track};
use crate::store::Store;
use std::collections::BTreeMap;
use std::fs;

#[test]
fn metadata_is_partitioned_by_account_and_survives_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("state.json");
    let store = Store::open(path.clone()).unwrap();
    let list = vec![CollectionSummary {
        id: "7".into(),
        collection_type: CollectionType::Playlist,
        title: "mine".into(),
        subtitle: String::new(),
        cover_url: String::new(),
        track_count: Some(1),
    }];
    store.save_library("42", "playlist", list.clone()).unwrap();
    drop(store);
    let reopened = Store::open(path).unwrap();
    assert_eq!(reopened.load_library("42", "playlist"), Some(list));
    assert!(reopened.library_is_current("42", "playlist"));
    assert_eq!(reopened.load_library("43", "playlist"), None);
}

#[test]
fn legacy_library_cache_requires_one_schema_refresh() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("state.json");
    fs::write(
        &path,
        r#"{"session":null,"libraries":{"42":{"album":[]}},"tracks":{}}"#,
    )
    .unwrap();

    let store = Store::open(path).unwrap();
    assert!(!store.library_is_current("42", "album"));
}

#[test]
fn tracks_are_partitioned_by_account_and_collection() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(dir.path().join("state.json")).unwrap();
    let tracks = vec![Track {
        id: "9".into(),
        title: "song".into(),
        artist: "artist".into(),
        duration: 1.0,
        cover_url: None,
    }];
    store
        .save_tracks("42", "playlist:7", tracks.clone())
        .unwrap();
    assert_eq!(store.load_tracks("42", "playlist:7"), Some(tracks));
    assert_eq!(store.load_tracks("42", "playlist:8"), None);
}

#[test]
fn playback_position_survives_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("state.json");
    let store = Store::open(path.clone()).unwrap();
    let position = crate::models::SavedPosition {
        track_id: "9".into(),
        track_index: 2,
        position: 87.5,
        updated_at: 123,
    };
    store
        .save_playback("42", "playlist:7".into(), position.clone())
        .unwrap();
    drop(store);

    let reopened = Store::open(path).unwrap();
    assert_eq!(
        reopened.load_playback("42").get("playlist:7"),
        Some(&position),
    );
}

#[test]
fn clearing_metadata_cache_keeps_other_accounts() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(dir.path().join("state.json")).unwrap();
    let list = vec![CollectionSummary {
        id: "7".into(),
        collection_type: CollectionType::Playlist,
        title: "mine".into(),
        subtitle: String::new(),
        cover_url: String::new(),
        track_count: None,
    }];
    store.save_library("42", "playlist", list.clone()).unwrap();
    store.save_library("43", "playlist", list.clone()).unwrap();

    store.clear_metadata_cache("42").unwrap();

    assert_eq!(store.load_library("42", "playlist"), None);
    assert_eq!(store.load_library("43", "playlist"), Some(list));
}

#[test]
fn audio_cache_atomically_writes_queries_sizes_and_clears_one_account() {
    let dir = tempfile::tempdir().unwrap();
    let cache = AudioCache::new(dir.path().join("audio")).unwrap();
    let path = cache.write("42", "9", b"audio bytes").unwrap();
    assert_eq!(fs::read(&path).unwrap(), b"audio bytes");
    assert_eq!(cache.lookup("42", "9"), Some(path));
    cache.write("43", "9", b"other").unwrap();
    assert_eq!(cache.size("42").unwrap(), 11);
    cache.clear("42").unwrap();
    assert!(cache.lookup("42", "9").is_none());
    assert!(cache.lookup("43", "9").is_some());
}

#[test]
fn audio_cache_rejects_path_traversal_ids() {
    let dir = tempfile::tempdir().unwrap();
    let cache = AudioCache::new(dir.path().join("audio")).unwrap();
    assert!(cache.write("../other", "9", b"x").is_err());
    assert!(cache.write("42", "../9", b"x").is_err());
}

#[test]
fn stale_session_cannot_clear_the_current_account() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(dir.path().join("state.json")).unwrap();
    let session = |id: &str| Session {
        profile: Profile {
            id: id.into(),
            nickname: id.into(),
            avatar_url: None,
        },
        cookies: BTreeMap::from([("MUSIC_U".into(), id.into())]),
    };
    let old = session("42");
    let current = session("43");
    store.save_session(current.clone()).unwrap();

    assert!(!store.clear_session_if_matches(&old).unwrap());
    assert_eq!(store.session(), Some(current));
}
