export type Category = "album" | "playlist" | "podcast";
export type Surface = "covers" | "tracks";

export interface CollectionSummary {
  id: string;
  type: Category;
  title: string;
  subtitle: string;
  coverUrl: string;
  trackCount?: number;
}

export interface Track {
  id: string;
  title: string;
  artist: string;
  duration: number;
  coverUrl?: string;
}

export interface Profile {
  id: string;
  nickname: string;
  avatarUrl?: string;
}

export interface SavedPosition {
  trackId: string;
  trackIndex: number;
  position: number;
  updatedAt: number;
}

export interface SavedSession extends SavedPosition {
  category: Category;
  collectionId: string;
  collectionKey: string;
  wasPlaying: boolean;
}

export interface ResumeTarget {
  collectionKey: string;
  track: Track;
  trackIndex: number;
  position: number;
}

export interface Playback extends ResumeTarget {
  duration: number;
  url?: string;
}

export type Resource<T> =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "ready"; data: T }
  | { status: "empty" }
  | { status: "error"; message: string };

export type PlayerState =
  | { status: "idle" }
  | { status: "resolving"; current?: Playback; pending: ResumeTarget; requestId: number; autoplay: boolean; currentWasPlaying?: boolean }
  | { status: "buffering" | "paused" | "playing"; current: Playback }
  | { status: "error"; current?: Playback; failed?: ResumeTarget; message: string; currentWasPlaying?: boolean };

export type AuthState =
  | { status: "signedOut" }
  | { status: "sendingCode"; countryCode: string; phone: string }
  | { status: "codeSent"; countryCode: string; phone: string; resendAt: number }
  | { status: "submitting"; countryCode: string; phone: string }
  | { status: "signedIn"; profile: Profile }
  | { status: "error"; countryCode: string; phone: string; phase: "send" | "login"; message: string };

export interface AppState {
  category: Category;
  surface: Surface;
  library: Record<Category, Resource<CollectionSummary[]>>;
  focusedIndex: Record<Category, number>;
  tracks: Record<string, Resource<Track[]>>;
  player: PlayerState;
  activation?: { collectionKey: string; requestId: number; autoplay: boolean };
  startupSession?: SavedSession;
  accountGeneration: number;
  requestSerial: number;
  history: Record<string, SavedPosition>;
  drawerOpen: boolean;
  auth: AuthState;
  notice?: string;
}

export type Event =
  | { type: "BOOT" }
  | { type: "CATEGORY_SELECTED"; category: Category }
  | { type: "RETRY_LIBRARY"; category: Category }
  | { type: "LIBRARY_LOADED"; category: Category; generation: number; collections: CollectionSummary[] }
  | { type: "LIBRARY_FAILED"; category: Category; generation: number; message: string }
  | { type: "FOCUS_MOVED"; delta: -1 | 1 }
  | { type: "COVER_TAPPED"; index: number }
  | { type: "SURFACE_SET"; surface: Surface }
  | { type: "RETRY_TRACKS"; collection: CollectionSummary }
  | { type: "TRACKS_LOADED"; collectionKey: string; generation: number; tracks: Track[] }
  | { type: "TRACKS_FAILED"; collectionKey: string; generation: number; message: string }
  | { type: "TRACK_SELECTED"; collectionKey: string; index: number }
  | { type: "STREAM_RESOLVED"; requestId: number; generation: number; url: string }
  | { type: "STREAM_FAILED"; requestId: number; generation: number; message: string }
  | { type: "PLAYER_TOGGLED" }
  | { type: "PLAYER_SEEKED"; position: number; updatedAt: number }
  | { type: "AUDIO_PLAYING"; updatedAt: number }
  | { type: "AUDIO_PAUSED"; updatedAt: number }
  | { type: "AUDIO_WAITING" }
  | { type: "AUDIO_TIME"; position: number; duration: number; updatedAt: number }
  | { type: "AUDIO_ERROR"; message: string }
  | { type: "DRAWER_SET"; open: boolean }
  | { type: "SEND_CODE"; countryCode: string; phone: string }
  | { type: "CODE_SENT"; resendAt: number }
  | { type: "SUBMIT_CODE"; countryCode: string; phone: string; code: string }
  | { type: "AUTHENTICATED"; profile: Profile }
  | { type: "AUTH_FAILED"; message: string }
  | { type: "HISTORY_LOADED"; history: Record<string, SavedPosition> }
  | { type: "STARTUP_RESTORE_REQUESTED"; session: SavedSession }
  | { type: "LOGOUT" }
  | { type: "LOGGED_OUT" }
  | { type: "NOTICE_SET"; message: string }
  | { type: "NOTICE_CLEARED" };

export type Effect =
  | { type: "LOAD_LIBRARY"; category: Category; generation: number }
  | { type: "LOAD_TRACKS"; collection: CollectionSummary; generation: number }
  | { type: "RESOLVE_STREAM"; requestId: number; target: ResumeTarget; generation: number }
  | { type: "LOAD_AUDIO"; playback: Playback; autoplay: boolean }
  | { type: "RESET_AUDIO" }
  | { type: "PERSIST_ACTIVE_PLAYBACK"; wasPlaying: boolean }
  | { type: "PLAY_AUDIO" }
  | { type: "PAUSE_AUDIO" }
  | { type: "SEEK_AUDIO"; position: number }
  | { type: "SAVE_POSITION"; collectionKey: string; position: SavedPosition; wasPlaying: boolean }
  | { type: "SEND_LOGIN_CODE"; countryCode: string; phone: string }
  | { type: "LOGIN"; countryCode: string; phone: string; code: string }
  | { type: "LOGOUT" };

export interface Transition {
  state: AppState;
  effects: Effect[];
}

export function initialState(history: Record<string, SavedPosition> = {}): AppState {
  return {
    category: "album",
    surface: "covers",
    library: {
      album: { status: "idle" },
      playlist: { status: "idle" },
      podcast: { status: "idle" },
    },
    focusedIndex: { album: 0, playlist: 0, podcast: 0 },
    tracks: {},
    player: { status: "idle" },
    accountGeneration: 0,
    requestSerial: 0,
    history,
    drawerOpen: false,
    auth: { status: "signedOut" },
  };
}

export function collectionKey(type: Category, id: string): string {
  return `${type}:${id}`;
}

export function normalizeCountryCode(value: string): string {
  return value.trim().replace(/^\+/, "");
}

export function moveFocus(current: number, delta: -1 | 1, count: number): number {
  if (count <= 0) return 0;
  return Math.min(count - 1, Math.max(0, current + delta));
}

export function decideCoverTap(
  focusedKey: string,
  tappedKey: string,
): { kind: "focus"; key: string } | { kind: "activate"; key: string } {
  return focusedKey === tappedKey
    ? { kind: "activate", key: tappedKey }
    : { kind: "focus", key: tappedKey };
}

export function classifySwipe(
  dx: number,
  dy: number,
  elapsedMs: number,
): "left" | "right" | "up" | "down" | "tap" | "none" {
  const distance = Math.hypot(dx, dy);
  if (distance < 18) return "tap";
  if (elapsedMs > 650) return "none";
  const horizontal = Math.abs(dx);
  const vertical = Math.abs(dy);
  if (horizontal < vertical * 1.25 && vertical < horizontal * 1.25) return "none";
  if (horizontal > vertical) return dx < 0 ? "left" : "right";
  return dy < 0 ? "up" : "down";
}

export function decideVerticalNavigation(
  surface: Surface,
  gesture: "up" | "down",
  listScrollTop: number,
): Surface {
  if (surface === "covers" && gesture === "up") return "tracks";
  if (surface === "tracks" && gesture === "down" && listScrollTop <= 0) return "covers";
  return surface;
}

export function selectResumeTarget(
  key: string,
  tracks: readonly Track[],
  saved?: SavedPosition,
): ResumeTarget | null {
  if (tracks.length === 0) return null;
  let index = saved ? tracks.findIndex((track) => track.id === saved.trackId) : 0;
  if (index < 0 && saved && saved.trackIndex >= 0 && saved.trackIndex < tracks.length) {
    index = saved.trackIndex;
  }
  if (index < 0) index = 0;
  const track = tracks[index];
  const position = saved
    ? Math.min(track.duration, Math.max(0, saved.position))
    : 0;
  return { collectionKey: key, track, trackIndex: index, position };
}

export function coverSlots(
  count: number,
  focusedIndex: number,
): Array<{ index: number; offset: -2 | -1 | 0 | 1 | 2; hidden: boolean }> {
  return Array.from({ length: count }, (_, index) => {
    const rawOffset = index - focusedIndex;
    const hidden = Math.abs(rawOffset) > 2;
    const offset = Math.min(2, Math.max(-2, rawOffset)) as -2 | -1 | 0 | 1 | 2;
    return { index, offset, hidden };
  });
}

function currentPlayback(player: PlayerState): Playback | undefined {
  return "current" in player ? player.current : undefined;
}

function currentWasPlaying(player: PlayerState): boolean {
  if (player.status === "playing") return true;
  if (player.status === "resolving" || player.status === "error") {
    return player.currentWasPlaying ?? false;
  }
  return false;
}

function focusedCollection(state: AppState): CollectionSummary | undefined {
  const resource = state.library[state.category];
  return resource.status === "ready"
    ? resource.data[state.focusedIndex[state.category]]
    : undefined;
}

function loadTracks(state: AppState, collection: CollectionSummary): Transition {
  const key = collectionKey(collection.type, collection.id);
  return {
    state: { ...state, tracks: { ...state.tracks, [key]: { status: "loading" } } },
    effects: [{ type: "LOAD_TRACKS", collection, generation: state.accountGeneration }],
  };
}

function resolveTarget(
  state: AppState,
  target: ResumeTarget,
  requestId: number,
  autoplay: boolean,
): Transition {
  return {
    state: {
      ...state,
      activation: undefined,
      player: {
        status: "resolving",
        current: currentPlayback(state.player),
        pending: target,
        requestId,
        autoplay,
        currentWasPlaying: currentWasPlaying(state.player),
      },
      notice: undefined,
    },
    effects: [{ type: "RESOLVE_STREAM", requestId, target, generation: state.accountGeneration }],
  };
}

function persistBeforeSwitch(state: AppState, transition: Transition): Transition {
  return currentPlayback(state.player)
    ? {
        ...transition,
        effects: [{
          type: "PERSIST_ACTIVE_PLAYBACK",
          wasPlaying: currentWasPlaying(state.player),
        }, ...transition.effects],
      }
    : transition;
}

function activateCollection(
  state: AppState,
  collection: CollectionSummary,
  autoplay = true,
): Transition {
  const key = collectionKey(collection.type, collection.id);
  const requestId = state.requestSerial + 1;
  const resource = state.tracks[key] ?? { status: "idle" };
  const next = {
    ...state,
    requestSerial: requestId,
    activation: { collectionKey: key, requestId, autoplay },
  };
  if (resource.status === "ready") {
    const target = selectResumeTarget(key, resource.data, state.history[key]);
    const transition = target
      ? resolveTarget(next, target, requestId, autoplay)
      : { state: { ...next, activation: undefined, notice: "这个集合暂无可播放曲目" }, effects: [] };
    return persistBeforeSwitch(state, transition);
  }
  if (resource.status === "empty") {
    return { state: { ...next, activation: undefined, notice: "这个集合暂无可播放曲目" }, effects: [] };
  }
  return persistBeforeSwitch(state, loadTracks(next, collection));
}

export function update(state: AppState, event: Event): Transition {
  switch (event.type) {
    case "BOOT":
    case "RETRY_LIBRARY": {
      const category = event.type === "BOOT" ? state.category : event.category;
      return {
        state: {
          ...state,
          library: { ...state.library, [category]: { status: "loading" } },
        },
        effects: [{ type: "LOAD_LIBRARY", category, generation: state.accountGeneration }],
      };
    }
    case "CATEGORY_SELECTED": {
      const resource = state.library[event.category];
      const shouldLoad = resource.status === "idle";
      return {
        state: {
          ...state,
          category: event.category,
          surface: "covers",
          library: shouldLoad
            ? { ...state.library, [event.category]: { status: "loading" } }
            : state.library,
        },
        effects: shouldLoad
          ? [{ type: "LOAD_LIBRARY", category: event.category, generation: state.accountGeneration }]
          : [],
      };
    }
    case "LIBRARY_LOADED": {
      if (event.generation !== state.accountGeneration) return { state, effects: [] };
      const resource: Resource<CollectionSummary[]> = event.collections.length
        ? { status: "ready", data: event.collections }
        : { status: "empty" };
      const focused = Math.min(
        state.focusedIndex[event.category],
        Math.max(0, event.collections.length - 1),
      );
      const next: AppState = {
        ...state,
        library: { ...state.library, [event.category]: resource },
        focusedIndex: { ...state.focusedIndex, [event.category]: focused },
      };
      if (state.startupSession?.category !== event.category) {
        return { state: next, effects: [] };
      }
      const index = event.collections.findIndex(
        (collection) => collection.id === state.startupSession?.collectionId,
      );
      if (index < 0) {
        return { state: { ...next, startupSession: undefined }, effects: [] };
      }
      const restored = {
        ...next,
        startupSession: undefined,
        focusedIndex: { ...next.focusedIndex, [event.category]: index },
      };
      return activateCollection(restored, event.collections[index], state.startupSession.wasPlaying);
    }
    case "LIBRARY_FAILED":
      if (event.generation !== state.accountGeneration) return { state, effects: [] };
      return {
        state: {
          ...state,
          library: {
            ...state.library,
            [event.category]: { status: "error", message: event.message },
          },
        },
        effects: [],
      };
    case "FOCUS_MOVED": {
      const resource = state.library[state.category];
      const count = resource.status === "ready" ? resource.data.length : 0;
      return {
        state: {
          ...state,
          focusedIndex: {
            ...state.focusedIndex,
            [state.category]: moveFocus(
              state.focusedIndex[state.category],
              event.delta,
              count,
            ),
          },
        },
        effects: [],
      };
    }
    case "COVER_TAPPED": {
      const resource = state.library[state.category];
      if (resource.status !== "ready" || !resource.data[event.index]) {
        return { state, effects: [] };
      }
      if (event.index !== state.focusedIndex[state.category]) {
        return {
          state: {
            ...state,
            focusedIndex: { ...state.focusedIndex, [state.category]: event.index },
          },
          effects: [],
        };
      }
      return activateCollection(state, resource.data[event.index]);
    }
    case "SURFACE_SET": {
      if (event.surface === state.surface) return { state, effects: [] };
      if (event.surface !== "tracks") {
        return { state: { ...state, surface: event.surface }, effects: [] };
      }
      const collection = focusedCollection(state);
      if (!collection) return { state, effects: [] };
      const next = { ...state, surface: event.surface };
      const resource = next.tracks[collectionKey(collection.type, collection.id)];
      return !resource || resource.status === "idle"
        ? loadTracks(next, collection)
        : { state: next, effects: [] };
    }
    case "RETRY_TRACKS":
      return loadTracks(state, event.collection);
    case "TRACKS_LOADED": {
      if (event.generation !== state.accountGeneration) return { state, effects: [] };
      const resource: Resource<Track[]> = event.tracks.length
        ? { status: "ready", data: event.tracks }
        : { status: "empty" };
      const next: AppState = {
        ...state,
        tracks: { ...state.tracks, [event.collectionKey]: resource },
      };
      if (state.activation?.collectionKey !== event.collectionKey) {
        return { state: next, effects: [] };
      }
      const target = selectResumeTarget(
        event.collectionKey,
        event.tracks,
        state.history[event.collectionKey],
      );
      return target
        ? resolveTarget(next, target, state.activation.requestId, state.activation.autoplay)
        : {
            state: { ...next, activation: undefined, notice: "这个集合暂无可播放曲目" },
            effects: [],
          };
    }
    case "TRACKS_FAILED":
      if (event.generation !== state.accountGeneration) return { state, effects: [] };
      return {
        state: {
          ...state,
          activation:
            state.activation?.collectionKey === event.collectionKey
              ? undefined
              : state.activation,
          tracks: {
            ...state.tracks,
            [event.collectionKey]: { status: "error", message: event.message },
          },
          notice: event.message,
        },
        effects: [],
      };
    case "TRACK_SELECTED": {
      const resource = state.tracks[event.collectionKey];
      if (resource?.status !== "ready" || !resource.data[event.index]) {
        return { state, effects: [] };
      }
      const requestId = state.requestSerial + 1;
      return persistBeforeSwitch(state, resolveTarget(
        { ...state, requestSerial: requestId },
        {
          collectionKey: event.collectionKey,
          track: resource.data[event.index],
          trackIndex: event.index,
          position: 0,
        },
        requestId,
        true,
      ));
    }
    case "STREAM_RESOLVED": {
      if (
        event.generation !== state.accountGeneration
        || state.player.status !== "resolving"
        || state.player.requestId !== event.requestId
      ) {
        return { state, effects: [] };
      }
      const playback: Playback = {
        ...state.player.pending,
        duration: state.player.pending.track.duration,
        url: event.url,
      };
      return {
        state: { ...state, player: { status: "buffering", current: playback } },
        effects: [{ type: "LOAD_AUDIO", playback, autoplay: state.player.autoplay }],
      };
    }
    case "STREAM_FAILED": {
      if (
        event.generation !== state.accountGeneration
        || state.player.status !== "resolving"
        || state.player.requestId !== event.requestId
      ) {
        return { state, effects: [] };
      }
      return {
        state: {
          ...state,
          player: {
            status: "error",
            current: state.player.current,
            failed: state.player.pending,
            message: event.message,
            currentWasPlaying: state.player.currentWasPlaying,
          },
        },
        effects: [],
      };
    }
    case "PLAYER_TOGGLED": {
      if (state.player.status === "error" && state.player.failed) {
        const requestId = state.requestSerial + 1;
        return resolveTarget(
          { ...state, requestSerial: requestId },
          state.player.failed,
          requestId,
          true,
        );
      }
      if (state.player.status === "playing" || state.player.status === "buffering") {
        return { state, effects: [{ type: "PAUSE_AUDIO" }] };
      }
      if (state.player.status === "paused") {
        return { state, effects: [{ type: "PLAY_AUDIO" }] };
      }
      return { state, effects: [] };
    }
    case "PLAYER_SEEKED": {
      const previous = currentPlayback(state.player);
      if (!previous) return { state, effects: [] };
      const position = Math.min(previous.duration, Math.max(0, event.position));
      const current = { ...previous, position };
      const saved = toSavedPosition(current, event.updatedAt);
      return {
        state: {
          ...state,
          player: { status: state.player.status === "playing" ? "playing" : "paused", current },
          history: { ...state.history, [current.collectionKey]: saved },
        },
        effects: [
          { type: "SEEK_AUDIO", position },
          {
            type: "SAVE_POSITION",
            collectionKey: current.collectionKey,
            position: saved,
            wasPlaying: state.player.status === "playing",
          },
        ],
      };
    }
    case "AUDIO_PLAYING": {
      const current = currentPlayback(state.player);
      return current
        ? {
            state: state.player.status === "resolving" || state.player.status === "error"
              ? { ...state, player: { ...state.player, currentWasPlaying: true } }
              : { ...state, player: { status: "playing", current } },
            effects: [{
              type: "SAVE_POSITION",
              collectionKey: current.collectionKey,
              position: toSavedPosition(current, event.updatedAt),
              wasPlaying: true,
            }],
          }
        : { state, effects: [] };
    }
    case "AUDIO_PAUSED": {
      const current = currentPlayback(state.player);
      if (!current) return { state, effects: [] };
      const saved = toSavedPosition(current, event.updatedAt);
      return {
        state: {
          ...state,
          player: state.player.status === "resolving" || state.player.status === "error"
            ? { ...state.player, currentWasPlaying: false }
            : { status: "paused", current },
          history: { ...state.history, [current.collectionKey]: saved },
        },
        effects: [{
          type: "SAVE_POSITION",
          collectionKey: current.collectionKey,
          position: saved,
          wasPlaying: false,
        }],
      };
    }
    case "AUDIO_WAITING": {
      const current = currentPlayback(state.player);
      if (state.player.status === "resolving" || state.player.status === "error") {
        return { state, effects: [] };
      }
      return current
        ? { state: { ...state, player: { status: "buffering", current } }, effects: [] }
        : { state, effects: [] };
    }
    case "AUDIO_TIME": {
      const previous = currentPlayback(state.player);
      if (!previous) return { state, effects: [] };
      const position = Math.min(event.duration || previous.duration, Math.max(0, event.position));
      const current = { ...previous, position, duration: event.duration || previous.duration };
      const saved = toSavedPosition(current, event.updatedAt);
      const shouldSave = Math.floor(previous.position / 5) !== Math.floor(position / 5);
      const player: PlayerState = state.player.status === "resolving"
        ? { ...state.player, current }
        : state.player.status === "error"
          ? { ...state.player, current }
        : { status: state.player.status === "playing" ? "playing" : "paused", current };
      return {
        state: {
          ...state,
          player,
          history: { ...state.history, [current.collectionKey]: saved },
        },
        effects: shouldSave
          ? [{
              type: "SAVE_POSITION",
              collectionKey: current.collectionKey,
              position: saved,
              wasPlaying: currentWasPlaying(state.player),
            }]
          : [],
      };
    }
    case "AUDIO_ERROR": {
      if (state.player.status === "resolving" || state.player.status === "error") {
        return { state, effects: [] };
      }
      const current = currentPlayback(state.player);
      return {
        state: { ...state, player: { status: "error", current, failed: current, message: event.message } },
        effects: [],
      };
    }
    case "DRAWER_SET":
      return { state: { ...state, drawerOpen: event.open }, effects: [] };
    case "SEND_CODE":
      return {
        state: {
          ...state,
          auth: {
            status: "sendingCode",
            countryCode: event.countryCode,
            phone: event.phone,
          },
        },
        effects: [{ type: "SEND_LOGIN_CODE", countryCode: event.countryCode, phone: event.phone }],
      };
    case "CODE_SENT": {
      if (state.auth.status !== "sendingCode") return { state, effects: [] };
      return {
        state: {
          ...state,
          auth: {
            status: "codeSent",
            countryCode: state.auth.countryCode,
            phone: state.auth.phone,
            resendAt: event.resendAt,
          },
        },
        effects: [],
      };
    }
    case "SUBMIT_CODE":
      return {
        state: {
          ...state,
          auth: {
            status: "submitting",
            countryCode: event.countryCode,
            phone: event.phone,
          },
        },
        effects: [
          { type: "LOGIN", countryCode: event.countryCode, phone: event.phone, code: event.code },
        ],
      };
    case "AUTHENTICATED":
      {
        const category = state.startupSession?.category ?? state.category;
        const generation = state.accountGeneration + 1;
      return {
        state: {
          ...state,
          category,
          surface: "covers",
          accountGeneration: generation,
          requestSerial: 0,
          focusedIndex: { album: 0, playlist: 0, podcast: 0 },
          tracks: {},
          player: { status: "idle" },
          activation: undefined,
          auth: { status: "signedIn", profile: event.profile },
          library: {
            album: category === "album" ? { status: "loading" } : { status: "idle" },
            playlist: category === "playlist" ? { status: "loading" } : { status: "idle" },
            podcast: category === "podcast" ? { status: "loading" } : { status: "idle" },
          },
        },
        effects: [
          { type: "RESET_AUDIO" },
          { type: "LOAD_LIBRARY", category, generation },
        ],
      };
      }
    case "AUTH_FAILED": {
      const countryCode = "countryCode" in state.auth ? state.auth.countryCode : "86";
      const phone = "phone" in state.auth ? state.auth.phone : "";
      const phase = state.auth.status === "submitting" ? "login" : "send";
      return {
        state: {
          ...state,
          auth: { status: "error", countryCode, phone, phase, message: event.message },
        },
        effects: [],
      };
    }
    case "HISTORY_LOADED":
      return { state: { ...state, history: event.history }, effects: [] };
    case "STARTUP_RESTORE_REQUESTED":
      return {
        state: { ...state, category: event.session.category, startupSession: event.session },
        effects: [],
      };
    case "LOGOUT":
      return { state, effects: [{ type: "LOGOUT" }] };
    case "LOGGED_OUT":
      {
      const generation = state.accountGeneration + 1;
      return {
        state: {
          ...state,
          surface: "covers",
          accountGeneration: generation,
          requestSerial: 0,
          auth: { status: "signedOut" },
          library: {
            album: state.category === "album" ? { status: "loading" } : { status: "idle" },
            playlist: state.category === "playlist" ? { status: "loading" } : { status: "idle" },
            podcast: state.category === "podcast" ? { status: "loading" } : { status: "idle" },
          },
          focusedIndex: { album: 0, playlist: 0, podcast: 0 },
          tracks: {},
          player: { status: "idle" },
          activation: undefined,
          history: {},
          startupSession: undefined,
        },
        effects: [
          { type: "RESET_AUDIO" },
          { type: "LOAD_LIBRARY", category: state.category, generation },
        ],
      };
      }
    case "NOTICE_SET":
      return { state: { ...state, notice: event.message }, effects: [] };
    case "NOTICE_CLEARED":
      return { state: { ...state, notice: undefined }, effects: [] };
  }
}

function toSavedPosition(playback: Playback, updatedAt: number): SavedPosition {
  return {
    trackId: playback.track.id,
    trackIndex: playback.trackIndex,
    position: playback.position,
    updatedAt,
  };
}
