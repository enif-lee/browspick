// Browspick extension — link interception + hover popover.
// Alt+Click or auto-route domains forward links to Browspick; hovering a link
// briefly shows an "Open with Browspick" popover under it.

let opts = { altClick: true, autoDomains: [], hoverPopover: true };
chrome.storage.sync.get(opts, (v) => { opts = v; });
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "sync") return;
  for (const [key, change] of Object.entries(changes)) {
    if (key in opts) opts[key] = change.newValue;
  }
  if (changes.hoverPopover?.newValue === false) hidePopover();
});

// MARK: - Click interception

document.addEventListener("click", (e) => {
  if (e.defaultPrevented || e.button !== 0) return;
  const a = e.target instanceof Element ? e.target.closest("a[href]") : null;
  if (!a || !isWebLink(a.href)) return;

  const force = opts.altClick && e.altKey;
  const auto = matchesDomain(a.href, opts.autoDomains || []);
  if (!force && !auto) return;

  e.preventDefault();
  e.stopPropagation();
  hidePopover();
  chrome.runtime.sendMessage({ type: "browspick:send", url: a.href });
}, true);

// MARK: - Hover popover

const SHOW_DELAY = 350;
const HIDE_DELAY = 250;

let popHost = null;
let hoverTimer = null;
let hideTimer = null;
let pendingLink = null;
let currentLink = null;

document.addEventListener("mouseover", (e) => {
  if (!opts.hoverPopover) return;
  if (popHost && e.target === popHost) return; // inside popover
  const a = e.target instanceof Element ? e.target.closest("a[href]") : null;
  if (a === pendingLink) return;
  cancelShow();
  if (a && isWebLink(a.href) && !matchesDomain(a.href, opts.autoDomains || [])) {
    pendingLink = a;
    hoverTimer = setTimeout(() => showPopover(a), SHOW_DELAY);
  }
}, true);

document.addEventListener("mouseout", (e) => {
  if (popHost && e.relatedTarget === popHost) return; // moving onto popover
  const from = e.target instanceof Element ? e.target.closest("a[href]") : null;
  const to = e.relatedTarget instanceof Element ? e.relatedTarget.closest("a[href]") : null;
  if (from === to) return; // moving within the same link
  cancelShow();
  scheduleHide();
}, true);

document.addEventListener("scroll", () => { cancelShow(); hidePopover(); }, true);
document.addEventListener("keydown", (e) => { if (e.key === "Escape") hidePopover(); }, true);

function cancelShow() {
  clearTimeout(hoverTimer);
  pendingLink = null;
}

function scheduleHide() {
  clearTimeout(hideTimer);
  hideTimer = setTimeout(hidePopover, HIDE_DELAY);
}

function showPopover(a) {
  pendingLink = null;
  ensurePopover();
  currentLink = a;
  const shadow = popHost.shadowRoot;
  shadow.getElementById("bp-open").onclick = () => {
    chrome.runtime.sendMessage({ type: "browspick:send", url: a.href });
    hidePopover();
  };
  popHost.onmouseover = () => clearTimeout(hideTimer);
  popHost.onmouseout = scheduleHide;

  const rect = a.getBoundingClientRect();
  popHost.style.left = Math.max(4, Math.min(rect.left, window.innerWidth - 190)) + "px";
  popHost.style.top = "0px";
  popHost.style.display = "block";
  const h = popHost.offsetHeight;
  const below = rect.bottom + 6 + h <= window.innerHeight;
  popHost.style.top = (below ? rect.bottom + 6 : rect.top - h - 6) + "px";
}

function hidePopover() {
  clearTimeout(hideTimer);
  currentLink = null;
  if (popHost) popHost.style.display = "none";
}

function ensurePopover() {
  if (popHost) return;
  popHost = document.createElement("div");
  popHost.style.cssText =
    "position:fixed;z-index:2147483647;display:none";
  const shadow = popHost.attachShadow({ mode: "open" });
  shadow.innerHTML = `
    <style>
      button {
        all: initial;
        display: flex; align-items: center; gap: 6px;
        padding: 6px 12px;
        background: #1e1f24; color: #fff;
        font: 12px/1 -apple-system, system-ui, sans-serif;
        border-radius: 8px;
        box-shadow: 0 4px 16px rgba(0,0,0,.35);
        cursor: pointer; user-select: none;
      }
      button:hover { background: #2e3038; }
      img { width: 14px; height: 14px; }
    </style>
    <button id="bp-open">
      <img src="${chrome.runtime.getURL("icons/icon32.png")}" alt="">
      Open with Browspick
    </button>`;
  document.documentElement.appendChild(popHost);
}

// MARK: - Helpers

function isWebLink(href) {
  return /^https?:/i.test(href);
}

function matchesDomain(href, domains) {
  try {
    const host = new URL(href).hostname.toLowerCase();
    return domains.some((d) => host === d || host.endsWith("." + d));
  } catch {
    return false;
  }
}
