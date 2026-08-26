(() => {
  const panel = document.body.dataset.panel;
  const messages = document.getElementById("messages");
  const status = document.getElementById("status");
  const source = new EventSource(`/events/${encodeURIComponent(panel)}`);
  const svgNS = "http://www.w3.org/2000/svg";
  let badgeSequence = 0;

  const platformIcons = {
    kick: "/assets/kick.png",
    youtube: "/assets/youtube.png",
    twitch: "/assets/twitch.png"
  };

  function safeClass(value) {
    return String(value || "unknown").toLowerCase().replace(/[^a-z0-9_-]/g, "-");
  }

  function svgElement(name, attributes = {}) {
    const node = document.createElementNS(svgNS, name);
    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    return node;
  }

  function youtubeModeratorBadge() {
    const svg = svgElement("svg", { viewBox: "0 0 24 24", fill: "currentColor", "aria-label": "Moderador de YouTube" });
    svg.append(svgElement("path", { d: "M3 4.998v9.857a6 6 0 003.365 5.39L12 23l5.635-2.755A6 6 0 0021 14.855V4.998a1 1 0 00-.656-.938L12 1 3.656 4.06A1 1 0 003 4.998Z" }));
    return svg;
  }

  function kickModeratorBadge() {
    const suffix = ++badgeSequence;
    const svg = svgElement("svg", { viewBox: "0 0 20 20", "aria-label": "Moderador de Kick" });
    const defs = svgElement("defs");
    const gradients = [
      ["11.581", "2.623", "-6.156", "22.997", "#ff6a4a", "#c70c00"],
      ["9.858", "10.181", "-1.675", "22.975", "#ffc900", "#ff9500"],
      ["-7.412", "19", "27.412", "1", "#0095ff", "#00c7ff"]
    ];
    const pathData = "M17.875 1C18.496 1 19 1.504 19 2.125v15.75c0 .621-.504 1.125-1.125 1.125H2.125A1.125 1.125 0 0 1 1 17.875V2.125C1 1.504 1.504 1 2.125 1zm-7.751 1.684a.56.56 0 0 0-.796 0L5.704 6.308a.563.563 0 0 0 0 .795l.973.972c.22.22.575.22.795 0l.045-.044 1.325 1.326-5.833 5.834a1.25 1.25 0 0 0 1.768 1.767l5.833-5.833 1.326 1.326-.044.043a.563.563 0 0 0 0 .796l.972.972c.22.22.576.22.795 0l3.624-3.624a.563.563 0 0 0 0-.795l-.972-.972a.56.56 0 0 0-.795 0l-.045.044-1.325-1.326a1.25 1.25 0 0 0-1.768-1.768l-1.326-1.326.044-.044a.56.56 0 0 0 0-.795z";
    gradients.forEach((values, index) => {
      const id = `kick-mod-${suffix}-${index}`;
      const gradient = svgElement("linearGradient", { id, x1: values[0], x2: values[1], y1: values[2], y2: values[3], gradientUnits: "userSpaceOnUse" });
      gradient.append(svgElement("stop", { "stop-color": values[4] }), svgElement("stop", { offset: index === 0 ? "1" : ".99", "stop-color": values[5] }));
      defs.append(gradient);
      svg.append(svgElement("path", { fill: `url(#${id})`, "fill-rule": "evenodd", "clip-rule": "evenodd", d: pathData }));
    });
    svg.prepend(defs);
    return svg;
  }

  function moderatorBadge(platform) {
    let node;
    if (platform === "youtube") node = youtubeModeratorBadge();
    if (platform === "kick") node = kickModeratorBadge();
    if (platform === "twitch") {
      node = document.createElement("img");
      node.src = "https://static-cdn.jtvnw.net/badges/v1/3267646d-33f0-4b17-b3df-f923a41db1d0/1";
      node.srcset = "https://static-cdn.jtvnw.net/badges/v1/3267646d-33f0-4b17-b3df-f923a41db1d0/1 1x, https://static-cdn.jtvnw.net/badges/v1/3267646d-33f0-4b17-b3df-f923a41db1d0/2 2x, https://static-cdn.jtvnw.net/badges/v1/3267646d-33f0-4b17-b3df-f923a41db1d0/3 4x";
      node.alt = "Moderador de Twitch";
    }
    if (node) node.classList.add("message__badge-icon");
    return node;
  }

  function render(data) {
    const item = document.createElement("article");
    item.className = `message platform-${safeClass(data.platform)} kind-${safeClass(data.kind)}`;
    item.dataset.id = data.id || "";

    const platformName = safeClass(data.platform);
    if (platformIcons[platformName]) {
      const icon = document.createElement("img");
      icon.className = "message__platform-icon";
      icon.src = platformIcons[platformName];
      icon.alt = platformName;
      icon.title = platformName;
      item.append(icon);
    } else {
      const platform = document.createElement("span");
      platform.className = "message__platform";
      platform.textContent = data.platform || "chat";
      item.append(platform);
    }

    for (const badge of data.badges || []) {
      if (String(badge).toLowerCase() === "moderator") {
        const icon = moderatorBadge(platformName);
        if (icon) { item.append(icon); continue; }
      }
      const node = document.createElement("span");
      node.className = "message__badge";
      node.textContent = `[${badge}]`;
      item.append(node);
    }

    if (data.author) {
      const author = document.createElement("span");
      author.className = "message__author";
      author.textContent = `${data.author}:`;
      if (/^#[0-9a-f]{6}$/i.test(data.color || "")) author.style.color = data.color;
      item.append(author);
    }

    const text = document.createElement("span");
    text.className = "message__text";
    text.textContent = data.text || "";
    item.append(text);
    messages.append(item);
    while (messages.children.length > 100) messages.firstElementChild.remove();
  }

  source.onopen = () => { status.classList.remove("is-error"); status.textContent = `Live · ${panel}`; };
  source.onerror = () => { status.classList.add("is-error"); status.textContent = `Reconnecting · ${panel}`; };
  source.onmessage = event => { try { render(JSON.parse(event.data)); } catch { status.classList.add("is-error"); status.textContent = "Invalid event"; } };
})();
