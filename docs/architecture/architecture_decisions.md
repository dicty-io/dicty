# Dicty Architecture Decision Records & System Design

This document serves as the centralized repository for critical architectural decisions, security boundaries, and system design patterns for the Dicty application ecosystem.

---

![alt text](image.png)

## ADR 001: 3-Tier Cloud Authentication & NeonDB Integration

**Status:** Approved & Implemented  
**Date:** July 2026  

### 1. Context & Security Challenge
Dicty is distributed as a native desktop application (macOS SwiftUI client + local Python processing engine). We require a user account system to activate Pro features, manage subscriptions, and authenticate against our hosted cloud database (NeonDB Cloud Postgres).

A fundamental security challenge arises if a client application attempts to communicate directly with a SQL database:
> [!CAUTION]
> **Never embed database connection strings or SQL credentials inside client-side software.** If a connection string (e.g., `postgresql://admin:secret@neondb...`) is embedded in desktop binaries or local Python scripts, any user can inspect memory, decompile code, or intercept network traffic to extract the database credentials. This would allow unauthorized full read/write access or deletion of all user records in the database.

### 2. Architectural Decision: The 3-Tier Model
To ensure complete credential security, offline resilience, and scalable subscription management, Dicty enforces a **3-Tier Architecture**:

```mermaid
flowchart TB
    subgraph Tier1 ["Tier 1: End-User's Local Machine"]
        UI["Dicty Client\n(SwiftUI / macOS App)"]
        LocalEng["Local Python Engine\n(localhost:8075\nWhisper, Audio & LLMs)"]
        Vault[("Native OS Keyring\n(macOS Keychain / Secure Vault)")],
        Cache[("Local Meta Cache\n(~/.gemini/.../auth_meta.json)")]
    end

    subgraph Tier2 ["Tier 2: Remote Cloud API (EC2 / Render / Fly.io)"]
        AuthAPI["FastAPI Cloud Backend\n(/auth/login, /auth/register, /auth/status)"]
        JWTGen["Crypto JWT Issuer & Bcrypt Verifier"]
    end

    subgraph Tier3 ["Tier 3: Cloud Database (NeonDB)"]
        DB[("NeonDB Cloud Postgres\n(Users Table & Subscription Flags)")]
    end

    %% Flow connections
    UI <-->|"1. Local Audio & UI Control\n(REST / WebSockets)"| LocalEng
    UI <-->|"2. HTTPS Auth Request\n(Email & Password)"| AuthAPI
    AuthAPI <-->|"3. Private SQL Query\n(DATABASE_URL Env Var)"| DB
    AuthAPI -->|"4. Return Signed JWT & Profile"| UI
    UI -->|"5. Store JWT Token"| Vault
    UI -->|"6. Store Profile & Pro Flag"| Cache
    UI <-->|"7. Offline Pro Verification"| Cache
```

### 3. Tier Breakdown & Security Boundaries

#### Tier 1: Local Client Ecosystem (End-User Machine)
- **Components:** `DictyClient` (macOS SwiftUI UI) and `dicty_engine.py` (Local background processing engine).
- **Responsibilities:** 
  - Audio capture, system microphone recording, and local speech-to-text (Whisper).
  - Local AI model management and clipboard orchestration.
- **Security & Storage Constraints:**
  - **Zero Database Secrets:** The local codebase has no knowledge of NeonDB passwords, hostnames, or SQL syntax.
  - **Secure Local Credential Storage (`auth.py`):** When authenticated, the client stores the cryptographic **JWT Access Token** securely inside `auth_meta.json` with POSIX `0o600` permissions (owner read/write only, isolated from other user accounts without triggering macOS Keychain ACL password prompts).
  - **Offline Profile Cache (`auth_meta.json`):** User attributes (`email`, `is_pro`) are cached locally so that Pro features can be verified instantly without network latency.

#### Tier 2: Remote Cloud API Server (Hosted EC2 / Container)
- **Components:** A lightweight FastAPI server running remotely in the cloud, exposing endpoints for account management (`/auth/register`, `/auth/login`, `/auth/google/mock`, `/auth/status`, `/auth/logout`).
- **Responsibilities:**
  - Acts as the sole gatekeeper and proxy between end users and NeonDB.
  - Validates login credentials against stored bcrypt password hashes (`passlib`).
  - Issues and verifies cryptographic JWT access tokens signed with a confidential server secret (`SECRET_KEY`).
- **Security & Storage Constraints:**
  - The secret `DATABASE_URL` exists exclusively as a protected environment variable on this server.
  - Configured with CORS and rate limiting to protect public endpoints.

#### Tier 3: Cloud Database (NeonDB Postgres)
- **Components:** Cloud-hosted PostgreSQL database.
- **Responsibilities:**
  - Stores user schemas, primary UUIDs, email addresses, password hashes, and `is_pro` subscription flags.
- **Security Constraints:**
  - Network firewall rules restrict incoming database connections exclusively to Tier 2's cloud IP address or AWS VPC peering.

---

### 4. Step-by-Step Authentication Workflows

#### A. Online Registration & Login
1. User inputs credentials into `LoginView.swift` and initiates authentication.
2. The client transmits an encrypted HTTPS POST payload to Tier 2 (`https://api.dicty.app/auth/login`).
3. Tier 2 connects via `DATABASE_URL` to NeonDB (Tier 3), verifies the password against the bcrypt hash, and generates a JWT token.
4. Tier 2 responds with the payload: `{"token": "eyJ...", "email": "user@domain.com", "is_pro": true}`.
5. Tier 1 receives the response and saves `token` and user profile into `auth_meta.json` with `0o600` permissions.

#### B. Offline Mode & Local Fallback
1. When Dicty launches without internet access (or if the remote API is unreachable), connection attempts to the cloud fail gracefully.
2. The local authentication manager catches network errors and queries `auth_meta.json`.
3. If a valid cached Pro session exists, `offline_mode: true` is returned to SwiftUI, allowing the user uninterrupted access to Pro features without crashes or lockouts.

---

### 5. Production Migration Roadmap
During initial development, the Tier 2 routing logic (`auth_router.py`, `db.py`, `models.py`) was integrated into the local `dicty_engine.py` for rapid testing. To transition to production:
1. **Service Extraction:** Deploy `db.py`, `models.py`, and `auth_router.py` as an independent service on an EC2 instance or serverless container.
2. **Environment Configuration:** Set `DATABASE_URL` in the remote server's environment variables and remove it from any client-side configuration.
3. **Client Endpoint Update:** Update the API base URL in `LoginView.swift` and `DictyClient.swift` from `http://127.0.0.1:8075` to the remote server domain (e.g., `https://api.dicty.app`).

---
106: 
107: ## ADR 002: Dual-Platform Strategy (macOS Native SwiftUI + Windows/Linux Tauri v2)
108: 
109: **Status:** Approved  
110: **Date:** September 2026  
111: 
112: ### 1. Context & Challenge
113: Dicty's original desktop client was developed exclusively for macOS in native Swift/SwiftUI. While the core engine (`dicty_engine.py`) is written in cross-platform Python (FastAPI, SQLite, PortAudio), expanding support to Windows and Linux requires a frontend and OS integration strategy. SwiftUI is Apple-proprietary and cannot be compiled for Windows.
114: 
115: ### 2. Decision: The Decoupled Dual-Client Architecture
116: Rather than discarding the highly polished macOS SwiftUI client (~19,500 lines) or rewriting the entire stack into a heavy Electron wrapper, Dicty adopts a **Decoupled Dual-Client Architecture**:
117: 1. **macOS Flagship Client (`DictyClient`)**: Remains 100% native Swift/SwiftUI and AppKit to ensure the highest standard of macOS design fidelity, zero-latency CoreAudio, and standard Apple accessibility.
118: 2. **Windows & Linux Client (`DictyClientTauri`)**: Built using **Tauri v2** (Rust native core + React/TypeScript UI). It utilizes native system WebViews (WebView2 on Windows, WebKitGTK on Linux), minimizing memory footprint (~40MB RAM vs 300MB+ in Electron) and installer size (<18MB).
119: 3. **Shared Brain (`dicty_engine`)**: Both clients connect to the identical local Python FastAPI engine over `127.0.0.1:8075` via REST, WebSockets, and UDP volume packets.
120: 
121: Detailed technical roadmap, Win32 API mappings, and milestone schedules are specified in [windows_integration_roadmap.md](file:///Users/kazmin/projects/dicty/docs/windows_integration_roadmap.md).

