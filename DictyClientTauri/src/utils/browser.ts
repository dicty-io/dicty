import { invoke } from "@tauri-apps/api/core";

/**
 * Reliably opens an external URL in the operating system's default web browser
 * bypassing WebView2 popup restrictions on Windows.
 */
export async function openExternalUrl(url: string): Promise<void> {
  if (!url) return;
  try {
    await invoke("open_external_url", { url });
  } catch (err) {
    try {
      window.open(url, "_blank");
    } catch {}
  }
}
