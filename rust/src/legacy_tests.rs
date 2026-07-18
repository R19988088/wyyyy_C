use crate::crypto::{eapi_encrypt, md5_hex};
use crate::models::{CollectionSummary, CollectionType, Profile, SavedPosition, Session};
use crate::netease::{
    eapi_payload, extract_set_cookie_values, merge_tracks, parse_account, parse_album_detail,
    parse_albums, parse_playback_url, parse_playlist_detail, parse_playlists, parse_podcast_detail,
    parse_podcasts, parse_qr_key, parse_qr_login_status, parse_song_details, qr_data_url,
    QrLoginStatus,
};
use crate::store::Store;
use std::collections::BTreeMap;
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn md5_matches_known_vector() {
    assert_eq!(md5_hex("123456"), "e10adc3949ba59abbe56e057f20f883e");
}

#[test]
fn eapi_matches_known_vector() {
    let encrypted = eapi_encrypt("/eapi/test", &serde_json::json!({ "a": 1 })).unwrap();
    assert_eq!(
        encrypted,
        "4DC723619A991588865191FD2F319BAD0918BC9C604E1E84A5C3578922E3A7E8810405B5500AF5BEABA2DEAB687471586CE47DE62C9D523E260A0250C7F3AC2802B572BD7B95623F10A1D55EF99B9A8C"
    );
}

#[test]
fn eapi_payload_includes_client_and_session_header() {
    let cookies = BTreeMap::from([
        ("MUSIC_U".into(), "session".into()),
        ("__csrf".into(), "csrf".into()),
        ("deviceId".into(), "device".into()),
    ]);
    let (payload, header) =
        eapi_payload(serde_json::json!({ "ids": "[1]" }), &cookies, "fallback").unwrap();

    assert_eq!(header.get("deviceId").map(String::as_str), Some("device"));
    assert_eq!(header.get("MUSIC_U").map(String::as_str), Some("session"));
    assert_eq!(payload["header"]["__csrf"], "csrf");
    assert_eq!(payload["header"]["os"], "pc");
    let (_, suffix) = payload["header"]["requestId"]
        .as_str()
        .unwrap()
        .rsplit_once('_')
        .unwrap();
    assert_eq!(suffix.len(), 4);
    assert!(suffix.chars().all(|character| character.is_ascii_digit()));
}

#[test]
fn cookie_extraction_keeps_equals_in_value() {
    let cookies =
        extract_set_cookie_values(["MUSIC_U=token==; Path=/; HttpOnly", "__csrf=csrf; Path=/"]);
    assert_eq!(cookies.get("MUSIC_U").map(String::as_str), Some("token=="));
    assert_eq!(cookies.get("__csrf").map(String::as_str), Some("csrf"));
}

#[test]
fn qr_login_parses_key_and_all_polling_states() {
    assert_eq!(
        parse_qr_key(r#"{"code":200,"unikey":"abc"}"#).unwrap(),
        "abc"
    );
    for (code, expected) in [
        (800, QrLoginStatus::Expired),
        (801, QrLoginStatus::Waiting),
        (802, QrLoginStatus::Scanned),
        (803, QrLoginStatus::Confirmed),
    ] {
        assert_eq!(
            parse_qr_login_status(&format!(r#"{{"code":{code}}}"#)).unwrap(),
            expected,
        );
    }
}

#[test]
fn qr_login_image_is_an_inline_svg() {
    let image = qr_data_url("abc").unwrap();
    assert!(image.starts_with("data:image/svg+xml;base64,"));
}

#[test]
fn account_parser_requires_profile() {
    let account = parse_account(
        r#"{"code":200,"profile":{"userId":42,"nickname":"Neri","avatarUrl":"https://img"}}"#,
    )
    .unwrap();
    assert_eq!(account.id, "42");
    assert_eq!(account.nickname, "Neri");
    assert!(parse_account(r#"{"code":301}"#).is_err());
}

#[test]
fn playlists_are_split_by_creator() {
    let raw = r#"{"code":200,"playlist":[
        {"id":1,"name":"Mine","coverImgUrl":"http://mine","trackCount":2,"creator":{"userId":42}},
        {"id":2,"name":"Saved","coverImgUrl":"https://saved","trackCount":3,"creator":{"userId":7}}
    ]}"#;
    let (created, subscribed) = parse_playlists(raw, 42).unwrap();
    assert_eq!(created[0].id, "1");
    assert_eq!(subscribed[0].id, "2");
    assert_eq!(created[0].cover_url, "https://mine");
}

#[test]
fn playlists_accept_alternate_cover_fields() {
    let raw = r#"{"code":200,"playlist":[
        {"id":1,"name":"Cover URL","coverUrl":"http://cover-url","creator":{"userId":42}},
        {"id":2,"name":"Pic URL","picUrl":"http://pic-url","creator":{"userId":42}}
    ]}"#;
    let (created, _) = parse_playlists(raw, 42).unwrap();
    assert_eq!(created[0].cover_url, "https://cover-url");
    assert_eq!(created[1].cover_url, "https://pic-url");
}

#[test]
fn albums_accept_nested_data_shape() {
    let raw = r#"{"code":200,"data":[{"dataInfo":{"picUrl":"http://cover","data":{"id":8,"name":"Album","size":9}}}]}"#;
    let albums = parse_albums(raw).unwrap();
    assert_eq!(albums[0].id, "8");
    assert_eq!(albums[0].track_count, Some(9));
}

#[test]
fn podcasts_accept_data_list_shape() {
    let raw = r#"{"code":200,"data":{"list":[{"radioId":5,"title":"Talk","coverUrl":"http://cover","programCount":4,"dj":{"nickname":"DJ"}}]}}"#;
    let podcasts = parse_podcasts(raw).unwrap();
    assert_eq!(podcasts[0].id, "5");
    assert_eq!(podcasts[0].subtitle, "DJ");
}

#[test]
fn playlist_detail_preserves_track_id_order() {
    let raw = r#"{"code":200,"playlist":{"id":7,"name":"List","coverImgUrl":"http://cover","trackCount":2,"trackIds":[{"id":2},{"id":1}],"tracks":[{"id":1,"name":"One","ar":[{"name":"A"}],"al":{"id":3,"name":"AL","picUrl":"http://song"},"dt":1000}]}}"#;
    let parsed = parse_playlist_detail(raw).unwrap();
    assert_eq!(parsed.track_ids, vec![2, 1]);
    assert_eq!(parsed.tracks[0].id, "1");
}

#[test]
fn album_detail_reads_songs() {
    let raw = r#"{"code":200,"album":{"id":3,"name":"AL","picUrl":"http://cover","size":1},"songs":[{"id":9,"name":"Song","ar":[{"name":"Singer"}],"al":{"id":3,"name":"AL"},"dt":1234}]}"#;
    let detail = parse_album_detail(raw).unwrap();
    assert_eq!(detail[0].artist, "Singer");
    assert!((detail[0].duration - 1.234).abs() < f64::EPSILON);
}

#[test]
fn podcast_uses_main_song_as_playable_track() {
    let summary = CollectionSummary {
        id: "4".into(),
        collection_type: CollectionType::Podcast,
        title: "Radio".into(),
        cover_url: "https://cover".into(),
        track_count: Some(1),
        subtitle: "Host".into(),
    };
    let raw = r#"{"code":200,"programs":[{"id":99,"name":"Episode","mainSong":{"id":11,"duration":5000}}]}"#;
    let detail = parse_podcast_detail(raw, summary).unwrap();
    assert_eq!(detail[0].id, "11");
}

#[test]
fn song_details_and_merge_restore_requested_order() {
    let raw = r#"{"code":200,"songs":[
        {"id":2,"name":"Two","ar":[{"name":"B"}],"al":{"id":1,"name":"AL"},"dt":2},
        {"id":1,"name":"One","ar":[{"name":"A"}],"al":{"id":1,"name":"AL"},"dt":1}
    ]}"#;
    let tracks = parse_song_details(raw).unwrap();
    let merged = merge_tracks(&[1, 2], tracks);
    assert_eq!(
        merged
            .iter()
            .map(|track| track.id.as_str())
            .collect::<Vec<_>>(),
        vec!["1", "2"]
    );
}

#[test]
fn playback_parser_rejects_null_url() {
    assert_eq!(
        parse_playback_url(r#"{"code":200,"data":[{"url":"https://audio","type":"mp3"}]}"#)
            .unwrap(),
        "https://audio"
    );
    assert!(parse_playback_url(r#"{"code":200,"data":[{"url":null,"fee":1}]}"#).is_err());
}

#[test]
fn store_keeps_playback_per_account_after_logout() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("wyyyy-store-{unique}"));
    let store = Store::open(dir.join("state.json")).unwrap();
    let account = Profile {
        id: "42".into(),
        nickname: "Neri".into(),
        avatar_url: None,
    };
    let session = Session {
        profile: account.clone(),
        cookies: BTreeMap::from([("MUSIC_U".into(), "token".into())]),
    };
    store.save_session(session).unwrap();
    store
        .save_playback(
            &account.id,
            "playlist:7".into(),
            SavedPosition {
                track_id: "9".into(),
                track_index: 1,
                position: 0.8,
                updated_at: 1,
            },
        )
        .unwrap();
    store.clear_session().unwrap();
    assert!(store.session().is_none());
    assert_eq!(
        store
            .load_playback(&account.id)
            .get("playlist:7")
            .unwrap()
            .track_id,
        "9"
    );
    let _ = fs::remove_dir_all(dir);
}
