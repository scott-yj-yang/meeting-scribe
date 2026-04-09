"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import ReactMarkdown from "react-markdown";
import { showNotification } from "@/lib/tauri";
import { apiBase } from "@/lib/api-base";

interface Message {
  role: "user" | "assistant";
  content: string;
}

export default function ChatPage() {
  const { id } = useParams<{ id: string }>();
  const [messages, setMessages] = useState<Message[]>([]);
  const [model, setModel] = useState("sonnet");
  const [thinkingEffort, setThinkingEffort] = useState("medium");
  const [showSettings, setShowSettings] = useState(false);
  const [input, setInput] = useState("");
  const [streaming, setStreaming] = useState(false);
  const [meetingTitle, setMeetingTitle] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  // AbortController ref — one per in-flight request, cleaned up on unmount
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    fetch(`${apiBase()}/api/meetings/${id}`)
      .then((r) => r.json())
      .then((data) => { if (data.title) setMeetingTitle(data.title); })
      .catch(() => {});
  }, [id]);

  // Auto-scroll to the latest message whenever messages update
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  useEffect(() => { inputRef.current?.focus(); }, []);

  // Cancel any in-flight request when the component unmounts
  useEffect(() => {
    return () => {
      abortRef.current?.abort();
    };
  }, []);

  const sendMessage = useCallback(async (overrideText?: string) => {
    const text = (overrideText || input).trim();
    if (!text || streaming) return;
    if (!overrideText) setInput("");

    // Abort any previous in-flight request and create a fresh controller
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const userMessage: Message = { role: "user", content: text };
    // Build a snapshot that includes the user message so the server receives
    // the full up-to-date conversation. Using `messages` directly would send
    // the stale pre-render value and omit this turn (stale-closure bug).
    const historySnapshot: Message[] = [...messages, userMessage];

    setMessages([...historySnapshot, { role: "assistant", content: "" }]);
    setStreaming(true);

    try {
      const res = await fetch(`${apiBase()}/api/meetings/${id}/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: text,
          history: historySnapshot,
          model,
          thinkingEffort,
        }),
        signal: controller.signal,
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: "Request failed" }));
        setMessages((prev) => {
          const updated = [...prev];
          updated[updated.length - 1] = { role: "assistant", content: `Error: ${err.error}` };
          return updated;
        });
        setStreaming(false);
        return;
      }

      const reader = res.body?.getReader();
      const decoder = new TextDecoder();
      if (!reader) { setStreaming(false); return; }

      let fullText = "";
      // leftover holds an incomplete SSE line carried across chunk boundaries
      let leftover = "";

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          // Prepend any leftover from the previous chunk before splitting
          const raw = leftover + decoder.decode(value, { stream: true });
          const lines = raw.split("\n");

          // The last element may be an incomplete line — save it for next read
          leftover = lines.pop() ?? "";

          for (const line of lines) {
            if (line.startsWith("data: ")) {
              try {
                const data = JSON.parse(line.slice(6));
                if (data.done) continue;
                if (data.text) fullText += data.text;
                setMessages((prev) => {
                  const updated = [...prev];
                  updated[updated.length - 1] = { role: "assistant", content: fullText };
                  return updated;
                });
              } catch { /* skip malformed JSON */ }
            }
          }
        }

        // Process any remaining buffered line after the stream closes
        if (leftover.startsWith("data: ")) {
          try {
            const data = JSON.parse(leftover.slice(6));
            if (data.text) {
              fullText += data.text;
              setMessages((prev) => {
                const updated = [...prev];
                updated[updated.length - 1] = { role: "assistant", content: fullText };
                return updated;
              });
            }
          } catch { /* skip */ }
        }
      } finally {
        reader.releaseLock();
      }

      // Notify the user if the tab is in the background when chat completes
      if (typeof document !== "undefined" && document.hidden) {
        await showNotification("MeetingScribe", "Chat response ready").catch(() => {});
      }
    } catch (err) {
      if (err instanceof Error && err.name === "AbortError") {
        // Component unmounted or a new send was triggered — silently exit
        return;
      }
      setMessages((prev) => {
        const updated = [...prev];
        updated[updated.length - 1] = { role: "assistant", content: "Error: Failed to connect." };
        return updated;
      });
    }

    setStreaming(false);
    inputRef.current?.focus();
  }, [id, input, messages, streaming, model, thinkingEffort]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage(); }
  };

  const suggestions = [
    "Summarize in 3 bullet points",
    "What were the key decisions?",
    "List all action items",
    "What was left unresolved?",
  ];

  return (
    <div className="flex h-[calc(100vh-48px)] flex-col bg-white dark:bg-zinc-950 page-transition">
      {/* Header bar */}
      <div className="flex items-center justify-between border-b border-zinc-100 px-5 py-2.5 dark:border-zinc-800/50">
        <Link
          href={`/meetings/${id}`}
          className="flex items-center gap-1.5 text-xs text-zinc-400 transition-colors hover:text-zinc-600 dark:text-zinc-500 dark:hover:text-zinc-300"
        >
          <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
          </svg>
          Back to meeting
        </Link>
        <div className="flex items-center gap-2">
          {meetingTitle && (
            <span className="text-xs text-zinc-400 dark:text-zinc-500 truncate max-w-32">{meetingTitle}</span>
          )}
          <button
            onClick={() => setShowSettings(!showSettings)}
            className={`flex items-center gap-1 rounded-md px-2 py-1 text-xs transition-colors ${
              showSettings
                ? "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
                : "text-zinc-400 hover:text-zinc-600 dark:text-zinc-500 dark:hover:text-zinc-300"
            }`}
          >
            <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M10.343 3.94c.09-.542.56-.94 1.11-.94h1.093c.55 0 1.02.398 1.11.94l.149.894c.07.424.384.764.78.93.398.164.855.142 1.205-.108l.737-.527a1.125 1.125 0 011.45.12l.773.774c.39.389.44 1.002.12 1.45l-.527.737c-.25.35-.272.806-.107 1.204.165.397.505.71.93.78l.893.15c.543.09.94.56.94 1.109v1.094c0 .55-.397 1.02-.94 1.11l-.893.149c-.425.07-.765.383-.93.78-.165.398-.143.854.107 1.204l.527.738c.32.447.269 1.06-.12 1.45l-.774.773a1.125 1.125 0 01-1.449.12l-.738-.527c-.35-.25-.806-.272-1.203-.107-.397.165-.71.505-.781.929l-.149.894c-.09.542-.56.94-1.11.94h-1.094c-.55 0-1.019-.398-1.11-.94l-.148-.894c-.071-.424-.384-.764-.781-.93-.398-.164-.854-.142-1.204.108l-.738.527c-.447.32-1.06.269-1.45-.12l-.773-.774a1.125 1.125 0 01-.12-1.45l.527-.737c.25-.35.273-.806.108-1.204-.165-.397-.506-.71-.93-.78l-.894-.15c-.542-.09-.94-.56-.94-1.109v-1.094c0-.55.398-1.02.94-1.11l.894-.149c.424-.07.765-.383.93-.78.165-.398.143-.854-.108-1.204l-.526-.738a1.125 1.125 0 01.12-1.45l.773-.773a1.125 1.125 0 011.45-.12l.737.527c.35.25.807.272 1.204.107.397-.165.71-.505.78-.929l.15-.894z" />
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            {model}
          </button>
        </div>
      </div>

      {/* Settings bar */}
      {showSettings && (
        <div className="flex items-center gap-4 border-b border-zinc-100 px-5 py-2 dark:border-zinc-800/50">
          <div className="flex items-center gap-2">
            <span className="text-xs text-zinc-400 dark:text-zinc-500">Model</span>
            <select
              value={model}
              onChange={(e) => setModel(e.target.value)}
              className="rounded-md border border-zinc-200 bg-white px-2 py-1 text-xs text-zinc-700 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
            >
              <option value="sonnet">Sonnet (fast)</option>
              <option value="opus">Opus (smartest)</option>
              <option value="haiku">Haiku (fastest)</option>
            </select>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-xs text-zinc-400 dark:text-zinc-500">Thinking</span>
            <select
              value={thinkingEffort}
              onChange={(e) => setThinkingEffort(e.target.value)}
              className="rounded-md border border-zinc-200 bg-white px-2 py-1 text-xs text-zinc-700 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
            >
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
            </select>
          </div>
        </div>
      )}

      {/* Chat area */}
      <div className="flex-1 overflow-y-auto">
        {messages.length === 0 ? (
          /* Empty state */
          <div className="flex h-full flex-col items-center justify-center px-4 gap-4">
            <p className="text-sm text-zinc-400 dark:text-zinc-500">
              Ask anything about &ldquo;{meetingTitle || "this meeting"}&rdquo;
            </p>
            <div className="flex flex-wrap justify-center gap-2">
              {suggestions.map((q) => (
                <button
                  key={q}
                  onClick={() => sendMessage(q)}
                  className="rounded-full border border-zinc-200 px-3.5 py-1.5 text-xs text-zinc-500 transition-all duration-150 hover:scale-[1.03] hover:border-zinc-300 hover:text-zinc-700 dark:border-zinc-700/60 dark:text-zinc-400 dark:hover:border-zinc-600 dark:hover:text-zinc-200"
                >
                  {q}
                </button>
              ))}
            </div>
          </div>
        ) : (
          /* Message list */
          <div className="mx-auto max-w-2xl px-4 py-8 space-y-6">
            {messages.map((msg, i) => (
              <div
                key={i}
                className={`flex animate-in fade-in slide-in-from-bottom-2 duration-200 ${
                  msg.role === "user" ? "justify-end" : "gap-3"
                }`}
              >
                {msg.role === "assistant" ? (
                  <>
                    {/* Assistant avatar */}
                    <div className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-zinc-100 dark:bg-zinc-800">
                      <span className="text-[10px] font-semibold tracking-tight text-zinc-500 dark:text-zinc-400">C</span>
                    </div>
                    <div className="min-w-0 flex-1">
                      {msg.content ? (
                        <div className="prose prose-sm dark:prose-invert max-w-none text-zinc-700 dark:text-zinc-300 prose-p:leading-relaxed prose-p:my-1.5 prose-ul:my-1.5 prose-ol:my-1.5 prose-li:my-0.5 prose-headings:mt-4 prose-headings:mb-2 prose-headings:text-zinc-800 dark:prose-headings:text-zinc-200 prose-strong:text-zinc-800 dark:prose-strong:text-zinc-200 prose-code:text-zinc-700 dark:prose-code:text-zinc-300">
                          <ReactMarkdown>{msg.content}</ReactMarkdown>
                        </div>
                      ) : (
                        streaming && i === messages.length - 1 && (
                          <div className="py-2">
                            <div className="h-1.5 w-1.5 rounded-full bg-zinc-400 dark:bg-zinc-500 animate-pulse" />
                          </div>
                        )
                      )}
                    </div>
                  </>
                ) : (
                  /* User message — right-aligned dark pill */
                  <div className="max-w-[80%] rounded-2xl bg-zinc-900 px-4 py-2.5 dark:bg-zinc-100">
                    <p className="text-sm leading-relaxed text-zinc-100 whitespace-pre-wrap dark:text-zinc-900">{msg.content}</p>
                  </div>
                )}
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Input area */}
      <div className="px-4 pb-4 pt-3">
        <div className="mx-auto max-w-2xl">
          <div className="relative rounded-xl border border-zinc-200/80 bg-white/80 shadow-sm backdrop-blur-sm transition-shadow focus-within:border-zinc-300 focus-within:shadow-md dark:border-zinc-700/60 dark:bg-zinc-900/80 dark:focus-within:border-zinc-600">
            <textarea
              ref={inputRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Ask about this meeting…"
              rows={1}
              className="w-full resize-none border-0 bg-transparent px-4 pb-10 pt-3.5 text-sm text-zinc-900 placeholder-zinc-400 focus:outline-none focus:ring-0 dark:text-zinc-100 dark:placeholder-zinc-500"
              style={{ maxHeight: "160px" }}
              onInput={(e) => {
                const t = e.target as HTMLTextAreaElement;
                t.style.height = "auto";
                t.style.height = Math.min(t.scrollHeight, 160) + "px";
              }}
            />
            <div className="absolute bottom-2.5 right-2.5 flex items-center gap-2">
              {input.length > 0 && (
                <span className="text-[10px] text-zinc-300 dark:text-zinc-600">Enter ↵</span>
              )}
              <button
                onClick={() => sendMessage()}
                disabled={!input.trim() || streaming}
                className="flex h-7 w-7 items-center justify-center rounded-lg bg-zinc-900 text-white transition-all hover:bg-zinc-700 disabled:bg-zinc-100 disabled:text-zinc-300 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300 dark:disabled:bg-zinc-800 dark:disabled:text-zinc-600"
              >
                {/* Arrow up icon */}
                <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={2.5} stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 10.5L12 3m0 0l7.5 7.5M12 3v18" />
                </svg>
              </button>
            </div>
          </div>
          <p className="mt-1.5 text-center text-[10px] text-zinc-300 dark:text-zinc-700">
            Responses are generated using this meeting&apos;s transcript
          </p>
        </div>
      </div>
    </div>
  );
}
