import {
  classifySwipe,
  collectionKey,
  coverSlots,
  decideVerticalNavigation,
  type AppState,
  type AuthState,
  type Category,
  type CollectionSummary,
  type Event,
  type Playback,
  type Resource,
  type Track,
} from "./state.ts";

type Dispatch = (event: Event) => void;

export interface View {
  render(state: AppState): void;
}

const categoryLabels: Record<Category, string> = {
  album: "专辑",
  playlist: "歌单",
  podcast: "播客",
};

function required<T extends Element>(selector: string): T {
  const node = document.querySelector<T>(selector);
  if (!node) throw new Error(`Missing UI element: ${selector}`);
  return node;
}

function currentPlayback(state: AppState): Playback | undefined {
  return "current" in state.player ? state.player.current : undefined;
}

function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";
  const whole = Math.floor(seconds);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
}

function focusedCollection(state: AppState): CollectionSummary | undefined {
  const resource = state.library[state.category];
  return resource.status === "ready"
    ? resource.data[state.focusedIndex[state.category]]
    : undefined;
}

function stateBlock(
  kind: "loading" | "empty" | "error",
  title: string,
  message?: string,
  action?: { label: string; name: string },
): HTMLElement {
  const block = document.createElement("div");
  block.className = `state-block state-${kind}`;
  if (kind === "loading") {
    const spinner = document.createElement("span");
    spinner.className = "spinner";
    spinner.setAttribute("aria-hidden", "true");
    block.append(spinner);
  }
  const heading = document.createElement("strong");
  heading.textContent = title;
  block.append(heading);
  if (message) {
    const detail = document.createElement("p");
    detail.textContent = message;
    block.append(detail);
  }
  if (action) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "secondary-button";
    button.dataset.action = action.name;
    button.textContent = action.label;
    block.append(button);
  }
  return block;
}

function skeletonCovers(): DocumentFragment {
  const fragment = document.createDocumentFragment();
  for (const offset of [-2, -1, 0, 1, 2]) {
    const item = document.createElement("div");
    item.className = "cover cover-skeleton";
    item.dataset.offset = String(offset);
    fragment.append(item);
  }
  return fragment;
}

function trackRows(tracks: readonly Track[], key: string, active?: Playback): DocumentFragment {
  const fragment = document.createDocumentFragment();
  tracks.forEach((track, index) => {
    const row = document.createElement("button");
    row.type = "button";
    row.className = "track-row";
    row.dataset.trackIndex = String(index);
    const isActive = active?.collectionKey === key && active.track.id === track.id;
    if (isActive) row.classList.add("is-playing");
    row.setAttribute("aria-current", isActive ? "true" : "false");

    const number = document.createElement("span");
    number.className = "track-number";
    number.textContent = isActive ? "▶" : String(index + 1).padStart(2, "0");
    const copy = document.createElement("span");
    copy.className = "track-copy";
    const title = document.createElement("strong");
    title.textContent = track.title;
    const artist = document.createElement("span");
    artist.textContent = track.artist;
    copy.append(title, artist);
    const duration = document.createElement("time");
    duration.textContent = formatTime(track.duration);
    row.append(number, copy, duration);
    fragment.append(row);
  });
  return fragment;
}

export function createView(dispatch: Dispatch): View {
  const content = required<HTMLElement>("#content");
  const topbar = required<HTMLElement>(".topbar");
  const coverSurface = required<HTMLElement>("#cover-surface");
  const trackSurface = required<HTMLElement>("#track-surface");
  const coverflow = required<HTMLElement>("#coverflow");
  const collectionCopy = required<HTMLElement>("#collection-copy");
  const libraryState = required<HTMLElement>("#library-state");
  const trackScroll = required<HTMLElement>("#track-scroll");
  const trackList = required<HTMLElement>("#track-list");
  const trackTitle = required<HTMLElement>("#track-title");
  const trackSubtitle = required<HTMLElement>("#track-subtitle");
  const playerTitle = required<HTMLElement>("#player-title");
  const playerArtist = required<HTMLElement>("#player-artist");
  const playerPosition = required<HTMLElement>("#player-position");
  const playerDuration = required<HTMLElement>("#player-duration");
  const playerProgress = required<HTMLInputElement>("#player-progress");
  const playerToggle = required<HTMLButtonElement>("#player-toggle");
  const playerError = required<HTMLElement>("#player-error");
  const player = required<HTMLElement>("#player");
  const drawerLayer = required<HTMLElement>("#drawer-layer");
  const settingsDrawer = required<HTMLElement>(".settings-drawer");
  const openSettings = required<HTMLButtonElement>("#open-settings");
  const closeSettings = required<HTMLButtonElement>("#close-settings");
  const authPanel = required<HTMLElement>("#auth-panel");
  const notice = required<HTMLElement>("#notice");
  const noticeText = required<HTMLElement>("#notice-text");

  let latestState: AppState;
  let coversSignature = "";
  let tracksSignature = "";
  let authSignature = "";
  let drawerWasOpen = false;
  let coverGesture: { x: number; y: number; at: number; pointerId: number } | undefined;
  let suppressCoverClickUntil = 0;

  document.querySelectorAll<HTMLButtonElement>("[data-category]").forEach((button) => {
    button.addEventListener("click", () => {
      dispatch({ type: "CATEGORY_SELECTED", category: button.dataset.category as Category });
    });
  });
  openSettings.addEventListener("click", () => dispatch({ type: "DRAWER_SET", open: true }));
  closeSettings.addEventListener("click", () => dispatch({ type: "DRAWER_SET", open: false }));
  required("#drawer-backdrop").addEventListener("click", () => dispatch({ type: "DRAWER_SET", open: false }));
  required("#close-tracks").addEventListener("click", () => dispatch({ type: "SURFACE_SET", surface: "covers" }));
  required("#close-notice").addEventListener("click", () => dispatch({ type: "NOTICE_CLEARED" }));
  playerToggle.addEventListener("click", () => dispatch({ type: "PLAYER_TOGGLED" }));
  playerProgress.addEventListener("input", () => {
    dispatch({ type: "PLAYER_SEEKED", position: Number(playerProgress.value), updatedAt: Date.now() });
  });

  document.addEventListener("keydown", (event) => {
    if (!latestState.drawerOpen) return;
    if (event.key === "Escape") {
      event.preventDefault();
      dispatch({ type: "DRAWER_SET", open: false });
      return;
    }
    if (event.key === "Tab") {
      const focusable = Array.from(settingsDrawer.querySelectorAll<HTMLElement>(
        'button:not([disabled]), input:not([disabled]), [href], [tabindex]:not([tabindex="-1"])',
      )).filter((element) => !element.hidden);
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && (document.activeElement === first || !settingsDrawer.contains(document.activeElement))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (document.activeElement === last || !settingsDrawer.contains(document.activeElement))) {
        event.preventDefault();
        first.focus();
      }
    }
  });

  coverflow.addEventListener("click", (event) => {
    if (performance.now() < suppressCoverClickUntil) return;
    const button = (event.target as Element).closest<HTMLButtonElement>("[data-cover-index]");
    if (button) dispatch({ type: "COVER_TAPPED", index: Number(button.dataset.coverIndex) });
  });
  coverflow.addEventListener("pointerdown", (event) => {
    if (!event.isPrimary) return;
    coverGesture = { x: event.clientX, y: event.clientY, at: performance.now(), pointerId: event.pointerId };
    coverflow.setPointerCapture(event.pointerId);
  });
  coverflow.addEventListener("pointerup", (event) => {
    if (!coverGesture || coverGesture.pointerId !== event.pointerId) return;
    const gesture = classifySwipe(
      event.clientX - coverGesture.x,
      event.clientY - coverGesture.y,
      performance.now() - coverGesture.at,
    );
    coverGesture = undefined;
    if (gesture === "left" || gesture === "right") {
      suppressCoverClickUntil = performance.now() + 320;
      dispatch({ type: "FOCUS_MOVED", delta: gesture === "left" ? 1 : -1 });
    } else if (gesture === "up") {
      suppressCoverClickUntil = performance.now() + 320;
      dispatch({ type: "SURFACE_SET", surface: "tracks" });
    }
  });
  coverflow.addEventListener("pointercancel", () => {
    coverGesture = undefined;
  });

  let listTouch: { x: number; y: number; at: number; scrollTop: number } | undefined;
  trackScroll.addEventListener("touchstart", (event) => {
    const touch = event.changedTouches[0];
    listTouch = { x: touch.clientX, y: touch.clientY, at: performance.now(), scrollTop: trackScroll.scrollTop };
  }, { passive: true });
  trackScroll.addEventListener("touchend", (event) => {
    if (!listTouch) return;
    const touch = event.changedTouches[0];
    const gesture = classifySwipe(
      touch.clientX - listTouch.x,
      touch.clientY - listTouch.y,
      performance.now() - listTouch.at,
    );
    if (gesture === "down") {
      const surface = decideVerticalNavigation("tracks", "down", listTouch.scrollTop);
      if (surface === "covers") dispatch({ type: "SURFACE_SET", surface });
    }
    listTouch = undefined;
  }, { passive: true });

  libraryState.addEventListener("click", (event) => {
    const button = (event.target as Element).closest<HTMLButtonElement>("[data-action=retry-library]");
    if (button) dispatch({ type: "RETRY_LIBRARY", category: latestState.category });
  });
  trackList.addEventListener("click", (event) => {
    const row = (event.target as Element).closest<HTMLButtonElement>("[data-track-index]");
    const collection = focusedCollection(latestState);
    if (row && collection) {
      dispatch({
        type: "TRACK_SELECTED",
        collectionKey: collectionKey(collection.type, collection.id),
        index: Number(row.dataset.trackIndex),
      });
      return;
    }
    const retry = (event.target as Element).closest<HTMLButtonElement>("[data-action=retry-tracks]");
    if (retry && collection) dispatch({ type: "RETRY_TRACKS", collection });
  });

  authPanel.addEventListener("submit", (event) => {
    event.preventDefault();
    const form = event.target as HTMLFormElement;
    const data = new FormData(form);
    const countryCode = String(data.get("countryCode") ?? "+86").trim();
    const phone = String(data.get("phone") ?? "").trim();
    if (form.id === "phone-form") {
      dispatch({ type: "SEND_CODE", countryCode, phone });
    } else if (form.id === "code-form") {
      dispatch({ type: "SUBMIT_CODE", countryCode, phone, code: String(data.get("code") ?? "").trim() });
    }
  });
  authPanel.addEventListener("click", (event) => {
    const action = (event.target as Element).closest<HTMLButtonElement>("[data-auth-action]")?.dataset.authAction;
    if (action === "logout") dispatch({ type: "LOGOUT" });
    if (action === "resend") {
      const countryCode = authPanel.querySelector<HTMLInputElement>("[name=countryCode]")?.value ?? "+86";
      const phone = authPanel.querySelector<HTMLInputElement>("[name=phone]")?.value ?? "";
      dispatch({ type: "SEND_CODE", countryCode, phone });
    }
  });

  function renderCovers(state: AppState): void {
    const resource = state.library[state.category];
    const active = currentPlayback(state);
    const signature = JSON.stringify([
      state.category,
      state.focusedIndex[state.category],
      resource,
      active?.collectionKey,
    ]);
    if (signature === coversSignature) return;
    coversSignature = signature;
    coverflow.replaceChildren();
    collectionCopy.replaceChildren();
    libraryState.replaceChildren();

    if (resource.status === "loading" || resource.status === "idle") {
      coverflow.append(skeletonCovers());
      collectionCopy.append(stateBlock("loading", `正在载入${categoryLabels[state.category]}`));
      return;
    }
    if (resource.status === "empty") {
      libraryState.append(stateBlock("empty", `暂无${categoryLabels[state.category]}`, "登录账号中还没有这一类收藏。"));
      return;
    }
    if (resource.status === "error") {
      libraryState.append(stateBlock("error", `${categoryLabels[state.category]}载入失败`, resource.message, {
        label: "重试",
        name: "retry-library",
      }));
      return;
    }

    const focused = state.focusedIndex[state.category];
    for (const slot of coverSlots(resource.data.length, focused)) {
      if (slot.hidden) continue;
      const collection = resource.data[slot.index];
      const key = collectionKey(collection.type, collection.id);
      const button = document.createElement("button");
      button.type = "button";
      button.className = "cover";
      button.dataset.coverIndex = String(slot.index);
      button.dataset.offset = String(slot.offset);
      if (active?.collectionKey === key) button.classList.add("is-playing");
      button.setAttribute("aria-pressed", slot.offset === 0 ? "true" : "false");
      button.setAttribute(
        "aria-label",
        slot.offset === 0 ? `${collection.title}，再次点击播放` : `${collection.title}，点击居中`,
      );
      const fallback = document.createElement("span");
      fallback.className = "cover-fallback";
      fallback.textContent = collection.title.trim().charAt(0) || "♪";
      if (collection.coverUrl) {
        const image = document.createElement("img");
        image.src = collection.coverUrl;
        image.alt = "";
        image.draggable = false;
        image.loading = Math.abs(slot.offset) > 1 ? "lazy" : "eager";
        image.addEventListener("error", () => image.remove(), { once: true });
        button.append(image);
      }
      button.append(fallback);
      coverflow.append(button);
    }
    const collection = resource.data[focused];
    if (collection) {
      const title = document.createElement("h1");
      title.textContent = collection.title;
      const subtitle = document.createElement("p");
      subtitle.textContent = collection.subtitle || categoryLabels[collection.type];
      collectionCopy.append(title, subtitle);
    }
  }

  function renderTracks(state: AppState): void {
    const collection = focusedCollection(state);
    const key = collection ? collectionKey(collection.type, collection.id) : "";
    const resource: Resource<Track[]> = key
      ? state.tracks[key] ?? { status: "loading" }
      : { status: "empty" };
    const active = currentPlayback(state);
    const signature = JSON.stringify([collection, resource, active?.collectionKey, active?.track.id]);
    if (signature === tracksSignature) return;
    tracksSignature = signature;
    trackList.replaceChildren();
    trackTitle.textContent = collection?.title ?? "曲目";
    trackSubtitle.textContent = collection?.subtitle ?? "";
    if (resource.status === "loading" || resource.status === "idle") {
      const fragment = document.createDocumentFragment();
      for (let index = 0; index < 7; index += 1) {
        const row = document.createElement("div");
        row.className = "track-row track-skeleton";
        fragment.append(row);
      }
      trackList.append(fragment);
    } else if (resource.status === "empty") {
      trackList.append(stateBlock("empty", "暂无曲目"));
    } else if (resource.status === "error") {
      trackList.append(stateBlock("error", "曲目载入失败", resource.message, {
        label: "重试",
        name: "retry-tracks",
      }));
    } else {
      trackList.append(trackRows(resource.data, key, active));
      trackSubtitle.textContent = `${collection?.subtitle ?? ""} · ${resource.data.length} 首`;
    }
  }

  function renderPlayer(state: AppState): void {
    const playback = currentPlayback(state);
    const pending = state.player.status === "resolving" ? state.player.pending : undefined;
    const failed = state.player.status === "error" ? state.player.failed : undefined;
    const shown = pending ?? failed ?? playback;
    playerTitle.textContent = shown?.track.title ?? "尚未播放";
    playerArtist.textContent = shown?.track.artist ?? "暂无曲目";
    const position = pending?.position ?? failed?.position ?? playback?.position ?? 0;
    const duration = pending?.track.duration ?? failed?.track.duration ?? playback?.duration ?? 0;
    playerPosition.textContent = formatTime(position);
    playerDuration.textContent = formatTime(duration);
    playerProgress.max = String(Math.max(1, duration));
    playerProgress.value = String(Math.min(position, duration));
    playerProgress.disabled = !playback || Boolean(pending) || Boolean(failed);
    const retryable = Boolean(failed);
    const playing = state.player.status === "playing" || state.player.status === "buffering";
    playerToggle.textContent = retryable ? "↻" : playing ? "Ⅱ" : "▶︎";
    playerToggle.ariaLabel = retryable ? "重试播放" : playing ? "暂停" : "播放";
    playerToggle.title = retryable ? "重试播放" : playing ? "暂停" : "播放";
    playerToggle.disabled = (!playback && !retryable) || state.player.status === "resolving";
    playerToggle.classList.toggle("is-loading", state.player.status === "buffering" || state.player.status === "resolving");
    const error = state.player.status === "error" ? state.player.message : "";
    playerError.textContent = error;
    playerError.hidden = !error;
  }

  function renderAuth(auth: AuthState): void {
    const signature = JSON.stringify(auth);
    if (signature === authSignature) return;
    authSignature = signature;
    authPanel.replaceChildren();
    const section = document.createElement("section");
    section.className = "account-section";
    const heading = document.createElement("h3");
    heading.textContent = "网易云账号";
    section.append(heading);

    if (auth.status === "signedIn") {
      const account = document.createElement("div");
      account.className = "account-profile";
      const avatar = document.createElement("span");
      avatar.textContent = auth.profile.nickname.trim().charAt(0) || "云";
      const nickname = document.createElement("strong");
      nickname.textContent = auth.profile.nickname;
      account.append(avatar, nickname);
      const logout = document.createElement("button");
      logout.type = "button";
      logout.className = "secondary-button wide-button";
      logout.dataset.authAction = "logout";
      logout.textContent = "退出登录";
      section.append(account, logout);
      authPanel.append(section);
      return;
    }

    const countryCode = "countryCode" in auth ? auth.countryCode : "+86";
    const phone = "phone" in auth ? auth.phone : "";
    const busy = auth.status === "sendingCode" || auth.status === "submitting";
    const hasCode = auth.status === "codeSent"
      || auth.status === "submitting"
      || (auth.status === "error" && auth.phase === "login");
    const phoneForm = document.createElement("form");
    phoneForm.id = "phone-form";
    phoneForm.className = "settings-form phone-form";
    phoneForm.innerHTML = `
      <label><span>国家/地区</span><input name="countryCode" inputmode="tel" autocomplete="tel-country-code" required /></label>
      <label class="phone-field"><span>手机号</span><input name="phone" inputmode="numeric" autocomplete="tel-national" pattern="[0-9]{5,15}" required /></label>
      <button class="primary-button" type="submit">${auth.status === "sendingCode" ? "发送中…" : "发送验证码"}</button>
    `;
    const countryInput = phoneForm.elements.namedItem("countryCode") as HTMLInputElement;
    const phoneInput = phoneForm.elements.namedItem("phone") as HTMLInputElement;
    countryInput.value = countryCode;
    phoneInput.value = phone;
    Array.from(phoneForm.elements).forEach((element) => ((element as HTMLInputElement).disabled = busy || hasCode));
    section.append(phoneForm);

    if (hasCode) {
      const codeForm = document.createElement("form");
      codeForm.id = "code-form";
      codeForm.className = "settings-form code-form";
      codeForm.innerHTML = `
        <input type="hidden" name="countryCode" />
        <input type="hidden" name="phone" />
        <label><span>验证码</span><input name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{4,8}" required autofocus /></label>
        <button class="primary-button" type="submit">${auth.status === "submitting" ? "登录中…" : "登录"}</button>
        <button class="text-button" type="button" data-auth-action="resend" id="resend-code">重新发送</button>
      `;
      (codeForm.elements.namedItem("countryCode") as HTMLInputElement).value = countryCode;
      (codeForm.elements.namedItem("phone") as HTMLInputElement).value = phone;
      Array.from(codeForm.elements).forEach((element) => {
        (element as HTMLInputElement).disabled = busy;
      });
      section.append(codeForm);
    }
    if (auth.status === "error") {
      const error = document.createElement("p");
      error.className = "form-error";
      error.setAttribute("role", "alert");
      error.textContent = auth.message;
      section.append(error);
    }
    authPanel.append(section);
  }

  function updateResend(auth: AuthState): void {
    const button = authPanel.querySelector<HTMLButtonElement>("#resend-code");
    if (!button) return;
    const remaining = auth.status === "codeSent"
      ? Math.max(0, Math.ceil((auth.resendAt - Date.now()) / 1000))
      : 0;
    button.disabled = auth.status === "submitting" || remaining > 0;
    button.textContent = remaining > 0 ? `${remaining} 秒后重新发送` : "重新发送";
  }

  window.setInterval(() => latestState && updateResend(latestState.auth), 1000);

  return {
    render(state: AppState): void {
      latestState = state;
      content.dataset.surface = state.surface;
      coverSurface.hidden = false;
      trackSurface.hidden = false;
      coverSurface.setAttribute("aria-hidden", String(state.surface !== "covers"));
      trackSurface.setAttribute("aria-hidden", String(state.surface !== "tracks"));
      document.querySelectorAll<HTMLButtonElement>("[data-category]").forEach((button) => {
        const active = button.dataset.category === state.category;
        button.classList.toggle("is-active", active);
        button.setAttribute("aria-current", active ? "page" : "false");
      });
      renderCovers(state);
      renderTracks(state);
      renderPlayer(state);
      renderAuth(state.auth);
      updateResend(state.auth);

      drawerLayer.classList.toggle("is-open", state.drawerOpen);
      drawerLayer.setAttribute("aria-hidden", String(!state.drawerOpen));
      for (const element of [topbar, content, player, notice]) element.inert = state.drawerOpen;
      if (state.drawerOpen && !drawerWasOpen) requestAnimationFrame(() => closeSettings.focus());
      if (!state.drawerOpen && drawerWasOpen) requestAnimationFrame(() => openSettings.focus());
      drawerWasOpen = state.drawerOpen;

      notice.hidden = !state.notice;
      noticeText.textContent = state.notice ?? "";
    },
  };
}
