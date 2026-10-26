import { invoke } from "@tauri-apps/api/core";

const ENGINE_HTTP_URL = "http://127.0.0.1:8075";
const ENGINE_WS_URL = "ws://127.0.0.1:8075";
const WS_SUBPROTOCOL = "dicty.v1";
const TOKEN_HEADER = "X-Dicty-Token";

let cachedToken: string | null = null;
let tokenPromise: Promise<string> | null = null;

function notifyAuthFailed(message: string) {
  window.dispatchEvent(
    new CustomEvent("dicty:engine-auth-failed", { detail: { error: message } })
  );
}

async function getToken(forceRefresh = false): Promise<string> {
  if (!forceRefresh && cachedToken) {
    return cachedToken;
  }

  if (!tokenPromise) {
    tokenPromise = invoke<string>("engine_token").finally(() => {
      tokenPromise = null;
    });
  }

  const token = await tokenPromise;
  cachedToken = token;
  return token;
}

function engineUrl(path: string): string {
  return `${ENGINE_HTTP_URL}${path.startsWith("/") ? path : `/${path}`}`;
}

function engineWebSocketUrl(path: string): string {
  return `${ENGINE_WS_URL}${path.startsWith("/") ? path : `/${path}`}`;
}

async function isTokenRejection(response: Response): Promise<boolean> {
  if (response.status !== 401) return false;
  try {
    const payload = await response.clone().json();
    return payload?.error === "unauthorized";
  } catch {
    return false;
  }
}

export async function engineFetch(
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  for (let attempt = 0; attempt < 2; attempt++) {
    const token = await getToken(attempt > 0);
    const headers = new Headers(init.headers);
    headers.set(TOKEN_HEADER, token);

    const response = await fetch(engineUrl(path), { ...init, headers });

    if (!(await isTokenRejection(response))) {
      return response;
    }

    if (attempt === 1) {
      const message =
        "Dicty's engine rejected this session. Restart the engine to reconnect.";
      notifyAuthFailed(message);
      throw new Error(message);
    }
  }

  throw new Error(
    "Dicty's engine rejected this session. Restart the engine to reconnect."
  );
}

function waitForWebSocketHandshake(ws: WebSocket): Promise<"open" | number> {
  return new Promise((resolve, reject) => {
    let timer = 0;

    const handleOpen = () => {
      cleanup();
      resolve("open");
    };

    const handleClose = (event: CloseEvent) => {
      cleanup();
      resolve(event.code);
    };

    const cleanup = () => {
      window.clearTimeout(timer);
      ws.removeEventListener("open", handleOpen);
      ws.removeEventListener("close", handleClose);
    };

    timer = window.setTimeout(() => {
      cleanup();
      reject(new Error("Timed out connecting to Dicty's engine."));
    }, 5000);

    ws.addEventListener("open", handleOpen);
    ws.addEventListener("close", handleClose);
  });
}

export async function engineWebSocket(path: string): Promise<WebSocket> {
  for (let attempt = 0; attempt < 2; attempt++) {
    const token = await getToken(attempt > 0);
    const ws = new WebSocket(engineWebSocketUrl(path), [
      WS_SUBPROTOCOL,
      token,
    ]);

    let result: "open" | number;
    try {
      result = await waitForWebSocketHandshake(ws);
    } catch (error) {
      ws.close();
      throw error;
    }

    if (result === "open") {
      return ws;
    }

    if (result === 4401 && attempt === 0) {
      continue;
    }

    if (result === 4401) {
      const message =
        "Dicty's engine rejected this session. Restart the engine to reconnect.";
      notifyAuthFailed(message);
      throw new Error(message);
    }

    throw new Error(
      `Dicty's engine WebSocket closed before opening (code ${result}).`
    );
  }

  throw new Error(
    "Dicty's engine rejected this session. Restart the engine to reconnect."
  );
}
