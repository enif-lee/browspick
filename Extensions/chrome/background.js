// Browspick extension — service worker.
// Native messaging (com.ed.browspick) is the primary channel: silent and
// bidirectional. If the host isn't installed (older app), we fall back to
// navigating the tab to a browspick: URL, which shows Chrome's external
// protocol prompt once per "always allow".

const MENU_LINK = "browspick-link";
const MENU_PAGE = "browspick-page";
const NATIVE_HOST = "com.ed.browspick";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: MENU_LINK,
    title: "Open link with Browspick",
    contexts: ["link"]
  });
  chrome.contextMenus.create({
    id: MENU_PAGE,
    title: "Open page with Browspick",
    contexts: ["page"]
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const url = info.menuItemId === MENU_LINK ? info.linkUrl : info.pageUrl;
  if (url && tab?.id != null) route(url, tab.id);
});

chrome.action.onClicked.addListener((tab) => {
  if (tab?.url && tab.id != null) route(tab.url, tab.id);
});

chrome.commands.onCommand.addListener((command, tab) => {
  if (command === "send-page" && tab?.url && tab.id != null) {
    route(tab.url, tab.id);
  }
});

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type === "browspick:send" && typeof msg.url === "string" && sender.tab?.id != null) {
    route(msg.url, sender.tab.id, msg.targetKey);
    return;
  }
  if (msg?.type === "browspick:getTargets") {
    nativeSend({ type: "getTargets" })
      .then((r) => sendResponse(Array.isArray(r?.targets) ? r.targets : null))
      .catch(() => sendResponse(null));
    return true; // async sendResponse
  }
});

// MARK: - Auto-route: catch navigations the in-page click handler can't see —
// new-tab link opens (target=_blank, ⌘+click), address bar, bookmarks.

// Loop breaker: if Browspick routes a URL back into this same profile, the
// re-navigation would be intercepted again forever. Let a URL we just
// forwarded pass through once.
const routed = new Map(); // url → timestamp
const ROUTED_TTL = 3000;

// Links opening in a new tab: remember the source tab so we can close the
// blank target tab and forward through the source instead.
const linkOpenedTabs = new Map(); // tabId → sourceTabId

chrome.webNavigation.onCreatedNavigationTarget.addListener((d) => {
  linkOpenedTabs.set(d.tabId, d.sourceTabId);
});

chrome.tabs.onRemoved.addListener((tabId) => {
  linkOpenedTabs.delete(tabId);
});

chrome.webNavigation.onBeforeNavigate.addListener(async (d) => {
  if (d.frameId !== 0 || !/^https?:/i.test(d.url)) return;
  const { autoDomains = [] } = await chrome.storage.sync.get({ autoDomains: [] });
  if (!matchesDomains(d.url, autoDomains)) return;
  if (wasRouted(d.url)) return;

  const sourceTabId = linkOpenedTabs.get(d.tabId);
  linkOpenedTabs.delete(d.tabId);
  if (sourceTabId != null) {
    route(d.url, sourceTabId);
    chrome.tabs.remove(d.tabId).catch(() => {});
  } else {
    route(d.url, d.tabId);
  }
});

function matchesDomains(url, domains) {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return domains.some((d) => host === d || host.endsWith("." + d));
  } catch {
    return false;
  }
}

function wasRouted(url) {
  const ts = routed.get(url);
  routed.delete(url);
  return ts != null && Date.now() - ts < ROUTED_TTL;
}

// MARK: - Native channel + scheme fallback

function nativeSend(message) {
  return new Promise((resolve, reject) => {
    try {
      chrome.runtime.sendNativeMessage(NATIVE_HOST, message, (resp) => {
        if (chrome.runtime.lastError) reject(new Error(chrome.runtime.lastError.message));
        else resolve(resp);
      });
    } catch (e) {
      reject(e);
    }
  });
}

async function route(url, tabId, targetKey) {
  if (!/^https?:/i.test(url)) return;
  routed.set(url, Date.now());
  try {
    const r = await nativeSend({ type: "send", url, targetKey });
    if (r?.ok) return;
  } catch { /* host unavailable — fall through to the scheme */ }
  sendViaScheme(url, tabId, targetKey);
}

async function sendViaScheme(url, tabId, targetKey) {
  let target = "browspick:open?url=" + encodeURIComponent(url);
  if (targetKey) {
    target += "&target=" + encodeURIComponent(targetKey);
  } else {
    const { alwaysPicker } = await chrome.storage.sync.get({ alwaysPicker: false });
    if (alwaysPicker) target += "&prompt";
  }
  chrome.tabs.update(tabId, { url: target });
}
