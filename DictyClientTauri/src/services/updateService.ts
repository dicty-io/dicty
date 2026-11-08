import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { engineApi } from "./engineApi";

let cachedHasUpdate: boolean | null = null;
let updateCheckPromise: Promise<boolean> | null = null;

async function checkUpdateStatus(): Promise<boolean> {
  if (cachedHasUpdate !== null) {
    return cachedHasUpdate;
  }
  if (!updateCheckPromise) {
    updateCheckPromise = (async () => {
      try {
        const rawVer = await invoke<string>("get_app_version").catch(() => "1.0.0");
        const cleanVer = (rawVer || "1.0.0").replace(/^[vV]/, "");
        const res = await engineApi.checkForUpdates(cleanVer);
        cachedHasUpdate = Boolean(res?.has_update);
        return cachedHasUpdate;
      } catch (err) {
        console.warn("Failed to check for updates:", err);
        return false;
      } finally {
        updateCheckPromise = null;
      }
    })();
  }
  return updateCheckPromise;
}

export function useUpdateAvailable(): boolean {
  const [hasUpdate, setHasUpdate] = useState<boolean>(cachedHasUpdate ?? false);

  useEffect(() => {
    let isMounted = true;
    checkUpdateStatus().then((result) => {
      if (isMounted) {
        setHasUpdate(result);
      }
    });
    return () => {
      isMounted = false;
    };
  }, []);

  return hasUpdate;
}
