(() => {
  const panel = document.body.dataset.panel;
  const messages = document.getElementById("messages");
  const status = document.getElementById("status");
  const source = new EventSource(`/events/${encodeURIComponent(panel)}`);

  function safeClass(value) {
    return String(value || "unknown").toLowerCase().replace(/[^a-z0-9_-]/g, "-");
  }

  function render(data) {
    const item = document.createElement("article");
    item.className = `message platform-${safeClass(data.platform)} kind-${safeClass(data.kind)}`;
    item.dataset.id = data.id || "";

    const platform = document.createElement("span");
    platform.className = "message__platform";
    platform.textContent = data.platform || "chat";
    item.append(platform);

    for (const badge of data.badges || []) {
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
