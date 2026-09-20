// Browspick extension — service worker.
// All forwarding goes through sendToBrowspick(): the current tab navigates to a
// browspick: URL, macOS hands it to the app, and the page stays put. Chrome shows
// an "Open Browspick.app?" prompt once; ticking "always allow" makes it silent.

const MENU_LINK = "browspick-link";
const MENU_PAGE = "browspick-page";

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
  if (url && tab?.id != null) sendToBrowspick(url, tab.id);
});

chrome.action.onClicked.addListener((tab) => {
  if (tab?.url && tab.id != null) sendToBrowspick(tab.url, tab.id);
});

chrome.commands.onCommand.addListener((command, tab) => {
  if (command === "send-page" && tab?.url && tab.id != null) {
    sendToBrowspick(tab.url, tab.id);
  }
});

chrome.runtime.onMessage.addListener((msg, sender) => {
  if (msg?.type === "browspick:send" && typeof msg.url === "string" && sender.tab?.id != null) {
    sendToBrowspick(msg.url, sender.tab.id);
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
    sendToBrowspick(d.url, sourceTabId);
    chrome.tabs.remove(d.tabId).catch(() => {});
  } else {
    sendToBrowspick(d.url, d.tabId);
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

async function sendToBrowspick(url, tabId) {
  if (!/^https?:/i.test(url)) return;
  routed.set(url, Date.now());
  const { alwaysPicker } = await chrome.storage.sync.get({ alwaysPicker: false });
  const target = "browspick:open?url=" + encodeURIComponent(url) + (alwaysPicker ? "&prompt" : "");
  chrome.tabs.update(tabId, { url: target });
}
