import { useState, useEffect } from "react";
import { engineApi } from "./engineApi";
import { engineFetch } from "./engineClient";

export type ArchitectureTaskStatus = "idle" | "generating" | "completed" | "error";

export interface ArchitectureTaskState {
  status: ArchitectureTaskStatus;
  isGenerating: boolean;
  message: string | null;
  error: string | null;
  pendingId: string | null;
  repo?: string;
  branch?: string;
  destinationDesc?: string;
  startedAt: number | null;
  completedAt: number | null;
}

const STORAGE_KEY = "dicty_architecture_task_state";

class ArchitectureTaskService {
  private state: ArchitectureTaskState = {
    status: "idle",
    isGenerating: false,
    message: null,
    error: null,
    pendingId: null,
    repo: undefined,
    branch: undefined,
    destinationDesc: undefined,
    startedAt: null,
    completedAt: null,
  };

  private listeners: Set<(state: ArchitectureTaskState) => void> = new Set();
  private recoveryPollInterval: any = null;

  constructor() {
    this.restoreState();
  }

  private restoreState() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const parsed = JSON.parse(saved) as ArchitectureTaskState;
        if (parsed.status === "generating" && parsed.startedAt) {
          const ageMs = Date.now() - parsed.startedAt;
          // Stale check after 10 minutes
          if (ageMs > 10 * 60 * 1000) {
            this.state = {
              ...parsed,
              status: "error",
              isGenerating: false,
              error: "Task timed out or was interrupted.",
              message: "Generation timed out. Please try again.",
            };
          } else {
            this.state = parsed;
            this.startRecoveryPolling();
          }
        } else {
          this.state = parsed;
        }
      }
    } catch {
      // Ignore JSON parse errors
    }
  }

  private saveState() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.state));
    } catch {}
  }

  private updateState(partial: Partial<ArchitectureTaskState>) {
    this.state = { ...this.state, ...partial };
    this.saveState();
    this.notify();
  }

  private notify() {
    for (const listener of this.listeners) {
      try {
        listener(this.state);
      } catch (err) {
        console.error("Error in architecture task listener:", err);
      }
    }
  }

  public getState(): ArchitectureTaskState {
    return this.state;
  }

  public subscribe(listener: (state: ArchitectureTaskState) => void): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => {
      this.listeners.delete(listener);
    };
  }

  public clearStatus() {
    this.stopRecoveryPolling();
    this.state = {
      status: "idle",
      isGenerating: false,
      message: null,
      error: null,
      pendingId: null,
      repo: undefined,
      branch: undefined,
      destinationDesc: undefined,
      startedAt: null,
      completedAt: null,
    };
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch {}
    this.notify();
  }

  private startRecoveryPolling() {
    if (this.recoveryPollInterval) return;
    this.recoveryPollInterval = setInterval(async () => {
      try {
        const res = await engineFetch("/pending_updates");
        if (res.ok) {
          const data = await res.json();
          const updates = Array.isArray(data.updates) ? data.updates : [];
          // If we find an update created recently or if list is non-empty
          if (updates.length > 0) {
            this.stopRecoveryPolling();
            this.updateState({
              status: "completed",
              isGenerating: false,
              pendingId: updates[0]?.id || null,
              message: `Architecture proposal drafted! Please review and approve in Pending Updates to publish.`,
              completedAt: Date.now(),
            });
          }
        }
      } catch {}
    }, 4000);
  }

  private stopRecoveryPolling() {
    if (this.recoveryPollInterval) {
      clearInterval(this.recoveryPollInterval);
      this.recoveryPollInterval = null;
    }
  }

  public async startGeneration(
    payload: Record<string, any>,
    context: {
      repo: string;
      branch?: string;
      thoughtCount: number;
      commitCount: number;
      destinationDesc: string;
    }
  ): Promise<void> {
    this.stopRecoveryPolling();
    const initialMessage = `Agent is synthesizing ${context.thoughtCount} voice thought(s) and ${context.commitCount} commit(s)... this may take a few moments.`;

    this.updateState({
      status: "generating",
      isGenerating: true,
      message: initialMessage,
      error: null,
      repo: context.repo,
      branch: context.branch,
      destinationDesc: context.destinationDesc,
      startedAt: Date.now(),
      completedAt: null,
      pendingId: null,
    });

    try {
      const res = await engineApi.reconcileArchitecture(payload);
      if (res && (res.status === "success" || res.ok || res.pending_id)) {
        this.updateState({
          status: "completed",
          isGenerating: false,
          pendingId: res.pending_id || null,
          message: `Architecture proposal drafted ${context.destinationDesc}! Please review and approve in Pending Updates to publish.`,
          error: null,
          completedAt: Date.now(),
        });
      } else {
        const detail = res?.detail || res?.message || res?.error || "Generation completed.";
        const isErr = detail.includes("Error") || res?.status === "failed";
        this.updateState({
          status: isErr ? "error" : "completed",
          isGenerating: false,
          message: isErr ? `Error: ${detail}` : detail,
          error: isErr ? detail : null,
          completedAt: Date.now(),
        });
      }
    } catch (err: any) {
      const errMsg = err?.message || String(err);
      let userMsg = "Architecture generation request submitted! Synthesis running in background.";
      let status: ArchitectureTaskStatus = "completed";

      if (errMsg.includes("504") || errMsg.includes("timeout")) {
        userMsg = "Generation timed out on LLM response. Please retry with a faster model.";
        status = "error";
      } else if (errMsg.includes("Failed to fetch") || errMsg.includes("NetworkError")) {
        userMsg = `Connection error: Could not reach backend engine (${errMsg})`;
        status = "error";
      }

      this.updateState({
        status,
        isGenerating: false,
        message: userMsg,
        error: status === "error" ? errMsg : null,
        completedAt: Date.now(),
      });
    }
  }
}

export const architectureTaskService = new ArchitectureTaskService();

export function useArchitectureTask() {
  const [state, setState] = useState<ArchitectureTaskState>(() => architectureTaskService.getState());

  useEffect(() => {
    return architectureTaskService.subscribe(setState);
  }, []);

  return {
    ...state,
    startGeneration: (
      payload: Record<string, any>,
      context: {
        repo: string;
        branch?: string;
        thoughtCount: number;
        commitCount: number;
        destinationDesc: string;
      }
    ) => architectureTaskService.startGeneration(payload, context),
    clearStatus: () => architectureTaskService.clearStatus(),
  };
}
