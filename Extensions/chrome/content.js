// Browspick extension — link interception + hover popover.
// Alt+Click or auto-route domains forward links to Browspick; hovering a link
// briefly shows a target list (browsers + profiles, fetched from the app via
// native messaging) plus a Copy button.

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
// undefined = not fetched yet, null = native host unavailable, array = targets
let targetsCache;

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
  const shadow = popHost.shadowRoot;
  popHost.onmouseover = () => clearTimeout(hideTimer);
  popHost.onmouseout = scheduleHide;

  // Targets (browsers + profiles) — fetched once per page load.
  const list = shadow.getElementById("bp-list");
  if (targetsCache === undefined) {
    list.innerHTML = `<div class="row dim">Browspick…</div>`;
    chrome.runtime.sendMessage({ type: "browspick:getTargets" }, (r) => {
      targetsCache = (chrome.runtime.lastError || !Array.isArray(r)) ? null : r;
      renderTargets(list, a);
    });
  } else {
    renderTargets(list, a);
  }

  shadow.getElementById("bp-copy").onclick = () => {
    copyText(a.href);
    const btn = shadow.getElementById("bp-copy");
    btn.textContent = "Copied";
    setTimeout(hidePopover, 500);
  };

  const rect = a.getBoundingClientRect();
  popHost.style.left = Math.max(4, Math.min(rect.left, window.innerWidth - 230)) + "px";
  popHost.style.top = "0px";
  popHost.style.display = "block";
  const h = popHost.offsetHeight;
  const below = rect.bottom + 6 + h <= window.innerHeight;
  popHost.style.top = (below ? rect.bottom + 6 : rect.top - h - 6) + "px";
}

function renderTargets(list, a) {
  const targets = targetsCache;
  if (!targets || !targets.length) {
    // Native host unavailable — fall back to a single generic entry.
    list.innerHTML = `<button class="row">Open with Browspick</button>`;
    list.querySelector("button").onclick = () => {
      chrome.runtime.sendMessage({ type: "browspick:send", url: a.href });
      hidePopover();
    };
    return;
  }
  list.innerHTML = "";
  for (const t of targets) {
    const btn = document.createElement("button");
    btn.className = "row";
    if (t.icon) {
      const img = document.createElement("img");
      img.src = t.icon;
      btn.appendChild(img);
    }
    const label = document.createElement("span");
    label.textContent = t.title;
    btn.appendChild(label);
    btn.onclick = () => {
      chrome.runtime.sendMessage({ type: "browspick:send", url: a.href, targetKey: t.key });
      hidePopover();
    };
    list.appendChild(btn);
  }
}

function copyText(text) {
  if (navigator.clipboard?.writeText) {
    navigator.clipboard.writeText(text).catch(() => copyTextFallback(text));
  } else {
    copyTextFallback(text);
  }
}

function copyTextFallback(text) {
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.style.cssText = "position:fixed;opacity:0";
  document.documentElement.appendChild(ta);
  ta.select();
  try { document.execCommand("copy"); } catch {}
  ta.remove();
}

function hidePopover() {
  clearTimeout(hideTimer);
  if (popHost) popHost.style.display = "none";
}

function ensurePopover() {
  if (popHost) return;
  popHost = document.createElement("div");
  popHost.style.cssText = "position:fixed;z-index:2147483647;display:none";
  const shadow = popHost.attachShadow({ mode: "open" });
  shadow.innerHTML = `
    <style>
      .card {
        all: initial;
        display: flex; flex-direction: column;
        width: 210px; max-height: 280px;
        background: #1e1f24; color: #fff;
        font: 12px/1.4 -apple-system, system-ui, sans-serif;
        border-radius: 10px; overflow: hidden;
        box-shadow: 0 6px 20px rgba(0,0,0,.4);
      }
      #bp-list { overflow-y: auto; padding: 4px; }
      .row {
        all: initial;
        display: flex; align-items: center; gap: 8px;
        width: 100%; box-sizing: border-box;
        padding: 6px 10px; border-radius: 6px;
        cursor: pointer; user-select: none;
        color: #fff; font: inherit;
        white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
      }
      button.row:hover { background: #34363f; }
      .row img { width: 16px; height: 16px; flex: none; border-radius: 50%; }
      .row span { overflow: hidden; text-overflow: ellipsis; }
      .dim { color: #8a8d98; cursor: default; }
      .divider { height: 1px; background: #34363f; margin: 0 4px; }
      #bp-copy {
        all: initial;
        display: block; padding: 7px 10px;
        color: #9ec1ff; font: 11px/1 -apple-system, system-ui, sans-serif;
        cursor: pointer; text-align: center;
      }
      #bp-copy:hover { background: #34363f; }
    </style>
    <div class="card">
      <div id="bp-list"></div>
      <div class="divider"></div>
      <button id="bp-copy">Copy link</button>
    </div>`;
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
