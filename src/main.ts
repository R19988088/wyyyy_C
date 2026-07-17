import { invoke } from "@tauri-apps/api/core";

import {
  collectionKey,
  initialState,
  update,
  type AppState,
  type CollectionSummary,
  type Effect,
  type Event,
  type Profile,
  type SavedPosition,
  type SavedSession,
  type Track,
} from "./state.ts";
import { createView } from "./view.ts";

const audioElement = document.querySelector<HTMLAudioElement>("#audio");
if (!audioElement) throw new Error("Missing audio element");
const audio: HTMLAudioElement = audioElement;

const positionsStorageKey = "wyyyy.playback-state.v1";
let activeAccountId = "guest";
let state: AppState = initialState(readHistory(activeAccountId));
const view = createView(dispatch);
let audioLoadSerial = 0;
let pendingMetadataHandler: (() => void) | undefined;

function readableError(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (error && typeof error === "object" && "message" in error) return String(error.message);
  return "请求失败，请稍后重试";
}

function handleExpiredSession(error: unknown): boolean {
  if (activeAccountId === "guest" || !readableError(error).includes("登录已失效")) return false;
  persistActivePlayback();
  activeAccountId = "guest";
  dispatch({ type: "LOGGED_OUT" });
  return true;
}

interface AccountPlaybackState {
  positions: Record<string, SavedPosition>;
  session?: SavedSession;
}

function readPositionStore(): Record<string, AccountPlaybackState> {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(positionsStorageKey) ?? "{}");
    return parsed && typeof parsed === "object"
      ? parsed as Record<string, AccountPlaybackState>
      : {};
  } catch {
    return {};
  }
}

function readHistory(accountId: string): Record<string, SavedPosition> {
  return readPositionStore()[accountId]?.positions ?? {};
}

function readSession(accountId: string): SavedSession | undefined {
  return readPositionStore()[accountId]?.session;
}

function savePosition(key: string, position: SavedPosition, wasPlaying: boolean): void {
  const store = readPositionStore();
  const separator = key.indexOf(":");
  const category = key.slice(0, separator) as SavedSession["category"];
  const collectionId = key.slice(separator + 1);
  const previous = store[activeAccountId] ?? { positions: {} };
  store[activeAccountId] = {
    positions: { ...previous.positions, [key]: position },
    session: {
      ...position,
      category,
      collectionId,
      collectionKey: key,
      wasPlaying,
    },
  };
  localStorage.setItem(positionsStorageKey, JSON.stringify(store));
}

function unwrapList<T>(response: T[] | { items: T[] }): T[] {
  return Array.isArray(response) ? response : response.items;
}

function dispatch(event: Event): void {
  const transition = update(state, event);
  state = transition.state;
  view.render(state);
  for (const effect of transition.effects) void runEffect(effect);
}

async function runEffect(effect: Effect): Promise<void> {
  switch (effect.type) {
    case "LOAD_LIBRARY":
      try {
        const response = await invoke<CollectionSummary[] | { items: CollectionSummary[] }>(
          "get_library",
          { category: effect.category },
        );
        dispatch({
          type: "LIBRARY_LOADED",
          category: effect.category,
          generation: effect.generation,
          collections: unwrapList(response),
        });
      } catch (error) {
        if (!handleExpiredSession(error)) {
          dispatch({
            type: "LIBRARY_FAILED",
            category: effect.category,
            generation: effect.generation,
            message: readableError(error),
          });
        }
      }
      return;
    case "LOAD_TRACKS": {
      const key = collectionKey(effect.collection.type, effect.collection.id);
      try {
        const response = await invoke<Track[] | { items: Track[] }>("get_collection_tracks", {
          collectionType: effect.collection.type,
          collectionId: effect.collection.id,
        });
        dispatch({
          type: "TRACKS_LOADED",
          collectionKey: key,
          generation: effect.generation,
          tracks: unwrapList(response),
        });
      } catch (error) {
        if (!handleExpiredSession(error)) {
          dispatch({
            type: "TRACKS_FAILED",
            collectionKey: key,
            generation: effect.generation,
            message: readableError(error),
          });
        }
      }
      return;
    }
    case "RESOLVE_STREAM":
      try {
        const response = await invoke<string | { url: string }>("get_stream_url", {
          collectionKey: effect.target.collectionKey,
          trackId: effect.target.track.id,
        });
        const url = typeof response === "string" ? response : response.url;
        if (!url) throw new Error("未获取到可播放地址");
        dispatch({
          type: "STREAM_RESOLVED",
          requestId: effect.requestId,
          generation: effect.generation,
          url,
        });
      } catch (error) {
        if (!handleExpiredSession(error)) {
          dispatch({
            type: "STREAM_FAILED",
            requestId: effect.requestId,
            generation: effect.generation,
            message: readableError(error),
          });
        }
      }
      return;
    case "LOAD_AUDIO": {
      const loadSerial = ++audioLoadSerial;
      if (pendingMetadataHandler) {
        audio.removeEventListener("loadedmetadata", pendingMetadataHandler);
        pendingMetadataHandler = undefined;
      }
      const startPlayback = (): void => {
        if (loadSerial !== audioLoadSerial) return;
        pendingMetadataHandler = undefined;
        audio.currentTime = Math.min(effect.playback.position, audio.duration || effect.playback.duration);
        if (effect.autoplay) {
          void audio.play().catch(() => dispatch({ type: "AUDIO_PAUSED", updatedAt: Date.now() }));
        } else dispatch({ type: "AUDIO_PAUSED", updatedAt: Date.now() });
      };
      audio.src = effect.playback.url ?? "";
      audio.load();
      if (audio.readyState >= HTMLMediaElement.HAVE_METADATA) startPlayback();
      else {
        pendingMetadataHandler = startPlayback;
        audio.addEventListener("loadedmetadata", startPlayback, { once: true });
      }
      return;
    }
    case "RESET_AUDIO":
      audioLoadSerial += 1;
      if (pendingMetadataHandler) {
        audio.removeEventListener("loadedmetadata", pendingMetadataHandler);
        pendingMetadataHandler = undefined;
      }
      audio.pause();
      audio.removeAttribute("src");
      audio.load();
      return;
    case "PERSIST_ACTIVE_PLAYBACK":
      persistActivePlayback(effect.wasPlaying);
      return;
    case "PLAY_AUDIO":
      void audio.play().catch((error) => dispatch({ type: "AUDIO_ERROR", message: readableError(error) }));
      return;
    case "PAUSE_AUDIO":
      audio.pause();
      return;
    case "SEEK_AUDIO":
      audio.currentTime = effect.position;
      return;
    case "SAVE_POSITION":
      savePosition(effect.collectionKey, effect.position, effect.wasPlaying);
      return;
    case "SEND_LOGIN_CODE":
      try {
        await invoke("send_login_code", {
          countryCode: effect.countryCode,
          phone: effect.phone,
        });
        dispatch({ type: "CODE_SENT", resendAt: Date.now() + 60_000 });
      } catch (error) {
        dispatch({ type: "AUTH_FAILED", message: readableError(error) });
      }
      return;
    case "LOGIN":
      try {
        const profile = await invoke<Profile>("login_with_code", {
          countryCode: effect.countryCode,
          phone: effect.phone,
          code: effect.code,
        });
        persistActivePlayback();
        activeAccountId = profile.id;
        dispatch({ type: "HISTORY_LOADED", history: readHistory(activeAccountId) });
        const session = readSession(activeAccountId);
        if (session) dispatch({ type: "STARTUP_RESTORE_REQUESTED", session });
        dispatch({ type: "AUTHENTICATED", profile });
      } catch (error) {
        dispatch({ type: "AUTH_FAILED", message: readableError(error) });
      }
      return;
    case "LOGOUT":
      try {
        persistActivePlayback();
        await invoke("logout");
        activeAccountId = "guest";
        dispatch({ type: "LOGGED_OUT" });
      } catch (error) {
        dispatch({ type: "NOTICE_SET", message: readableError(error) });
      }
  }
}

audio.addEventListener("playing", () => dispatch({ type: "AUDIO_PLAYING", updatedAt: Date.now() }));
audio.addEventListener("pause", () => dispatch({ type: "AUDIO_PAUSED", updatedAt: Date.now() }));
audio.addEventListener("waiting", () => dispatch({ type: "AUDIO_WAITING" }));
audio.addEventListener("timeupdate", () => {
  dispatch({
    type: "AUDIO_TIME",
    position: audio.currentTime,
    duration: Number.isFinite(audio.duration) ? audio.duration : 0,
    updatedAt: Date.now(),
  });
});
audio.addEventListener("error", () => {
  const message = audio.error?.message || "音频载入失败";
  dispatch({ type: "AUDIO_ERROR", message });
});

function persistActivePlayback(wasPlaying = state.player.status === "playing"): void {
  if (!("current" in state.player) || !state.player.current) return;
  const current = state.player.current;
  savePosition(current.collectionKey, {
    trackId: current.track.id,
    trackIndex: current.trackIndex,
    position: Number.isFinite(audio.currentTime) ? audio.currentTime : current.position,
    updatedAt: Date.now(),
  }, wasPlaying);
}

window.addEventListener("pagehide", () => persistActivePlayback());
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") persistActivePlayback();
});

async function start(): Promise<void> {
  view.render(state);
  try {
    const profile = await invoke<Profile | null>("restore_session");
    if (profile) {
      activeAccountId = profile.id;
      dispatch({ type: "HISTORY_LOADED", history: readHistory(activeAccountId) });
      const session = readSession(activeAccountId);
      if (session) dispatch({ type: "STARTUP_RESTORE_REQUESTED", session });
      dispatch({ type: "AUTHENTICATED", profile });
      return;
    }
  } catch {
    // A missing or expired session is the normal signed-out startup path.
  }
  dispatch({ type: "BOOT" });
}

void start();
