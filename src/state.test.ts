// @ts-nocheck -- Node runs this file directly; the app does not depend on Node types.
import assert from "node:assert/strict";
import test from "node:test";

import {
  classifySwipe,
  collectionKey,
  coverSlots,
  decideCoverTap,
  decideVerticalNavigation,
  initialState,
  moveFocus,
  normalizeCountryCode,
  selectResumeTarget,
  update,
} from "./state.ts";

const collections = [
  { id: "a", type: "album", title: "A", subtitle: "Artist A", coverUrl: "a.jpg" },
  { id: "b", type: "album", title: "B", subtitle: "Artist B", coverUrl: "b.jpg" },
  { id: "c", type: "album", title: "C", subtitle: "Artist C", coverUrl: "c.jpg" },
];

const tracks = [
  { id: "t1", title: "One", artist: "Artist", duration: 100 },
  { id: "t2", title: "Two", artist: "Artist", duration: 200 },
];

function readyState() {
  return {
    ...initialState(),
    library: {
      album: { status: "ready", data: collections },
      playlist: { status: "idle" },
      podcast: { status: "idle" },
    },
    player: {
      status: "playing",
      current: {
        collectionKey: "playlist:old",
        track: tracks[0],
        trackIndex: 0,
        position: 42,
        duration: 100,
      },
    },
  };
}

test("collection keys include the category", () => {
  assert.equal(collectionKey("album", "42"), "album:42");
  assert.equal(collectionKey("podcast", "42"), "podcast:42");
});

test("country codes are sent as digits without a display prefix", () => {
  assert.equal(normalizeCountryCode("+86"), "86");
  assert.equal(normalizeCountryCode(" 86 "), "86");
});

test("focus movement is clamped to the collection bounds", () => {
  assert.equal(moveFocus(0, -1, 3), 0);
  assert.equal(moveFocus(1, 1, 3), 2);
  assert.equal(moveFocus(2, 1, 3), 2);
  assert.equal(moveFocus(0, 1, 0), 0);
});

test("a side cover focuses first and a centered cover activates", () => {
  assert.deepEqual(decideCoverTap("album:a", "album:b"), {
    kind: "focus",
    key: "album:b",
  });
  assert.deepEqual(decideCoverTap("album:b", "album:b"), {
    kind: "activate",
    key: "album:b",
  });
});

test("swipes require distance and a dominant axis", () => {
  assert.equal(classifySwipe(-80, 8, 180), "left");
  assert.equal(classifySwipe(70, 4, 180), "right");
  assert.equal(classifySwipe(3, -65, 220), "up");
  assert.equal(classifySwipe(4, 70, 220), "down");
  assert.equal(classifySwipe(12, 8, 100), "tap");
  assert.equal(classifySwipe(60, 55, 180), "none");
  assert.equal(classifySwipe(100, 0, 900), "none");
});

test("vertical navigation does not steal normal list scrolling", () => {
  assert.equal(decideVerticalNavigation("covers", "up", 0), "tracks");
  assert.equal(decideVerticalNavigation("covers", "down", 0), "covers");
  assert.equal(decideVerticalNavigation("tracks", "down", 0), "covers");
  assert.equal(decideVerticalNavigation("tracks", "down", 12), "tracks");
  assert.equal(decideVerticalNavigation("tracks", "up", 0), "tracks");
});

test("resume uses track id and clamps saved progress", () => {
  assert.deepEqual(
    selectResumeTarget("album:a", tracks, {
      trackId: "t2",
      trackIndex: 0,
      position: 250,
      updatedAt: 1,
    }),
    {
      collectionKey: "album:a",
      track: tracks[1],
      trackIndex: 1,
      position: 200,
    },
  );
});

test("resume falls back to saved index, then the first track", () => {
  assert.equal(
    selectResumeTarget("album:a", tracks, {
      trackId: "removed",
      trackIndex: 1,
      position: 12,
      updatedAt: 1,
    })?.track.id,
    "t2",
  );
  assert.equal(
    selectResumeTarget("album:a", tracks, {
      trackId: "removed",
      trackIndex: 20,
      position: 12,
      updatedAt: 1,
    })?.track.id,
    "t1",
  );
  assert.equal(selectResumeTarget("album:a", [], undefined), null);
});

test("cover flow exposes at most five nearby covers", () => {
  assert.deepEqual(
    coverSlots(8, 4).filter((slot) => !slot.hidden),
    [
      { index: 2, offset: -2, hidden: false },
      { index: 3, offset: -1, hidden: false },
      { index: 4, offset: 0, hidden: false },
      { index: 5, offset: 1, hidden: false },
      { index: 6, offset: 2, hidden: false },
    ],
  );
});

test("horizontal browsing never changes the active playback", () => {
  const before = readyState();
  const result = update(before, { type: "FOCUS_MOVED", delta: 1 });

  assert.equal(result.state.focusedIndex.album, 1);
  assert.deepEqual(result.state.player, before.player);
  assert.deepEqual(result.effects, []);
});

test("changing category only loads browse data", () => {
  const before = readyState();
  const result = update(before, { type: "CATEGORY_SELECTED", category: "playlist" });

  assert.equal(result.state.category, "playlist");
  assert.deepEqual(result.state.player, before.player);
  assert.deepEqual(result.effects, [{ type: "LOAD_LIBRARY", category: "playlist", generation: 0 }]);
});

test("a side cover click only focuses it", () => {
  const before = readyState();
  const result = update(before, { type: "COVER_TAPPED", index: 2 });

  assert.equal(result.state.focusedIndex.album, 2);
  assert.deepEqual(result.state.player, before.player);
  assert.deepEqual(result.effects, []);
});

test("a centered cover click loads its tracks before activation", () => {
  const before = readyState();
  const result = update(before, { type: "COVER_TAPPED", index: 0 });

  assert.equal(result.state.tracks["album:a"].status, "loading");
  assert.equal(result.state.activation?.collectionKey, "album:a");
  assert.deepEqual(result.effects, [
    { type: "PERSIST_ACTIVE_PLAYBACK", wasPlaying: true },
    { type: "LOAD_TRACKS", collection: collections[0], generation: 0 },
  ]);
});

test("late stream responses cannot replace a newer activation", () => {
  const state = {
    ...readyState(),
    player: {
      status: "resolving",
      current: readyState().player.current,
      pending: {
        collectionKey: "album:b",
        track: tracks[1],
        trackIndex: 1,
        position: 15,
      },
      requestId: 9,
    },
  };

  const result = update(state, {
    type: "STREAM_RESOLVED",
    requestId: 8,
    generation: 0,
    url: "https://stale.invalid/audio.mp3",
  });

  assert.deepEqual(result.state, state);
  assert.deepEqual(result.effects, []);
});

test("seeking clamps progress and delegates the audio mutation", () => {
  const before = readyState();
  const result = update(before, { type: "PLAYER_SEEKED", position: 140, updatedAt: 123 });

  assert.equal(result.state.player.current.position, 100);
  assert.deepEqual(result.effects[0], { type: "SEEK_AUDIO", position: 100 });
});

test("startup restore locates its collection after the library arrives", () => {
  const session = {
    category: "playlist",
    collectionId: "saved",
    collectionKey: "playlist:saved",
    trackId: "t2",
    trackIndex: 1,
    position: 23,
    wasPlaying: false,
    updatedAt: 10,
  };
  let result = update(initialState(), { type: "STARTUP_RESTORE_REQUESTED", session });
  result = update(result.state, {
    type: "AUTHENTICATED",
    profile: { id: "user", nickname: "User" },
  });
  assert.deepEqual(result.effects, [
    { type: "RESET_AUDIO" },
    { type: "LOAD_LIBRARY", category: "playlist", generation: 1 },
  ]);

  result = update(result.state, {
    type: "LIBRARY_LOADED",
    category: "playlist",
    generation: 1,
    collections: [
      { ...collections[0], id: "other", type: "playlist" },
      { ...collections[1], id: "saved", type: "playlist" },
    ],
  });

  assert.equal(result.state.focusedIndex.playlist, 1);
  assert.deepEqual(result.state.activation, {
    collectionKey: "playlist:saved",
    requestId: 1,
    autoplay: false,
  });
  assert.equal(result.state.tracks["playlist:saved"].status, "loading");
  assert.deepEqual(result.effects, [{
    type: "LOAD_TRACKS",
    collection: { ...collections[1], id: "saved", type: "playlist" },
    generation: 1,
  }]);
});

test("startup restore preserves the previous paused state when loading audio", () => {
  const target = {
    collectionKey: "album:a",
    track: tracks[0],
    trackIndex: 0,
    position: 17,
  };
  const state = {
    ...readyState(),
    player: {
      status: "resolving",
      pending: target,
      requestId: 4,
      autoplay: false,
    },
  };
  const result = update(state, {
    type: "STREAM_RESOLVED",
    requestId: 4,
    generation: 0,
    url: "https://example.invalid/audio.mp3",
  });

  assert.deepEqual(result.effects, [{
    type: "LOAD_AUDIO",
    playback: { ...target, duration: 100, url: "https://example.invalid/audio.mp3" },
    autoplay: false,
  }]);
});

test("signing in clears playback data and advances the account generation", () => {
  const before = {
    ...readyState(),
    tracks: { "playlist:old": { status: "ready", data: tracks } },
  };
  const result = update(before, {
    type: "AUTHENTICATED",
    profile: { id: "new-account", nickname: "New" },
  });

  assert.equal(result.state.accountGeneration, 1);
  assert.deepEqual(result.state.player, { status: "idle" });
  assert.deepEqual(result.state.tracks, {});
  assert.deepEqual(result.effects, [
    { type: "RESET_AUDIO" },
    { type: "LOAD_LIBRARY", category: "album", generation: 1 },
  ]);
});

test("signing out clears playback and reloads with a new account generation", () => {
  const result = update(readyState(), { type: "LOGGED_OUT" });

  assert.equal(result.state.accountGeneration, 1);
  assert.deepEqual(result.state.player, { status: "idle" });
  assert.deepEqual(result.state.history, {});
  assert.deepEqual(result.effects, [
    { type: "RESET_AUDIO" },
    { type: "LOAD_LIBRARY", category: "album", generation: 1 },
  ]);
});

test("responses from an older account generation are ignored", () => {
  const state = {
    ...readyState(),
    accountGeneration: 2,
    library: { ...readyState().library, album: { status: "loading" } },
  };
  const result = update(state, {
    type: "LIBRARY_LOADED",
    category: "album",
    generation: 1,
    collections,
  });

  assert.deepEqual(result.state, state);
  assert.deepEqual(result.effects, []);
});

test("a stale stream response cannot resume playback after an account switch", () => {
  const state = {
    ...readyState(),
    accountGeneration: 3,
    player: {
      status: "resolving",
      pending: {
        collectionKey: "album:a",
        track: tracks[0],
        trackIndex: 0,
        position: 0,
      },
      requestId: 5,
      autoplay: true,
    },
  };
  const result = update(state, {
    type: "STREAM_RESOLVED",
    requestId: 5,
    generation: 2,
    url: "https://stale.invalid/audio.mp3",
  });

  assert.deepEqual(result.state, state);
  assert.deepEqual(result.effects, []);
});

test("swiping up while the library loads stays on the cover surface", () => {
  const booting = update(initialState(), { type: "BOOT" }).state;
  const result = update(booting, { type: "SURFACE_SET", surface: "tracks" });

  assert.equal(result.state.surface, "covers");
  assert.deepEqual(result.effects, []);
});

test("activating a collection persists the active playback before switching", () => {
  const before = {
    ...readyState(),
    tracks: { "album:a": { status: "ready", data: tracks } },
  };
  const result = update(before, { type: "COVER_TAPPED", index: 0 });

  assert.deepEqual(result.effects[0], { type: "PERSIST_ACTIVE_PLAYBACK", wasPlaying: true });
  assert.equal(result.effects[1].type, "RESOLVE_STREAM");
});

test("selecting a track persists the active playback before switching", () => {
  const before = {
    ...readyState(),
    tracks: { "album:a": { status: "ready", data: tracks } },
  };
  const result = update(before, {
    type: "TRACK_SELECTED",
    collectionKey: "album:a",
    index: 1,
  });

  assert.deepEqual(result.effects[0], { type: "PERSIST_ACTIVE_PLAYBACK", wasPlaying: true });
  assert.equal(result.effects[1].type, "RESOLVE_STREAM");
});

test("toggling a failed stream retries the retained target", () => {
  const failed = {
    collectionKey: "album:a",
    track: tracks[1],
    trackIndex: 1,
    position: 23,
  };
  const state = {
    ...readyState(),
    requestSerial: 7,
    player: { status: "error", failed, message: "temporary failure" },
  };
  const result = update(state, { type: "PLAYER_TOGGLED" });

  assert.equal(result.state.player.status, "resolving");
  assert.equal(result.state.player.requestId, 8);
  assert.deepEqual(result.effects, [{
    type: "RESOLVE_STREAM",
    requestId: 8,
    target: failed,
    generation: 0,
  }]);
});

test("old audio time updates do not cancel a pending stream resolution", () => {
  const pending = {
    collectionKey: "album:a",
    track: tracks[1],
    trackIndex: 1,
    position: 0,
  };
  const state = {
    ...readyState(),
    player: {
      status: "resolving",
      current: readyState().player.current,
      pending,
      requestId: 11,
      autoplay: true,
      currentWasPlaying: true,
    },
  };
  const result = update(state, {
    type: "AUDIO_TIME",
    position: 47,
    duration: 100,
    updatedAt: 1000,
  });

  assert.equal(result.state.player.status, "resolving");
  assert.deepEqual(result.state.player.pending, pending);
  assert.equal(result.state.player.requestId, 11);
  assert.equal(result.state.player.current.position, 47);
  assert.equal(result.effects[0].wasPlaying, true);
});

test("old audio lifecycle events do not cancel a pending stream resolution", () => {
  const resolving = {
    ...readyState(),
    player: {
      status: "resolving",
      current: readyState().player.current,
      pending: {
        collectionKey: "album:b",
        track: tracks[1],
        trackIndex: 1,
        position: 0,
      },
      requestId: 6,
      autoplay: true,
    },
  };

  for (const event of [
    { type: "AUDIO_PLAYING", updatedAt: 10 },
    { type: "AUDIO_PAUSED", updatedAt: 11 },
    { type: "AUDIO_WAITING" },
    { type: "AUDIO_ERROR", message: "old source failed" },
  ]) {
    const result = update(resolving, event);
    assert.equal(result.state.player.status, "resolving");
    assert.equal(result.state.player.requestId, 6);
    assert.equal(result.state.player.pending.track.id, "t2");
  }
});

test("old audio time updates preserve a failed switch target", () => {
  const failed = {
    collectionKey: "album:b",
    track: tracks[1],
    trackIndex: 1,
    position: 0,
  };
  const state = {
    ...readyState(),
    player: {
      status: "error",
      current: readyState().player.current,
      failed,
      message: "stream failed",
      currentWasPlaying: true,
    },
  };

  const result = update(state, {
    type: "AUDIO_TIME",
    position: 45,
    duration: 100,
    updatedAt: 12,
  });

  assert.equal(result.state.player.status, "error");
  assert.equal(result.state.player.failed.track.id, "t2");
  assert.equal(result.state.player.current.position, 45);
  assert.equal(result.effects[0].wasPlaying, true);
});

test("an operational notice does not replace signed-in auth state", () => {
  const before = {
    ...readyState(),
    auth: { status: "signedIn", profile: { id: "42", nickname: "User" } },
  };

  const result = update(before, { type: "NOTICE_SET", message: "退出失败" });

  assert.equal(result.state.auth.status, "signedIn");
  assert.equal(result.state.notice, "退出失败");
});
