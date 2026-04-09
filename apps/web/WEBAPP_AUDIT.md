# MeetingScribe Webapp — Interactive Elements Audit

**Date:** 2026-04-09  
**Branch:** `feat/hallucination-detection-timestamps-tauri`  
**Auditor:** Claude Code (automated review)  
**Scope:** Seven client-side components plus their backing API routes.

---

## Severity Legend

| Level | Meaning |
|-------|---------|
| **CRITICAL** | Data loss, silent failure, or broken core flow |
| **HIGH** | Feature regularly broken or produces wrong output |
| **MEDIUM** | Annoying or confusing UX; wrong behavior under common conditions |
| **LOW** | Minor cosmetic or code-quality issue |

---

## 1. `DashboardClient.tsx`

### What Works
- Select-all / deselect-all checkbox logic is correct (functional update pattern on `toggleSelect`).
- Floating delete bar appears only when items are selected and is disabled during the delete request.
- Empty-state message changes correctly between "no meetings" and "no matches" based on filter presence.
- Date grouping is straightforward and handles Today/Yesterday labels.

### Bugs & Issues

#### [MEDIUM] `allSelected` miscounts across pages
```ts
const allSelected = meetings.length > 0 && selected.size === meetings.length;
```
`selected` persists across `router.refresh()` calls. If the user selects 5 items, deletes them, and the next page now shows 5 different meetings, `allSelected` will be `true` immediately—before the user has touched anything. The selection set is never cleared when the meeting list changes from the server.

**Fix:** Reset `selected` inside a `useEffect` keyed on the `meetings` prop (e.g., compare meeting IDs).

#### [MEDIUM] Batch delete swallows individual failures silently
```ts
await Promise.all(
  Array.from(selected).map((id) =>
    fetch(`/api/meetings/${id}`, { method: "DELETE" })
  )
);
```
`Promise.all` with plain `fetch` does not throw on a non-2xx response—`fetch` only rejects on network failure. If one DELETE returns 500, the catch branch is never hit, and `router.refresh()` is called anyway. The failed item disappears from `selected` but may still appear in the refreshed list with no error shown.

**Fix:** Check `res.ok` inside the map, collect failures, and show an error count to the user.

#### [LOW] Pagination uses `<a>` not `<Link>`
```tsx
<a href={`/?page=${page - 1}...`}>Previous</a>
```
A plain `<a>` tag causes a full page reload instead of a client-side navigation, discarding any React state. This is inconsistent with the rest of the app which uses Next.js `<Link>`.

**Fix:** Replace `<a>` tags in the pagination block with `<Link href="...">`.

#### [LOW] `groupMeetingsByDay` assumes sorted input
The function uses a `currentLabel` running variable and compares adjacent entries. If the server ever returns meetings in a non-chronological order (e.g., after a filter), the same day will appear as two separate groups.

**Fix:** Sort by date before grouping, or use a `Map<string, Meeting[]>` accumulator.

---

## 2. `MeetingTabs.tsx`

### What Works
- Tab switching between Summary / Transcript / Raw Markdown is correct.
- `highlightTime` flows properly from the parent into `TranscriptView` and is cleared after 3 seconds.
- The "Raw Markdown" copy button uses `setCopied` + a timeout, which is safe.

### Bugs & Issues

#### [MEDIUM] `highlightTime` is not cleared when switching away from Transcript then back
The 3-second timer clears `highlightTime` in state, but the `useEffect` fires based on the value changing. If the user clicks a timestamp link while already on the Transcript tab, then switches to Summary, then back to Transcript within 3 seconds, the segment is already highlighted but scrolling will not fire again (the `highlightTime` value hasn't changed, so the `useEffect` in `TranscriptView` is not re-triggered).

**Fix:** Use a monotonically increasing counter or a `{ time, seq }` object so the effect always fires, even for the same timestamp clicked twice.

#### [LOW] Default tab ignores URL-driven tab state
`useState<Tab>(summaryContent ? "Summary" : "Transcript")` is evaluated once at mount. If a user navigates to a meeting detail page via a deep link that should open the Transcript tab, there is no mechanism to honour that preference.

**Fix:** Accept an optional `defaultTab` prop or read from `searchParams` in the parent Server Component.

#### [LOW] `handleCopy` has no error handling
```ts
await navigator.clipboard.writeText(rawMarkdown);
```
`navigator.clipboard` is unavailable in non-secure (non-HTTPS) contexts and can throw a `DOMException` even in secure contexts (e.g., when the page is not focused). A rejected promise here goes unhandled.

**Fix:** Wrap in `try/catch` and show an error state instead of silently failing.

---

## 3. `SummaryView.tsx`

### What Works
- The polling loop correctly exits when `cancelledRef.current` is set.
- The 409-conflict auto-retry with `force: true` is a clean recovery path.
- The elapsed timer is driven by `setInterval` referencing a `startTimeRef` rather than accumulating seconds, which avoids drift.
- Notion export shows the URL inline after success.

### Bugs & Issues

#### [CRITICAL] Timer resets when a running job is resumed on mount
```ts
// In the "resume polling" branch (mount useEffect):
if (data.elapsedSeconds) {
  startTimeRef.current = Date.now() - data.elapsedSeconds * 1000;
  setElapsed(data.elapsedSeconds);
}
// ...
setLoading(true);
```
Then, in the second `useEffect` keyed on `loading`:
```ts
if (loading) {
  startTimeRef.current = Date.now();   // ← overwrites the correct value!
  setElapsed(0);
```
When `setLoading(true)` is called in the first effect, the second effect fires synchronously in the same render cycle and resets `startTimeRef.current` to `Date.now()`, discarding the server-provided elapsed time.

**Fix:** Guard the timer-reset effect so it only runs when transitioning from `false → true`:
```ts
const prevLoadingRef = useRef(false);
useEffect(() => {
  if (loading && !prevLoadingRef.current) {
    startTimeRef.current = startTimeRef.current ?? Date.now();
    setElapsed(0);
  }
  prevLoadingRef.current = loading;
  // ... interval setup
}, [loading]);
```
Or, simpler: set `startTimeRef` in the timer effect only if it is `null`.

#### [CRITICAL] `window.location.reload()` on summarization complete
Both the mount-resume poll and the main `handleSummarize` poll call `window.location.reload()` on completion. This is a full hard reload, which:
- Loses any unsaved form state on the page.
- Is incompatible with Tauri's embedded WebView if navigation history matters.
- Does not work at all in environments where `window` is not defined (SSR edge cases, test runners).

**Fix:** Use `router.refresh()` (from `useRouter`) to re-fetch Server Component data without a full navigation, then optionally update local state to transition out of the loading skeleton.

#### [HIGH] Race condition: poll can fire after component unmount
The polling function is a plain recursive `setTimeout` closure—not attached to any cleanup mechanism. If the user navigates away from the meeting detail page while summarization is in progress, the poll continues running in the background and will call `window.location.reload()` or `setError` (calling setState on an unmounted component).

**Fix:** Use a `useRef<boolean>` "mounted" flag set to `false` in the `useEffect` cleanup, and check it before every `setTimeout(poll, 3000)` and before every `setState` call inside the poll.

#### [HIGH] `handleResummarize` does not await or handle errors
```ts
const handleResummarize = () => {
  handleSummarize(customInstruction || undefined);  // unawaited Promise
  setShowResummarize(false);
  setCustomInstruction("");
};
```
`handleSummarize` is `async`. If it throws before the try block (e.g., immediately), the error is swallowed. The UI transitions to the skeleton via `setLoading(true)` inside `handleSummarize`, but if that never happens the button state is never updated.

**Fix:** Make `handleResummarize` async and await `handleSummarize`, or move the state cleanup into `handleSummarize` itself.

#### [MEDIUM] `claudeReady` state flickers on every mount
`fetch("/api/health/claude")` is called unconditionally in the mount effect. This means every time the user switches to the Summary tab (MeetingTabs unmounts/remounts the child), a network request fires and `claudeReady` briefly returns to `null`, which hides the "Claude Code not installed" warning for a fraction of a second.

**Fix:** Lift the `claudeReady` check to the parent `MeetingTabs` level or cache it with a global/context store.

#### [MEDIUM] Error shown alongside "No summary yet" disappears on retry
When `handleSummarize` is called from the Retry button in the error state, `setError(null)` and `setLoading(true)` fire. The error message vanishes but the skeleton is shown. If the retry itself fails, the error is set again. This is logically correct but the sequence "error → skeleton → error" with no persistent history can be confusing if polling takes a long time before failing.

**Fix:** Add a `retryCount` counter and show "Retry failed (attempt N)" in the error message.

---

## 4. `TranscriptView.tsx`

### What Works
- Filter by speaker or text is case-insensitive and updates live.
- Time-gap separators (`> 30s`) correctly reference the filtered list, not the original, so gaps only appear between visible segments.
- Highlight logic handles both exact overlap (`startTime <= t < endTime`) and a 1-second proximity fallback.
- `scrollIntoView` targets the correct DOM id (`seg-${target.id}`).

### Bugs & Issues

#### [HIGH] Highlight does not trigger scroll when filter is active
```ts
// useEffect reads `segments` (original), but renders `filtered`
const target =
  segments.find((s) => s.startTime <= highlightTime && highlightTime < s.endTime) ...
```
When a filter is applied, the element `seg-${target.id}` may not be in the DOM (because the matching segment was filtered out). `document.getElementById` returns `null` and `el?.scrollIntoView` silently does nothing. The user clicks a timestamp in the summary, the tab switches, but the segment is invisible under the current filter—no feedback is given.

**Fix:** Either (a) clear the filter when a timestamp navigation occurs, or (b) search within `filtered` instead of `segments` and show a "no visible match—clear filter" message when the target segment is absent.

#### [MEDIUM] Filter input not cleared when `highlightTime` changes
If a user types a filter, then clicks a summary timestamp, the transcript view switches to the transcript tab but the filter text remains. The target segment might not be visible. There is no user affordance to explain why nothing is highlighted.

**Fix:** In the `useEffect([highlightTime])` block, call `setFilter("")` before scrolling when `highlightTime` is non-null.

#### [LOW] `containerRef` is declared but never used
```ts
const containerRef = useRef<HTMLDivElement>(null);
```
The ref is attached to the outer `<div>` but never read anywhere in the component.

**Fix:** Remove the unused ref, or use it for the `scrollIntoView` call (passing the container as the scroll target).

---

## 5. `app/meetings/[id]/chat/page.tsx`

### What Works
- SSE streaming is implemented correctly at the chunk level (split on `\n`, prefix `data: `).
- The `streaming` guard prevents double-sends while a response is in-flight.
- Suggestion pills call `sendMessage(q)` directly, bypassing the input field correctly.
- Auto-resize textarea via `onInput` + `scrollHeight` is correct.

### Bugs & Issues

#### [CRITICAL] History sent to server is always one message stale
```ts
const newMessages = [...messages, userMessage];
setMessages(newMessages);               // schedules React state update
setStreaming(true);
setMessages((prev) => [...prev, { role: "assistant", content: "" }]);

const res = await fetch(`/api/meetings/${id}/chat`, {
  body: JSON.stringify({ message: text, history: messages, ... }),
  //                                            ^^^^^^^^
  //                              still the OLD messages array!
```
Because `setMessages` is asynchronous, `messages` in the closure still refers to the value captured when `sendMessage` was called—which does not include the new user message. The API therefore never sees the user's most recent turn in the history, and the assistant has no memory of the previous exchange.

**Fix:** Build `newMessages` before the fetch and pass `newMessages.slice(0, -1)` (all history except the pending assistant placeholder) as `history`:
```ts
const newMessages = [...messages, userMessage];
setMessages(newMessages);
// ...
body: JSON.stringify({ message: text, history: newMessages, ... })
```

#### [HIGH] Suggestion pills disappear immediately after first message
The suggestions block is rendered only when `messages.length === 0`. Clicking a suggestion calls `sendMessage(q)`, which sets `messages` to `[userMessage, emptyAssistant]`, so the empty state is gone before the user sees any response. This is intentional, but if the server returns an error on the very first message, the suggestions never come back and the user is left with an empty-looking error state.

**Fix:** Show the empty state (including suggestions) until the assistant has produced at least one non-empty response.

#### [HIGH] Stream reader is not cancelled on component unmount
The `while (true)` loop reading from `reader` has no cleanup. If the user navigates away mid-stream, the `ReadableStreamDefaultReader` is left open, keeping the HTTP connection alive. The background loop will continue calling `setMessages` on the unmounted component (React 18 removes the warning but the state update is still wasteful) until the server closes the connection.

**Fix:** Return a cleanup function from the `sendMessage` call or use an `AbortController` passed to `fetch`. Cancel the controller in a `useEffect` cleanup.

#### [MEDIUM] `sendMessage` has `messages` in its dependency array
```ts
const sendMessage = useCallback(async (overrideText?: string) => {
  ...
}, [id, input, messages, streaming]);
```
Because `messages` is in the dependency array, `sendMessage` is recreated on every incoming chunk (every `setMessages` call during streaming). This is not a correctness bug, but it causes unnecessary re-renders of any component holding the callback reference and can create subtle closure-capture bugs in future refactoring.

**Fix:** Remove `messages` from the dependency array and use the functional-update form where needed: `setMessages(prev => [...prev, userMessage])`. Read the current `messages` at call time via a ref if needed.

#### [MEDIUM] `model` and `thinkingEffort` not persisted across page visits
Model and thinking effort settings reset to defaults (`"sonnet"`, `"medium"`) on every page load. Users who prefer `opus` or `high` effort must re-set every visit.

**Fix:** Persist settings to `localStorage` with a `useEffect`.

#### [LOW] Chat API constructs prompt by string concatenation, not native multi-turn format
The chat route builds the entire conversation as one giant string passed to `claude -p`. Claude Code's `--print` mode does not support multi-turn conversation natively this way—the "history" is simulated. This means the model cannot distinguish between system, user, and assistant roles with proper attention masking.

**Fix:** If the Anthropic SDK is available, use the `/messages` endpoint with a proper `messages` array instead of the CLI subprocess.

---

## 6. `AutoSummarizeTrigger.tsx`

### What Works
- The `triggered` ref prevents double-fires within the same mount lifecycle.
- Silent failure (doing nothing on error) is appropriate here since it's a background auto-trigger.

### Bugs & Issues

#### [HIGH] Race condition with `SummaryView`'s own job detection
`AutoSummarizeTrigger` fires a POST to `/summarize` on mount. `SummaryView` also checks `/summarize/status` on mount and resumes polling if a job is running. If both components mount simultaneously (which they do—`AutoSummarizeTrigger` is a sibling of `MeetingTabs`), both will fire their respective effects in the same event-loop tick:

1. `AutoSummarizeTrigger` POSTs to start a job.
2. `SummaryView` GETs `/summarize/status`.

If the status GET resolves before the POST response returns, `SummaryView` will see `status: "idle"` and not attach a polling loop. It will then wait for the next user interaction to show any progress, even though summarization has started.

**Fix:** Move auto-summarize logic into `SummaryView` itself (or a shared context), so there is a single authoritative polling loop rather than two components independently managing job state.

#### [HIGH] `window.location.reload()` inside poll
Same issue as in `SummaryView` — the poll calls `window.location.reload()` on completion, which is a hard reload incompatible with Tauri and loses page state.

**Fix:** Use `router.refresh()` from `useRouter`.

#### [MEDIUM] No loading feedback to the user
The auto-summarize trigger fires silently. The user sees the "No summary yet" screen, and then 30-90 seconds later the page suddenly reloads with a summary. There is no spinner, progress indicator, or notification that something is happening.

**Fix:** Pass a callback prop (e.g., `onStarted`) back to the parent or into `SummaryView` so the loading skeleton can be shown immediately when auto-summarize fires.

#### [LOW] `localStorage` access is not guarded for SSR
```ts
const autoSummarize = localStorage.getItem(AUTO_SUMMARIZE_KEY) === "true";
```
This is inside a `useEffect`, so it is safe in Next.js (effects never run server-side). However, if the file is ever moved or the component is used outside of `"use client"` context, this will throw `ReferenceError: localStorage is not defined`.

**Fix:** Wrap in `typeof window !== "undefined" && localStorage.getItem(...)` as a defensive guard.

---

## 7. `SearchBar.tsx`

### What Works
- Type-filter pills navigate correctly, preserving the current search query.
- URL encoding of query parameters is correct (`encodeURIComponent`).
- The component correctly reads its initial state from server-rendered props.

### Bugs & Issues

#### [HIGH] Clicking a type pill while typing discards in-progress query
```ts
function handleTypeClick(type: string) {
  navigate(query, type);
}
```
`query` is the local React state, which is synced with the text input. However, `navigate` calls `router.push`, which triggers a full server re-render. The new page is rendered with the updated `initialQuery` prop from the URL, but the `useState(initialQuery)` initializer only runs once at mount. If the user navigates back and the `SearchBar` re-mounts, `query` will be correct again—but if Next.js reuses the component instance (same route, different search params), `initialQuery` changes but `useState` does not re-initialize.

**Fix:** Add a `useEffect` that syncs `query` state to `initialQuery` when the prop changes:
```ts
useEffect(() => { setQuery(initialQuery); }, [initialQuery]);
```

#### [HIGH] No debounce or auto-submit on search input
The search input only triggers navigation on form `submit` (pressing Enter). There is no debounce auto-search as the user types. Combined with the type pills (which navigate immediately on click), the UX is inconsistent: clicking a pill is instant, but changing the text requires pressing Enter.

**Fix:** Add a debounced `useEffect` on `query` that calls `navigate(query, initialType)` after ~300 ms, giving the same instant-feel as the filter pills.

#### [MEDIUM] Active pill highlight uses `initialType`, not local state
```tsx
className={initialType === type ? "bg-gray-900 ..." : "bg-gray-100 ..."}
```
When a pill is clicked, `router.push` fires and the component may stay mounted during the navigation. During the transition, the `initialType` prop hasn't updated yet, but visually the old pill remains highlighted. There is a brief flash where the newly-clicked pill appears inactive.

**Fix:** Maintain a local `activeType` state initialized from `initialType` and update it immediately on click before navigation resolves.

#### [LOW] Search clears to `"All"` type on query submit
```ts
function handleSubmit(e: React.FormEvent) {
  navigate(query, initialType);
}
```
If the user has selected the "1:1" filter pill and then types in the search box and presses Enter, `initialType` correctly carries the current type filter through. This is actually fine, but only because `handleSubmit` uses `initialType` (the prop) not a local type state. This creates a subtle coupling: if the component ever gains local type state, submit behaviour must be updated accordingly.

---

## Cross-Cutting Issues

### [CRITICAL] `window.location.reload()` used in 3 places
`SummaryView.tsx` (×2) and `AutoSummarizeTrigger.tsx` (×1) use `window.location.reload()` to refresh data after summarization completes. This is the most impactful issue in the entire webapp because it:
1. Causes a full browser page reload, discarding all React state.
2. Breaks the Tauri desktop integration (the Tauri shell may not handle `window.location` reloads the same way as a normal browser navigation).
3. Is incompatible with Next.js App Router's incremental revalidation design.

**Unified fix:** Replace all three call sites with `router.refresh()` and, where necessary, use a `key` prop or local state to reset UI after the server data is refreshed.

### [HIGH] No global loading/error state for the summarize job
Both `SummaryView` and `AutoSummarizeTrigger` independently manage summarize job state. There is no shared context or store. If the user opens a second browser tab to the same meeting while summarization is running, the two tabs will have desynchronized states and may both try to start jobs (resulting in a 409, then a force-restart).

**Fix:** Consider a React Context or a simple SWR/React Query cache for the summarize job status.

### [MEDIUM] Missing `aria-live` regions on dynamic content
The streaming chat response, summarization progress, and error messages are all injected into the DOM dynamically but have no `aria-live` attributes. Screen reader users will not be notified of status changes.

**Fix:** Add `aria-live="polite"` to the streaming chat area and summarization status messages.

---

## Summary Table

| Component | Issue | Severity |
|-----------|-------|----------|
| DashboardClient | `selected` set survives refresh, causes false `allSelected` | MEDIUM |
| DashboardClient | Batch delete swallows per-item HTTP errors | MEDIUM |
| DashboardClient | Pagination uses `<a>` (full reload) not `<Link>` | LOW |
| DashboardClient | `groupMeetingsByDay` assumes sorted input | LOW |
| MeetingTabs | `highlightTime` re-click after 3s doesn't re-scroll | MEDIUM |
| MeetingTabs | Default tab ignores URL state | LOW |
| MeetingTabs | `handleCopy` unhandled promise rejection | LOW |
| SummaryView | Timer `startTimeRef` reset overwrites server-elapsed on resume | CRITICAL |
| SummaryView | `window.location.reload()` — hard reload, Tauri-incompatible | CRITICAL |
| SummaryView | Polling continues after component unmount (setState leak) | HIGH |
| SummaryView | `handleResummarize` is unawaited async | HIGH |
| SummaryView | `claudeReady` refetched on every tab switch | MEDIUM |
| TranscriptView | Scroll to highlighted segment fails when filter is active | HIGH |
| TranscriptView | Filter not cleared on timestamp navigation | MEDIUM |
| TranscriptView | `containerRef` unused | LOW |
| Chat page | `history` sent to API is one message stale (closure capture) | CRITICAL |
| Chat page | Suggestions lost after first message, never restored on error | HIGH |
| Chat page | Stream reader not cancelled on unmount | HIGH |
| Chat page | `sendMessage` recreated every streaming chunk | MEDIUM |
| Chat page | Model/effort settings not persisted | MEDIUM |
| Chat page | Chat uses CLI string concatenation, not SDK messages API | LOW |
| AutoSummarizeTrigger | Race condition with `SummaryView` status polling on mount | HIGH |
| AutoSummarizeTrigger | `window.location.reload()` — hard reload | HIGH |
| AutoSummarizeTrigger | No user-visible loading feedback during auto-summarize | MEDIUM |
| SearchBar | `query` state not synced when `initialQuery` prop changes | HIGH |
| SearchBar | No debounce/auto-search; inconsistent UX vs type pills | HIGH |
| SearchBar | Active pill flashes inactive during navigation | MEDIUM |
