import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";

try {
  const win = getCurrentWebviewWindow();
  if (win && (win.label === "overlay" || win.label === "mode_switcher")) {
    document.documentElement.classList.add("is-overlay");
    document.documentElement.style.background = "transparent";
    if (document.body) {
      document.body.style.background = "transparent";
    }
  }
} catch {
  // Browser preview mode
}

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
