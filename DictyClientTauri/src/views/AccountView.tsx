import React, { useState, useEffect } from "react";
import {
  Star,
  Zap,
  RefreshCw,
  LogOut,
  User,
  CircleDollarSign,
  TrendingDown,
  Mic,
  ExternalLink,
  ShieldCheck,
  Gift,
  X,
  Loader2,
  CheckCircle2,
  Lock,
  ClipboardPaste,
} from "lucide-react";
import { engineApi } from "../services/engineApi";
import { UserAccount } from "../types/engine";
import { openExternalUrl } from "../utils/browser";

const AUTH_STORAGE_KEY = "dicty_auth_user";
const TOKEN_STORAGE_KEY = "dicty_jwt_token";


// Safe client-side Base64/JWT parser (guaranteed to never fail on CORS)
function parseJwtPayload(token: string): any {
  try {
    const parts = token.trim().replace(/['"]/g, "").split(".");
    if (parts.length < 2) return null;
    const base64Url = parts[1];
    const base64 = base64Url.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(
      base64.length + ((4 - (base64.length % 4)) % 4),
      "="
    );
    const jsonPayload = decodeURIComponent(
      atob(padded)
        .split("")
        .map((c) => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2))
        .join("")
    );
    return JSON.parse(jsonPayload);
  } catch (e) {
    try {
      const parts = token.trim().replace(/['"]/g, "").split(".");
      const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      const padded = base64.padEnd(
        base64.length + ((4 - (base64.length % 4)) % 4),
        "="
      );
      return JSON.parse(atob(padded));
    } catch {
      return null;
    }
  }
}

export const AccountView: React.FC = () => {
  const [user, setUser] = useState<UserAccount | null>(() => {
    try {
      const cached = localStorage.getItem(AUTH_STORAGE_KEY);
      if (cached) {
        const parsed = JSON.parse(cached);
        if (parsed && parsed.email) return parsed;
      }
    } catch (e) {
      console.warn("Failed to load cached user:", e);
    }
    return null;
  });

  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showLoginModal, setShowLoginModal] = useState(false);
  const [authMode, setAuthMode] = useState<"login" | "register">("login");
  const [emailInput, setEmailInput] = useState("");
  const [passwordInput, setPasswordInput] = useState("");
  const [authError, setAuthError] = useState<string | null>(null);
  const [authSuccess, setAuthSuccess] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [tokenInput, setTokenInput] = useState("");

  const fetchAuthStatus = async () => {
    setIsRefreshing(true);
    try {
      // 1. Check local engine /auth/status
      const status = await engineApi.getAuthStatus();
      if (status && status.logged_in && status.email) {
        const updated: UserAccount = {
          email: status.email,
          is_pro: status.is_pro,
          compute_balance: status.compute_balance ?? 0,
          subscription_tier: status.subscription_tier ?? "free",
          offline_mode: status.offline_mode ?? false,
          plan_expires_at: user?.plan_expires_at || "2026-08-31T00:00:00Z",
        };
        setUser(updated);
        localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(updated));
        return;
      }

      // 2. Check token against Cloud backend if stored (silently ignore CORS in browser)
      const token = localStorage.getItem(TOKEN_STORAGE_KEY);
      if (token) {
        try {
          const cloudMe = await engineApi.getCloudMe(token);
          if (cloudMe && cloudMe.user && cloudMe.user.email) {
            const u = cloudMe.user;
            const updated: UserAccount = {
              id: u.id,
              email: u.email,
              is_pro: u.isPro ?? u.is_pro ?? false,
              compute_balance: u.computeBalance ?? u.compute_balance ?? 0,
              subscription_tier: u.subscriptionTier ?? u.subscription_tier ?? "free",
              plan_expires_at: u.planExpiresAt ?? u.plan_expires_at,
            };
            setUser(updated);
            localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(updated));
            return;
          }
        } catch (e) {
          // CORS or offline; proceed to resilient fallbacks
        }

        // 3. Fallback: Check cached user credentials
        const cachedStr = localStorage.getItem(AUTH_STORAGE_KEY);
        if (cachedStr) {
          try {
            const cached = JSON.parse(cachedStr);
            if (cached && cached.email) {
              setUser(cached);
              return;
            }
          } catch {}
        }

        // 4. Fallback: Parse stored JWT token locally
        const jwtPayload = parseJwtPayload(token);
        const email =
          jwtPayload?.email ||
          (jwtPayload?.sub && jwtPayload.sub.includes("@") ? jwtPayload.sub : null);
        if (email) {
          const fallbackUser: UserAccount = {
            id: jwtPayload?.userId || jwtPayload?.sub,
            email,
            is_pro: jwtPayload?.isPro ?? jwtPayload?.is_pro ?? false,
            compute_balance: jwtPayload?.computeBalance ?? jwtPayload?.compute_balance ?? 0,
            subscription_tier: jwtPayload?.subscriptionTier ?? jwtPayload?.subscription_tier ?? "free",
            plan_expires_at: jwtPayload?.planExpiresAt ?? (jwtPayload?.exp ? new Date(jwtPayload.exp * 1000).toISOString() : undefined),
          };
          setUser(fallbackUser);
          localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(fallbackUser));
          return;
        }
      }

      // If neither is authenticated and no valid token exists, clear session
      setUser(null);
      localStorage.removeItem(AUTH_STORAGE_KEY);
    } catch (err) {
      console.error("Failed to fetch auth status:", err);
    } finally {
      setIsRefreshing(false);
    }
  };

  useEffect(() => {
    fetchAuthStatus();

    const handleStorage = () => {
      fetchAuthStatus();
    };
    window.addEventListener("storage", handleStorage);

    let unlisten: (() => void) | undefined;
    import("@tauri-apps/api/event").then(({ listen }) => {
      listen<string>("oauth-token", (event) => {
        if (event.payload) {
          console.log("[AccountView] Received OAuth token from deep link:", event.payload.substring(0, 15));
          handleTokenPasteSubmit(event.payload);
        }
      }).then((un) => {
        unlisten = un;
      });
    });

    return () => {
      window.removeEventListener("storage", handleStorage);
      if (unlisten) unlisten();
    };
  }, []);

  const handleLogout = async () => {
    await engineApi.logout();
    localStorage.removeItem(AUTH_STORAGE_KEY);
    localStorage.removeItem(TOKEN_STORAGE_KEY);
    setUser(null);
  };

  const handleLoginSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!emailInput.trim() || !passwordInput.trim() || isSubmitting) return;

    setIsSubmitting(true);
    setAuthError(null);
    setAuthSuccess(null);

    try {
      const res =
        authMode === "login"
          ? await engineApi.login(emailInput.trim(), passwordInput)
          : await engineApi.register(emailInput.trim(), passwordInput);

      if (res && (res.token || res.email)) {
        const loggedUser: UserAccount = {
          email: res.email,
          is_pro: res.is_pro ?? false,
          compute_balance: res.compute_balance ?? 0,
          subscription_tier: res.subscription_tier ?? "free",
          plan_expires_at: res.plan_expires_at,
        };
        if (res.token) {
          localStorage.setItem(TOKEN_STORAGE_KEY, res.token);
        }
        setUser(loggedUser);
        localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(loggedUser));
        setAuthSuccess("Successfully authenticated!");
        setTimeout(() => {
          setShowLoginModal(false);
          setEmailInput("");
          setPasswordInput("");
        }, 800);
      } else {
        setAuthError(res?.detail || "Authentication failed. Check your credentials.");
      }
    } catch (err: any) {
      setAuthError(err.message || "Failed to reach authentication server.");
    } finally {
      setIsSubmitting(false);
    }
  };


  const handleTokenPasteSubmit = async (explicitToken?: string) => {
    const raw = explicitToken || tokenInput;
    const cleaned = raw.trim().replace(/['"]/g, "");
    if (!cleaned) {
      setAuthError("Please enter or paste a valid JWT token.");
      return;
    }

    setIsSubmitting(true);
    setAuthError(null);
    setAuthSuccess(null);

    try {
      // 1. Decode JWT payload locally (100% resilient, independent of CORS)
      const jwtPayload = parseJwtPayload(cleaned);

      // 2. Submit to local backend engine
      let backendRes: any = null;
      try {
        backendRes = await engineApi.submitToken(cleaned);
      } catch (e) {
        console.warn("Backend token submission skipped:", e);
      }

      // 3. Optional Cloud verify (silently catch CORS)
      let cloudUser: any = null;
      try {
        const cloudRes = await engineApi.getCloudMe(cleaned);
        cloudUser = cloudRes?.user;
      } catch (e) {
        // Silently bypass CORS limitation in webview
      }

      const email =
        cloudUser?.email ||
        backendRes?.email ||
        jwtPayload?.email ||
        (jwtPayload?.sub && jwtPayload.sub.includes("@") ? jwtPayload.sub : null);

      if (!email) {
        setAuthError("Could not determine user email from the token.");
        setIsSubmitting(false);
        return;
      }

      const isPro =
        cloudUser?.isPro ??
        backendRes?.is_pro ??
        jwtPayload?.isPro ??
        jwtPayload?.is_pro ??
        false;

      const computeBalance =
        cloudUser?.computeBalance ??
        backendRes?.compute_balance ??
        jwtPayload?.computeBalance ??
        jwtPayload?.compute_balance ??
        0;

      const subscriptionTier =
        cloudUser?.subscriptionTier ??
        backendRes?.subscription_tier ??
        jwtPayload?.subscriptionTier ??
        jwtPayload?.subscription_tier ??
        "free";

      const planExpiresAt =
        cloudUser?.planExpiresAt ??
        backendRes?.plan_expires_at ??
        jwtPayload?.planExpiresAt ??
        (jwtPayload?.exp ? new Date(jwtPayload.exp * 1000).toISOString() : undefined);

      const loggedUser: UserAccount = {
        id: cloudUser?.id || jwtPayload?.userId,
        email,
        is_pro: isPro,
        compute_balance: computeBalance,
        subscription_tier: subscriptionTier,
        plan_expires_at: planExpiresAt,
      };

      localStorage.setItem(TOKEN_STORAGE_KEY, cleaned);
      localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(loggedUser));
      setUser(loggedUser);
      setAuthSuccess("Token applied successfully!");

      setTimeout(() => {
        setShowLoginModal(false);
        setTokenInput("");
        setAuthSuccess(null);
      }, 700);
    } catch (err: any) {
      setAuthError(err.message || "Failed to process token.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handlePasteFromClipboard = async () => {
    try {
      const text = await navigator.clipboard.readText();
      if (text && text.trim().length > 10) {
        setTokenInput(text.trim());
        await handleTokenPasteSubmit(text.trim());
      } else {
        setAuthError("Clipboard is empty or does not contain a valid token.");
      }
    } catch (e) {
      setAuthError("Clipboard read permission denied. Please paste directly into the field.");
    }
  };

  const formatExpirationDate = (dateStr?: string) => {
    if (!dateStr) return "Active Subscription";
    try {
      const date = new Date(dateStr);
      if (isNaN(date.getTime())) return dateStr;

      const day = date.getDate();
      const monthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
      ];
      const month = monthNames[date.getMonth()];
      const year = date.getFullYear();
      const formatted = `${day}. ${month} ${year}`;

      const now = new Date();
      return date < now ? `Expired on ${formatted}` : `Renews on ${formatted}`;
    } catch (e) {
      return dateStr;
    }
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-3xl mx-auto space-y-6 select-none font-sans">
      {/* Title (1:1 with macOS AccountSettingsView: "Dicty Account & Subscription") */}
      <h1 className="text-2xl font-bold text-white tracking-tight">
        Dicty Account & Subscription
      </h1>

      {user ? (
        <div className="space-y-4">
          {/* Card 1: Account & Plan Status */}
          <div className="p-5 rounded-2xl bg-white/[0.04] border border-white/10 shadow-lg space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <span className="text-xs font-normal text-white/50 block mb-1">
                  Signed in as
                </span>
                <span className="text-base font-bold text-white tracking-tight block">
                  {user.email}
                </span>
              </div>

              {user.is_pro ? (
                <div className="flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#87B996]/15 border border-[#87B996]/30 text-[#87B996] text-xs font-bold tracking-wider shadow-sm">
                  <Star className="w-3 h-3 fill-[#87B996] text-[#87B996]" />
                  <span>
                    {user.subscription_tier === "early_supporter"
                      ? "LIFETIME PRO"
                      : "PRO"}
                  </span>
                </div>
              ) : (
                <div className="px-3 py-1 rounded-full bg-white/10 text-white/60 text-xs font-medium uppercase tracking-wider">
                  {user.subscription_tier || "FREE"}
                </div>
              )}
            </div>

            {user.is_pro && (
              <>
                <div className="border-t border-white/[0.08]" />

                <div className="flex items-center justify-between pt-0.5">
                  <div>
                    <span className="text-[10px] font-semibold tracking-wider text-white/40 uppercase block mb-1">
                      RENEWAL / EXPIRATION
                    </span>
                    <span className="text-sm font-semibold text-white/90 block">
                      {user.subscription_tier === "early_supporter"
                        ? "Lifetime Access • Never expires"
                        : formatExpirationDate(user.plan_expires_at)}
                    </span>
                  </div>

                  <button
                    onClick={fetchAuthStatus}
                    disabled={isRefreshing}
                    className="p-1.5 rounded-lg text-white/40 hover:text-white hover:bg-white/10 transition-all disabled:opacity-50"
                    title="Refresh subscription status"
                  >
                    <RefreshCw
                      className={`w-3.5 h-3.5 ${
                        isRefreshing ? "animate-spin text-[#87B996]" : ""
                      }`}
                    />
                  </button>
                </div>
              </>
            )}
          </div>

          {/* Card 2: Compute Balance & How Dicty Cloud Works (1:1 with macOS) */}
          <div className="p-5 rounded-2xl bg-white/[0.04] border border-white/10 shadow-lg space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <span className="text-xs font-medium text-white/50 block mb-1">
                  Compute Balance
                </span>
                <span className="text-2xl font-bold text-[#87B996] tracking-tight">
                  {user.compute_balance.toLocaleString("de-DE")} Credits
                </span>
              </div>
              <Zap className="w-7 h-7 text-[#87B996]/40" />
            </div>

            <div className="border-t border-white/[0.08]" />

            <div className="space-y-2.5">
              <span className="text-xs font-bold text-white block">
                How Dicty Cloud works:
              </span>

              <div className="flex items-center gap-2 text-xs text-white/60">
                <CircleDollarSign className="w-3.5 h-3.5 text-white/50 flex-shrink-0" />
                <span>$1 equals 1,000 compute credits.</span>
              </div>

              <div className="flex items-start gap-2 text-xs text-white/60 leading-relaxed">
                <TrendingDown className="w-3.5 h-3.5 text-white/50 flex-shrink-0 mt-0.5" />
                <span>
                  Credits are dynamically deducted in real-time based on your
                  transcription length or text AI usage.
                </span>
              </div>

              <div className="flex items-center gap-2 text-xs text-white/60">
                <Mic className="w-3.5 h-3.5 text-white/50 flex-shrink-0" />
                <span>
                  Example: 1 minute of dictation uses approximately 12 credits.
                </span>
              </div>
            </div>
          </div>

          {/* If NOT Pro: Upgrade Actions */}
          {!user.is_pro && (
            <div className="p-5 rounded-2xl bg-[#87B996]/5 border border-[#87B996]/20 space-y-3 shadow-md">
              <div className="flex items-center gap-2 text-sm font-semibold text-white">
                <Star className="w-4 h-4 text-[#87B996]" />
                <span>Subscription Status</span>
              </div>
              <p className="text-xs text-white/60 leading-relaxed">
                If you just purchased a Pro subscription and it is not activated,
                click the refresh button below or restart the app.
              </p>
              <div className="flex items-center gap-3 pt-1">
                <button
                  onClick={() => {
                    openExternalUrl(
                      `https://dictyio.lemonsqueezy.com/checkout/buy/5d0f6cfb-8b95-4e42-bc40-01b58a47086b`
                    );
                  }}
                  className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold flex items-center gap-1.5 shadow transition-all"
                >
                  <Star className="w-3.5 h-3.5 fill-white" />
                  <span>Upgrade to Pro</span>
                </button>
                <button
                  onClick={() => {
                    openExternalUrl(
                      `https://dictyio.lemonsqueezy.com/checkout/buy/7cd6458e-280a-400b-9652-c65d3560321f`
                    );
                  }}
                  className="px-3.5 py-1.5 rounded-xl bg-white/10 hover:bg-white/15 text-white text-xs font-medium flex items-center gap-1.5 transition-all"
                >
                  <Gift className="w-3.5 h-3.5 text-[#87B996]" />
                  <span>Early Supporter</span>
                </button>
                <button
                  onClick={fetchAuthStatus}
                  className="p-2 rounded-xl bg-white/[0.05] hover:bg-white/10 text-[#87B996] border border-white/10 transition-all"
                  title="Refresh status"
                >
                  <RefreshCw className={`w-3.5 h-3.5 ${isRefreshing ? "animate-spin" : ""}`} />
                </button>
              </div>
            </div>
          )}

          {/* Offline Mode Indicator */}
          {user.offline_mode && (
            <div className="flex items-center gap-2 text-xs text-white/50 pt-1">
              <ShieldCheck className="w-3.5 h-3.5 text-[#87B996]" />
              <span>
                Offline Mode Active — Pro status cached securely on this device.
              </span>
            </div>
          )}

          {/* Log Out Button (1:1 with macOS screenshot) */}
          <div className="pt-2">
            <button
              onClick={handleLogout}
              className="px-5 py-2 rounded-xl bg-red-950/40 hover:bg-red-900/60 border border-red-500/20 text-red-400 font-medium text-xs transition-all shadow cursor-pointer flex items-center gap-2"
            >
              <LogOut className="w-3.5 h-3.5" />
              <span>Log Out</span>
            </button>
          </div>
        </div>
      ) : (
        /* Unauthenticated State (1:1 with macOS LoginView.swift) */
        <div className="p-6 rounded-2xl bg-white/[0.04] border border-white/10 space-y-4 shadow-lg">
          <div>
            <h2 className="text-base font-bold text-white">
              You are not currently signed in.
            </h2>
            <p className="text-xs text-white/60 mt-1">
              Sign in or register a Dicty account to activate Pro features, custom AI
              routing, and cloud sync.
            </p>
          </div>

          <div className="flex items-center gap-3 pt-2">
            <button
              onClick={() => setShowLoginModal(true)}
              className="px-4 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold flex items-center gap-2 shadow transition-all"
            >
              <User className="w-3.5 h-3.5" />
              <span>Sign In / Register Account</span>
            </button>

          </div>
        </div>
      )}

      {/* Login & Register Modal (1:1 with LoginView.swift) */}
      {showLoginModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md p-4">
          <div className="w-full max-w-sm rounded-2xl bg-[#1a1d22] border border-white/15 p-6 shadow-2xl space-y-4 relative max-h-[90vh] overflow-y-auto">
            <button
              onClick={() => {
                setShowLoginModal(false);
                setAuthError(null);
                setAuthSuccess(null);
              }}
              className="absolute top-4 right-4 p-1 rounded-full text-white/40 hover:text-white hover:bg-white/10 transition-all"
            >
              <X className="w-4 h-4" />
            </button>

            {/* Header */}
            <div className="text-center space-y-1.5 pt-1">
              <div className="w-10 h-10 rounded-full bg-[#5D6658]/30 border border-[#87B996]/30 flex items-center justify-center mx-auto text-[#87B996]">
                <User className="w-5 h-5" />
              </div>
              <h2 className="text-lg font-bold text-white">
                {authMode === "login" ? "Sign In to Dicty" : "Create Dicty Account"}
              </h2>
              <p className="text-[11px] text-white/50">
                Activate Pro features and sync your workspace.
              </p>
            </div>

            {/* Segmented Switcher */}
            <div className="grid grid-cols-2 p-1 rounded-xl bg-black/40 border border-white/10 text-xs font-medium">
              <button
                onClick={() => {
                  setAuthMode("login");
                  setAuthError(null);
                }}
                className={`py-1.5 rounded-lg transition-all ${
                  authMode === "login"
                    ? "bg-[#5D6658] text-white shadow-sm font-semibold"
                    : "text-white/60 hover:text-white"
                }`}
              >
                Sign In
              </button>
              <button
                onClick={() => {
                  setAuthMode("register");
                  setAuthError(null);
                }}
                className={`py-1.5 rounded-lg transition-all ${
                  authMode === "register"
                    ? "bg-[#5D6658] text-white shadow-sm font-semibold"
                    : "text-white/60 hover:text-white"
                }`}
              >
                Create Account
              </button>
            </div>

            {/* Form */}
            <form onSubmit={handleLoginSubmit} className="space-y-3">
              <div>
                <input
                  type="email"
                  placeholder="Email Address"
                  value={emailInput}
                  onChange={(e) => setEmailInput(e.target.value)}
                  className="w-full bg-black/40 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/40 focus:outline-none focus:border-[#5D6658]"
                  required
                />
              </div>

              <div>
                <input
                  type="password"
                  placeholder="Password"
                  value={passwordInput}
                  onChange={(e) => setPasswordInput(e.target.value)}
                  className="w-full bg-black/40 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/40 focus:outline-none focus:border-[#5D6658]"
                  required
                />
              </div>

              {authError && (
                <div className="p-2.5 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-xs text-center leading-relaxed">
                  {authError}
                </div>
              )}

              {authSuccess && (
                <div className="p-2.5 rounded-xl bg-[#87B996]/15 border border-[#87B996]/30 text-[#87B996] text-xs text-center flex items-center justify-center gap-1.5 font-medium">
                  <CheckCircle2 className="w-3.5 h-3.5" />
                  <span>{authSuccess}</span>
                </div>
              )}

              <button
                type="submit"
                disabled={isSubmitting || !emailInput || !passwordInput}
                className="w-full py-2.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] disabled:opacity-40 text-white text-xs font-semibold transition-all shadow flex items-center justify-center gap-2"
              >
                {isSubmitting ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : authMode === "login" ? (
                  "Sign In"
                ) : (
                  "Register Account"
                )}
              </button>
            </form>

            <div className="flex items-center gap-3">
              <div className="flex-1 border-t border-white/10" />
              <span className="text-[10px] text-white/40 uppercase font-bold tracking-widest">
                OR
              </span>
              <div className="flex-1 border-t border-white/10" />
            </div>

            {/* Google / Quick Login Options */}
            <div className="space-y-2">
              <button
                type="button"
                onClick={() => {
                  openExternalUrl(
                    `https://dicty-backend.dicty-backend.workers.dev/auth/google?source=windows`
                  );
                }}
                className="w-full py-2 rounded-xl bg-white/[0.06] hover:bg-white/10 border border-white/10 text-white text-xs font-medium transition-all flex items-center justify-center gap-2"
              >
                <span>Sign in with Google</span>
                <ExternalLink className="w-3 h-3 text-white/50" />
              </button>

            </div>

            {/* Dev Mode: Paste Google Token (1:1 with macOS LoginView.swift:151) */}
            <div className="pt-2 border-t border-white/10 space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Dev Mode: Google OAuth Token
                </span>
                <button
                  type="button"
                  onClick={handlePasteFromClipboard}
                  className="text-[11px] text-[#87B996] hover:underline flex items-center gap-1 font-medium"
                >
                  <ClipboardPaste className="w-3 h-3" />
                  <span>Paste Clipboard</span>
                </button>
              </div>

              <div className="space-y-2">
                <input
                  type="text"
                  placeholder="Paste eyJhbGciOiJIUzI1Ni... token here"
                  value={tokenInput}
                  onChange={(e) => setTokenInput(e.target.value)}
                  className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#87B996]"
                />
                <button
                  type="button"
                  onClick={() => handleTokenPasteSubmit()}
                  disabled={!tokenInput.trim() || isSubmitting}
                  className="w-full py-2 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] disabled:opacity-40 text-white text-xs font-semibold shadow transition-all flex items-center justify-center gap-2"
                >
                  {isSubmitting ? (
                    <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  ) : (
                    "Apply Token"
                  )}
                </button>
              </div>
            </div>

            <div className="text-[10px] text-white/40 text-center flex items-center justify-center gap-1.5 pt-1">
              <Lock className="w-3 h-3 text-white/30" />
              <span>Offline Mode Support: Credentials cached securely</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
