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

async function sendToBrowspick(url, tabId) {
  if (!/^https?:/i.test(url)) return;
  const { alwaysPicker } = await chrome.storage.sync.get({ alwaysPicker: false });
  const target = "browspick:open?url=" + encodeURIComponent(url) + (alwaysPicker ? "&prompt" : "");
  chrome.tabs.update(tabId, { url: target });
}
