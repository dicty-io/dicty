import { invoke } from "@tauri-apps/api/core";

/**
 * Copies transcribed text into the system clipboard and optionally simulates Ctrl+V paste
 * into the previously active application. Includes performance timing benchmarks.
 */
export async function copyToClipboardAndPaste(
  text: string,
  forceAutoPaste?: boolean,
  backendTimings?: any
) {
  if (!text || !text.trim()) return;

  const tStart = performance.now();
  const shouldAutoPaste =
    forceAutoPaste !== undefined
      ? forceAutoPaste
      : typeof window === "undefined" || localStorage.getItem("dicty_auto_paste") !== "false";

  let clipMs = 0;
  // 1. Copy via browser / webview clipboard API
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    const tClip0 = performance.now();
    try {
      await navigator.clipboard.writeText(text);
      clipMs = performance.now() - tClip0;
      console.log(`[*] Text copied to clipboard in ${clipMs.toFixed(1)} ms.`);
    } catch (err) {
      console.warn("navigator.clipboard.writeText failed:", err);
    }
  }

  // 2. Invoke OS-level native clipboard & synthetic keystroke injection
  let nativePasteMs = 0;
  try {
    const tPaste0 = performance.now();
    if (shouldAutoPaste) {
      await invoke("copy_and_paste", { text });
      nativePasteMs = performance.now() - tPaste0;
    } else {
      await invoke("copy_to_clipboard", { text });
      nativePasteMs = performance.now() - tPaste0;
    }
  } catch (err) {
    // If running in browser dev mode without Tauri backend
    console.warn("Native Tauri clipboard command skipped:", err);
  }

  const totalClientMs = performance.now() - tStart;
  console.log(
    `%c⏱️ [CLIENT TIMERS] Clipboard: ${clipMs.toFixed(1)}ms | Win32 Injection: ${nativePasteMs.toFixed(1)}ms | Client Total: ${totalClientMs.toFixed(1)}ms`,
    "color: #87B996; font-weight: bold;"
  );

  if (backendTimings) {
    console.table({
      "Mic Stop": `${backendTimings.mic_stop_ms ?? 0} ms`,
      "Audio Transcription": `${backendTimings.whisper_ms ?? 0} ms (${backendTimings.provider ?? "STT"})`,
      "Post-Processing": `${backendTimings.post_ms ?? 0} ms`,
      "LLM Reformatting": `${backendTimings.llm_ms ?? 0} ms`,
      "Backend Total": `${backendTimings.total_ms ?? 0} ms`,
      "Client Clipboard & Paste": `${totalClientMs.toFixed(1)} ms`,
    });
  }
}
