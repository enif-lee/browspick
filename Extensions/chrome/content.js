// Browspick extension — link interception.
// Alt+Click on a link (or any click matching an auto-route domain) is forwarded
// to Browspick instead of navigating. Everything else is left alone.

let opts = { altClick: true, autoDomains: [] };
chrome.storage.sync.get(opts, (v) => { opts = v; });
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "sync") return;
  for (const [key, change] of Object.entries(changes)) {
    if (key in opts) opts[key] = change.newValue;
  }
});

document.addEventListener("click", (e) => {
  if (e.defaultPrevented || e.button !== 0) return;
  const a = e.target instanceof Element ? e.target.closest("a[href]") : null;
  if (!a || !/^https?:/i.test(a.href)) return;

  const force = opts.altClick && e.altKey;
  const auto = matchesDomain(a.href, opts.autoDomains || []);
  if (!force && !auto) return;

  e.preventDefault();
  e.stopPropagation();
  chrome.runtime.sendMessage({ type: "browspick:send", url: a.href });
}, true);

function matchesDomain(href, domains) {
  try {
    const host = new URL(href).hostname.toLowerCase();
    return domains.some((d) => host === d || host.endsWith("." + d));
  } catch {
    return false;
  }
}
