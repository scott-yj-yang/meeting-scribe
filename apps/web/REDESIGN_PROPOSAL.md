# MeetingScribe Webapp — Redesign Proposal

**Date:** 2026-04-09  
**Status:** Proposed  
**Branch:** `feat/hallucination-detection-timestamps-tauri`  
**Author:** Claude Code (architecture decision record)  
**Based on:** `apps/web/WEBAPP_AUDIT.md` — 27 issues, 3 critical / 8 high / 9 medium / 7 low

---

## Decision

The audit found 3 critical bugs (including a stale-closure bug that breaks chat history on every message and hard reloads that are incompatible with Tauri's WebView), along with a pattern of shared state being independently duplicated across sibling components. Patching these individually is feasible in the short term, but the root causes are structural.

This document proposes a targeted restructure — not a ground-up rewrite — that fixes every critical and high issue while laying a foundation that avoids the same class of bugs recurring.

---

## 1. Component Architecture

### Current State

Every component in `src/app/` is a Client Component (`"use client"`). Data fetching, subscriptions, and presentation are co-located. This means:

- All server data loads block the client bundle.
- Shared state (e.g., `claudeReady`, summarize-job status) is fetched independently by sibling components, causing race conditions.
- Polling and streaming teardown is inconsistent; several components leak on unmount.

### Proposed Structure

Split every view into a Server Component shell and narrow Client Component islands.

```
app/
  page.tsx                      # Server Component — fetches meeting list, passes props
  meetings/
    [id]/
      page.tsx                  # Server Component — fetches meeting, summary, transcript
      chat/
        page.tsx                # Server Component shell; streams nothing, sets up context
components/
  server/
    MeetingList.tsx             # RSC — renders paginated meeting rows
    MeetingDetail.tsx           # RSC — renders summary text, transcript segments
    TranscriptSegments.tsx      # RSC — renders segment list; accepts highlightTime as prop
  client/
    DashboardClient.tsx         # selection, delete, filter interactions
    SearchBar.tsx               # search input + type pills
    SummaryView.tsx             # polling skeleton, resummarize form
    TranscriptFilter.tsx        # speaker/text filter input
    ChatPane.tsx                # streaming chat, AbortController, send form
    AudioUploader.tsx           # file picker — browser or native Tauri dialog
    DesktopIndicator.tsx        # visible only when isTauri()
  hooks/
    usePolling.ts               # shared polling loop with mountd-guard + cleanup
    useSSEStream.ts             # shared SSE reader with AbortController
    useServerHealth.ts          # single global health check (context-backed)
    usePersistentSettings.ts    # localStorage persistence for model/effort
```

**Rules:**
- Server Components may not import `"use client"` modules directly; pass data as props.
- Client Components are leaf nodes unless they render other Client Components via composition.
- Any component that calls `setTimeout`, `setInterval`, `fetch` with streaming, or `addEventListener` must be a Client Component with a cleanup `useEffect`.

---

## 2. Tauri-Native Patterns

The bridge module at `src/lib/tauri.ts` is already correct. The gap is that components do not yet use it consistently.

### 2.1 File Picker

Replace the current `<input type="file">` with a runtime-switchable uploader:

```tsx
// components/client/AudioUploader.tsx
import { isTauri, pickAudioFile } from "@/lib/tauri";

export function AudioUploader({ onFile }: { onFile: (f: File | TauriFile) => void }) {
  if (isTauri()) {
    return (
      <button onClick={async () => {
        const result = await pickAudioFile();
        if (result) onFile(result);
      }}>
        Choose Audio File
      </button>
    );
  }
  return <input type="file" accept="audio/*" onChange={e => {
    if (e.target.files?.[0]) onFile(e.target.files[0]);
  }} />;
}
```

### 2.2 Background Notifications

`showNotification()` in `tauri.ts` already wraps the browser Notification API. Call sites in `SummaryView` and `AutoSummarizeTrigger` should invoke it when the job completes instead of (or in addition to) triggering a reload.

### 2.3 Desktop Indicator

Add a non-intrusive badge when running under Tauri:

```tsx
// components/client/DesktopIndicator.tsx
"use client";
import { isTauri } from "@/lib/tauri";

export function DesktopIndicator() {
  if (!isTauri()) return null;
  return (
    <span className="text-xs text-gray-400 border border-gray-200 rounded px-1.5 py-0.5">
      Desktop
    </span>
  );
}
```

Render it in the top navigation bar next to the app name.

### 2.4 Navigation After Data Mutation (Critical Fix)

Every `window.location.reload()` call must be replaced with `router.refresh()`. This is the single highest-impact change in the codebase:

| File | Current | Replacement |
|------|---------|-------------|
| `SummaryView.tsx` (poll completion) | `window.location.reload()` | `router.refresh()` |
| `SummaryView.tsx` (resume poll) | `window.location.reload()` | `router.refresh()` |
| `AutoSummarizeTrigger.tsx` (poll completion) | `window.location.reload()` | `router.refresh()` |

After `router.refresh()`, reset local loading state via a transition:

```tsx
const router = useRouter();

// After job completes:
router.refresh();
setLoading(false);
setSummaryState("complete");
```

---

## 3. State Management

### 3.1 URL Search Params for Filter / Search

`SearchBar` and `DashboardClient` both store filter state in React `useState`. When the component remounts (e.g., after a `router.refresh()`), state is lost and props are not re-synced.

All filter and search state should live in the URL:

```
/?page=2&q=standup&type=1%3A1
```

Components read from `useSearchParams()` and write via `router.replace()`. This makes filters bookmarkable, survivable across refreshes, and shareable.

Affected changes:
- `SearchBar`: remove local `query` state; read directly from `useSearchParams()`.
- `DashboardClient`: derive `page`, `type`, `q` from `useSearchParams()`, not props.
- Add a `useEffect(() => setSelected(new Set()), [searchParams])` to clear selection when filters change.

### 3.2 React Context for Cross-Cutting Server State

Two pieces of state are fetched independently by multiple siblings:

**Claude/server health** — currently fetched in both `SummaryView` and `ClaudeStatus`:

```tsx
// lib/context/ServerHealthContext.tsx
const ServerHealthContext = createContext<{ claudeReady: boolean | null }>({ claudeReady: null });

export function ServerHealthProvider({ children }: { children: ReactNode }) {
  const [claudeReady, setClaudeReady] = useState<boolean | null>(null);
  useEffect(() => {
    fetch("/api/health/claude").then(r => r.json()).then(d => setClaudeReady(d.ok));
  }, []);
  return <ServerHealthContext.Provider value={{ claudeReady }}>{children}</ServerHealthContext.Provider>;
}

export const useServerHealth = () => useContext(ServerHealthContext);
```

Render `ServerHealthProvider` once in the root layout. Every component that needs `claudeReady` calls `useServerHealth()` — no extra network requests.

**Summarize job status** — currently managed in parallel by `SummaryView` and `AutoSummarizeTrigger`. Merge them:

- Delete `AutoSummarizeTrigger.tsx` as a standalone component.
- Move auto-trigger logic into `SummaryView`'s mount effect: if `summaryContent` is null and `autoSummarize` is enabled, call `handleSummarize()` immediately.
- This removes the race condition between two independent mount effects entirely.

### 3.3 Polling Cleanup

Extract a shared `usePolling` hook so the mounted-guard pattern is written once:

```ts
// hooks/usePolling.ts
export function usePolling(
  fn: () => Promise<"continue" | "stop">,
  intervalMs: number,
  active: boolean
) {
  useEffect(() => {
    if (!active) return;
    let mounted = true;
    const tick = async () => {
      const result = await fn();
      if (mounted && result === "continue") {
        setTimeout(tick, intervalMs);
      }
    };
    tick();
    return () => { mounted = false; };
  }, [fn, intervalMs, active]);
}
```

`SummaryView` and any future polling component uses this hook. The mounted flag is guaranteed to be set to `false` in cleanup — no setState after unmount.

---

## 4. Streaming Improvements for Chat

### 4.1 AbortController for Cancellation

```tsx
// hooks/useSSEStream.ts
export function useSSEStream() {
  const controllerRef = useRef<AbortController | null>(null);

  const stream = useCallback(async (url: string, body: object, onChunk: (s: string) => void) => {
    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;

    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    const reader = res.body!.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) {
        if (line.startsWith("data: ")) onChunk(line.slice(6));
      }
    }
  }, []);

  useEffect(() => () => { controllerRef.current?.abort(); }, []);

  return { stream };
}
```

Benefits: cancels on unmount, cancels on re-send, buffers partial chunks from split `\n` boundaries.

### 4.2 Fix the History Closure Capture Bug (Critical)

The current code passes `messages` (old state) to the API. The fix is to build the history snapshot before the first `setState`:

```tsx
// Inside sendMessage — build history BEFORE any setState call
const historySnapshot = [...messages, userMessage];

setMessages(historySnapshot);
setMessages(prev => [...prev, { role: "assistant", content: "" }]);

const res = await fetch(`/api/meetings/${id}/chat`, {
  body: JSON.stringify({
    message: text,
    history: historySnapshot,   // <-- snapshot, not the stale closure
  }),
});
```

### 4.3 Stable `sendMessage` Reference

Remove `messages` from `useCallback`'s dependency array. Read the latest messages via a ref when needed:

```tsx
const messagesRef = useRef(messages);
useEffect(() => { messagesRef.current = messages; }, [messages]);

const sendMessage = useCallback(async (overrideText?: string) => {
  const current = messagesRef.current;
  // build historySnapshot from `current`...
}, [id, input, streaming]);   // messages removed from deps
```

This prevents `sendMessage` from being recreated on every streaming chunk.

### 4.4 Reconnection Logic

Wrap the stream call in a retry loop with exponential backoff, capped at 3 attempts, only for network errors (not 4xx):

```tsx
let attempt = 0;
while (attempt < 3) {
  try {
    await stream(url, body, onChunk);
    break;
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") break; // user cancelled
    attempt++;
    if (attempt >= 3) throw e;
    await new Promise(r => setTimeout(r, 500 * 2 ** attempt));
  }
}
```

### 4.5 Suggestions Persistence

Show the suggestions panel until the first successful non-empty assistant response, not until the first user message:

```tsx
const hasResponse = messages.some(m => m.role === "assistant" && m.content.length > 0);
{!hasResponse && <SuggestionPills onSelect={sendMessage} />}
```

### 4.6 Migrate Chat to Anthropic SDK (Low, Post-Redesign)

The current implementation calls `claude -p` as a shell subprocess and concatenates the full conversation into a single string. This bypasses proper multi-turn attention masking. The API route at `/api/meetings/[id]/chat` should be migrated to the Anthropic `@anthropic-ai/sdk` `messages.stream()` method, which accepts a proper `messages` array and supports native streaming with backpressure. This can wait for a full redesign pass; it does not affect P0/P1 fixes.

---

## 5. Priority Ordering

### P0 — Critical (fix before any new feature work)

These three bugs actively break core product flows today.

| # | Issue | File | Fix |
|---|-------|------|-----|
| P0-1 | `window.location.reload()` breaks Tauri WebView | `SummaryView.tsx`, `AutoSummarizeTrigger.tsx` | Replace all 3 call sites with `router.refresh()` |
| P0-2 | Chat history always one message stale (closure capture) | `chat/page.tsx` | Build `historySnapshot` before `setState`; pass snapshot to API |
| P0-3 | Timer `startTimeRef` reset overwrites server-elapsed on resume | `SummaryView.tsx` | Guard timer-reset effect with `prev → current` comparison or null-check |

**Estimated effort:** 2–4 hours. These are surgical one-file changes with no architectural dependencies.

---

### P1 — High (fix in the current sprint)

These issues cause features to regularly produce wrong output or silently fail.

| # | Issue | File | Fix |
|---|-------|------|-----|
| P1-1 | Poll continues after unmount (setState leak) | `SummaryView.tsx` | Introduce `usePolling` hook with mounted-guard |
| P1-2 | `handleResummarize` does not await `handleSummarize` | `SummaryView.tsx` | Make `handleResummarize` async; await the inner call |
| P1-3 | Highlight scroll fails when filter is active | `TranscriptView.tsx` | Clear filter on timestamp navigation; search within `filtered` |
| P1-4 | Race condition: `AutoSummarizeTrigger` vs `SummaryView` on mount | Both | Merge auto-trigger into `SummaryView`; delete `AutoSummarizeTrigger` |
| P1-5 | `AutoSummarizeTrigger` uses `window.location.reload()` | `AutoSummarizeTrigger.tsx` | Covered by P0-1 fix (delete component; merge logic) |
| P1-6 | Stream reader not cancelled on unmount | `chat/page.tsx` | Add `AbortController` via `useSSEStream` hook |
| P1-7 | `SearchBar` query state not synced on `initialQuery` prop change | `SearchBar.tsx` | Add `useEffect([initialQuery])` sync; or migrate to `useSearchParams()` |
| P1-8 | No debounce on search input; inconsistent vs type pills | `SearchBar.tsx` | Add 300 ms debounced `useEffect` calling `navigate` |
| P1-9 | Suggestion pills lost after first error response | `chat/page.tsx` | Show suggestions until first non-empty assistant response |

**Estimated effort:** 1–2 days.

---

### P2 — Medium (can wait for a planned redesign sprint)

These are annoying but not regularly breaking. They are the natural output of the component restructure described in sections 1–3.

| # | Issue | Notes |
|---|-------|-------|
| P2-1 | `allSelected` miscounts after refresh | Resolved by clearing `selected` on `searchParams` change |
| P2-2 | Batch delete swallows per-item HTTP errors | Add `res.ok` check; show error count |
| P2-3 | `claudeReady` refetched on every tab switch | Resolved by `ServerHealthContext` |
| P2-4 | `highlightTime` re-click does not re-scroll | Replace `highlightTime` with `{ time, seq }` object |
| P2-5 | Filter not cleared on timestamp navigation | Resolved alongside P1-3 |
| P2-6 | Active pill flashes inactive during navigation | Add local `activeType` state |
| P2-7 | `sendMessage` recreated every streaming chunk | Remove `messages` from `useCallback` deps |
| P2-8 | Model/effort settings not persisted | `usePersistentSettings` hook + `localStorage` |
| P2-9 | No `aria-live` on dynamic content | Add `aria-live="polite"` to chat area and status messages |

---

### P3 — Low / Post-Redesign

| # | Issue |
|---|-------|
| Pagination uses `<a>` not `<Link>` | Replace with Next.js `<Link>` |
| `groupMeetingsByDay` assumes sorted input | Sort before grouping |
| Default tab ignores URL state | Accept `defaultTab` prop from Server Component `searchParams` |
| `handleCopy` unhandled rejection | Wrap in `try/catch` |
| `containerRef` unused | Remove or wire to `scrollIntoView` |
| `localStorage` not SSR-guarded | Add `typeof window !== "undefined"` guard |
| Chat uses CLI string concatenation | Migrate to Anthropic SDK `messages.stream()` |

---

## 6. Should We Do Targeted Fixes or a Full Redesign?

### Argument for Targeted Fixes First

- P0 fixes are 2–4 hours total and unblock Tauri shipping.
- P1 fixes are 1–2 days and eliminate all regularly-broken features.
- The codebase is small enough that targeted fixes are low risk.
- A redesign introduces merge conflicts with any in-flight feature work.

### Argument for a Full Redesign

- The root cause of most P1/P2 issues is the same: no shared state, no stable hooks, no Server/Client split. Patching each symptom individually means re-touching the same files 8–9 times.
- The Tauri integration requires the `AudioUploader` abstraction and `DesktopIndicator` to be built regardless; building them cleanly now is the same effort as bolting them onto the current structure.
- The chat page needs `useSSEStream` and the `AbortController` pattern; that hook will also be used by any future real-time feature.

### Recommendation

**Do P0 fixes immediately (today).** Then do a single structured sprint to address P1 + the component restructure from Section 1 together. Writing the new file layout while fixing P1 issues costs roughly the same as fixing P1 in the old structure and then restructuring later.

Specifically:
1. Fix P0 issues in the current branch (3 surgical edits, commit separately).
2. In a new branch, implement the `usePolling`, `useSSEStream`, `useServerHealth`, and `usePersistentSettings` hooks.
3. Move auto-trigger logic into `SummaryView`. Delete `AutoSummarizeTrigger.tsx`.
4. Add `AudioUploader` and `DesktopIndicator`.
5. Migrate filter state to URL search params.
6. Fix P1-3 (transcript scroll + filter clear) and P1-7/P1-8 (search debounce/sync).
7. Address P2/P3 issues opportunistically during review.

The full redesign (Server Component shells, RSC data loading) can follow as a separate PR once the hook layer is in place. That step is lower risk when the state management is already clean.

---

## Appendix: File Map — Current vs Proposed

| Current file | Disposition |
|---|---|
| `src/app/AutoSummarizeTrigger.tsx` | Delete — logic merged into `SummaryView` |
| `src/app/DashboardClient.tsx` | Keep; add URL-param state, fix selection reset |
| `src/app/MeetingTabs.tsx` | Keep; fix `{ time, seq }` highlight, pass `defaultTab` |
| `src/app/SummaryView.tsx` | Keep; fix P0-1, P0-3, P1-1, P1-2, P1-4 |
| `src/app/TranscriptView.tsx` | Keep; fix P1-3, P2-5, remove unused ref |
| `src/app/SearchBar.tsx` | Keep; fix P1-7, P1-8, P2-6 |
| `src/app/meetings/[id]/chat/page.tsx` | Keep; fix P0-2, P1-6, P1-9 via `useSSEStream` |
| `src/lib/tauri.ts` | Keep as-is — already correct |
| `src/components/client/AudioUploader.tsx` | **New** |
| `src/components/client/DesktopIndicator.tsx` | **New** |
| `src/hooks/usePolling.ts` | **New** |
| `src/hooks/useSSEStream.ts` | **New** |
| `src/hooks/useServerHealth.ts` | **New** (wraps existing `ServerHealthContext`) |
| `src/hooks/usePersistentSettings.ts` | **New** |
| `src/lib/context/ServerHealthContext.tsx` | **New** |
