// Saves the active tab to the Read Later app.
// The Swift-side SafariWebExtensionHandler receives {action:"save", url, title, html}
// and writes a PendingSave JSON to the App Group container.

async function saveActiveTab() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.url) return { ok: false, error: "no active tab" };

  let html = null;
  try {
    const results = await browser.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => document.documentElement.outerHTML,
    });
    html = results?.[0]?.result ?? null;
  } catch (_) {
    // Not fatal — the native side will refetch if HTML is missing.
  }

  const payload = { action: "save", url: tab.url, title: tab.title, html };
  return browser.runtime.sendNativeMessage("application.id", payload);
}

browser.action.onClicked.addListener(async () => {
  await saveActiveTab();
});

browser.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.action === "save") {
    saveActiveTab().then(sendResponse);
    return true; // keep the channel open for async response
  }
});
