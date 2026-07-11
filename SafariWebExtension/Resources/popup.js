const btn = document.getElementById("save");
const status = document.getElementById("status");

btn.addEventListener("click", async () => {
  btn.disabled = true;
  status.textContent = "Saving…";
  try {
    const res = await browser.runtime.sendMessage({ action: "save" });
    if (res && res.ok) {
      status.textContent = "Saved.";
      setTimeout(() => window.close(), 600);
    } else {
      status.textContent = "Couldn't save.";
      btn.disabled = false;
    }
  } catch (e) {
    status.textContent = String(e);
    btn.disabled = false;
  }
});
