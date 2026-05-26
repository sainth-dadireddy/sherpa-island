# sherpa-island — Claude session pickup

> Last updated: 2026-05-26 (post Phase 5 γ pivot)
> Companion to `~/CLAUDE/sherpa-platform/CLAUDE.md` (the backend).

## What this is

macOS notch / menubar app. **As of Phase 5 γ, this is the PRIMARY UI** for the autonomous-agent system. The AgentChatPopup window shows live chat between humans + CLI agents + sherpa-platform's SDK personas, all in one Teams-style layout.

## Stack

- **Swift 6 / SwiftUI** for macOS 14+
- **LSUIElement** = true (menubar-only, no Dock icon)
- **SQLite read/write** via libsqlite3 → `~/.claude/memory/agent_chat.db`
- **Polling-based** UI (every 4s) — no SSE/WebSocket
- Bundle: `/Applications/Sherpa Island.app`

## Build + install

```bash
cd /Users/sai/CLAUDE/sherpa-island
./install.sh
```

This script:
1. `swift build -c release`
2. Bundle into `/tmp/Sherpa Island.app`
3. Codesign + clear quarantine
4. Copy to `/Applications/Sherpa Island.app`
5. Launch via direct subprocess

**DO NOT use `open -a "Sherpa Island"`** — silently fails under non-TTY shells for LSUIElement apps. Use:

```bash
pkill -9 -f "SherpaIsland" 2>/dev/null
nohup /Applications/Sherpa\ Island.app/Contents/MacOS/SherpaIsland \
  > /tmp/si_nohup.log 2>&1 &
disown
```

## Key files

| File | What |
|---|---|
| `Sources/SherpaIsland/Sherpa/AgentChatPopup.swift` (~2500 LOC) | Main chat UI: top toolbar + 3-pane (sidebar / chat / right detail) |
| `Sources/SherpaIsland/Sherpa/WorkersBoardView.swift` | Kanban-style AI Workers board + per-agent AgentDetailPane |
| `Sources/SherpaIsland/Sherpa/WorkersData.swift` | Category colors, pricing table (36 models), CLI agent specs, UserDefaults LLM persistence |
| `Sources/SherpaIsland/AppDelegate.swift` | Menubar item + Settings window setup |
| `Sources/SherpaIsland/NotchContentView.swift` | Notch overlay UI (dual-mode toggle) |
| `Resources/erpa-mascot.png` | Rotating mascot in top-left of chat |
| `install.sh` | Release build + bundle + codesign + install |

## Canonical color palette

In `AgentChatPopup.swift` lines 8–15:

```
chatPrimary    #8250D8  (violet)
chatAccent     #B082FF  (light violet)
chatBg         #2A3141  (deep slate)
chatPanel      #343C4D  (raised panel)
chatSidebar    #252B3A  (left rail)
chatTextHi     #F2F5FA
chatTextMid    #B8BFCC
chatTextLow    #8C94A3
```

WorkersData.swift uses 7 category colors (PM=violet / Eng=cyan / Reviewer=yellow / Security=red / Research=blue / Docs=teal / CLI=orange).

## ConvSelection enum (UI state machine)

```swift
enum ConvSelection: Hashable {
    case none
    case dm(String, String)   // canonical sorted pair
    case room(String)
    case ticket(String)
    case agent(String)        // worker detail; sentinel "__board__" = full Workers Board
    case kanban               // ticket board view
}
```

**DO NOT add new cases** without auditing all switch sites (4+ scattered). Last attempt (2026-05-26) broke ViewBuilder switch exhaustiveness — required revert of commits `b583b01` + `bab8b06`. Use sentinel strings within existing cases instead (like `agent("__board__")`).

## How sidebar sections route to main pane

| Section header | Expand → child | Click child → main pane shows |
|---|---|---|
| **Direct Messages** | per-agent rows | DM thread |
| **Rooms** | per-room rows | Room thread |
| **Board** | `Kanban` | `kanbanBoard` view (state: `.kanban`) |
| **AI Workers** | `Agents (17)` | `WorkersBoardView` (state: `.agent("__board__")`) |
| **Tickets** | per-ticket rows | Ticket thread |

Main pane logic: see `private var mainPane` (currently ~L1265).

## Personas shown in Workers Board

Total 17 = 12 SDK personas (sherpa-platform side) + 5 CLI agents.

LLM picker persists per-agent via `UserDefaults.standard` key `worker.<id>.llm`. Posts notification `Notification.Name("workerLLMChanged")` on change. Not yet wired back to sherpa-platform orchestrator (would route the actual call to picked model).

## DB schema notes

Mac DB has additive columns from sherpa-platform pivot:
- `tickets`: cost_usd, cost_ceiling_usd, artifact, closed_at, repo, branch, pr_url, pr_state
- `rooms`: status, archived_at, topic
- `messages`: tokens_in, tokens_out, cost_usd, parent_id
- New tables: `agents`, `cost_ledger`

Migration runs from Python (sherpa-platform side) — Swift just reads what's there. Use `sqlite3_column_type == SQLITE_NULL` guards before reading every column (some Mac DBs predate migration).

## Known issues

1. **#Preview macros disabled across 15 files** — PreviewsMacros plugin missing in current Swift toolchain. Search `_DISABLED_BUILD_FIX_` / `/* DISABLED-PREVIEW`. Re-enable when toolchain has the plugin.

2. **Workers board first-click jitter** — open chat popup, click AI Workers → Agents the first time → momentary tab-like flash before settling. Subsequent clicks fine. Suspected: SwiftUI view-transition animation on `.agent("__board__")` first mount. Started fixing in `aeb30ec` but not fully resolved.

3. **Two pre-existing warnings**:
   - `IOKitSensors.swift:187` — variable never mutated
   - `AgentChatPopup.swift:1616` (approx) — MainActor `tickets` referenced from Sendable closure
   Neither blocks build. Address when refactoring those code paths.

4. **Multi-instance dedup** — DM pairs across multiple sessions can show as 1 row per agent (dedup logic in `loadDMPairs`). If you see duplicate `claude` rows, check that pair canonical sort is working.

## Test build commands

```bash
swift build -c release 2>&1 | rg "error:" | rg -v "PreviewsMacros"
# expected: no output (no errors)

# rebuild + reinstall + relaunch:
./install.sh && pkill -9 -f SherpaIsland; sleep 2
nohup /Applications/Sherpa\ Island.app/Contents/MacOS/SherpaIsland > /tmp/si.log 2>&1 &
disown
```

## Repo

github.com/sainth-dadireddy/sherpa-island — main branch.

Recent tags: none (Phase 5 work landed on main, untagged).

## Companion

The backend lives at `~/CLAUDE/sherpa-platform`. Read its `CLAUDE.md` for FastAPI / LangGraph / Bedrock orchestrator context.
