const fields = ["altClick", "alwaysPicker", "autoDomains"];
const $ = (id) => document.getElementById(id);

chrome.storage.sync.get(
  { altClick: true, alwaysPicker: false, autoDomains: [] },
  (opts) => {
    $("altClick").checked = opts.altClick;
    $("alwaysPicker").checked = opts.alwaysPicker;
    $("autoDomains").value = (opts.autoDomains || []).join("\n");
  }
);

$("save").addEventListener("click", () => {
  const domains = $("autoDomains").value
    .split(/\n+/)
    .map((s) => s.trim().toLowerCase().replace(/^\*\./, ""))
    .filter((s) => /^[a-z0-9.-]+\.[a-z]{2,}$/.test(s));
  chrome.storage.sync.set(
    {
      altClick: $("altClick").checked,
      alwaysPicker: $("alwaysPicker").checked,
      autoDomains: [...new Set(domains)]
    },
    () => {
      $("autoDomains").value = domains.join("\n");
      const status = $("status");
      status.classList.add("show");
      setTimeout(() => status.classList.remove("show"), 1500);
    }
  );
});
