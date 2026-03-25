"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import ReactMarkdown from "react-markdown";

interface Message {
  role: "user" | "assistant";
  content: string;
}

export default function ChatPage() {
  const { id } = useParams<{ id: string }>();
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [streaming, setStreaming] = useState(false);
  const [meetingTitle, setMeetingTitle] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    fetch(`/api/meetings/${id}`)
      .then((r) => r.json())
      .then((data) => { if (data.title) setMeetingTitle(data.title); })
      .catch(() => {});
  }, [id]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  useEffect(() => { inputRef.current?.focus(); }, []);

  const sendMessage = useCallback(async (overrideText?: string) => {
    const text = (overrideText || input).trim();
    if (!text || streaming) return;
    if (!overrideText) setInput("");

    const userMessage: Message = { role: "user", content: text };
    const newMessages = [...messages, userMessage];
    setMessages(newMessages);
    setStreaming(true);
    setMessages((prev) => [...prev, { role: "assistant", content: "" }]);

    try {
      const res = await fetch(`/api/meetings/${id}/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text, history: messages }),
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
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const chunk = decoder.decode(value, { stream: true });
        for (const line of chunk.split("\n")) {
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
            } catch { /* skip */ }
          }
        }
      }
    } catch {
      setMessages((prev) => {
        const updated = [...prev];
        updated[updated.length - 1] = { role: "assistant", content: "Error: Failed to connect." };
        return updated;
      });
    }
    setStreaming(false);
    inputRef.current?.focus();
  }, [id, input, messages, streaming]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage(); }
  };

  const suggestions = [
    "Summarize this meeting in 3 bullet points",
    "What were the key decisions?",
    "List all action items with owners",
    "What questions were left unresolved?",
  ];

  return (
    <div className="flex h-[calc(100vh-48px)] flex-col bg-white dark:bg-gray-950">
      {/* Header bar */}
      <div className="flex items-center justify-between border-b border-gray-100 px-5 py-2.5 dark:border-gray-800/60">
        <div className="flex items-center gap-3">
          <Link
            href={`/meetings/${id}`}
            className="flex items-center gap-1 text-xs text-gray-400 transition-colors hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300"
          >
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
            </svg>
            Back to meeting
          </Link>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-xs text-gray-400 dark:text-gray-500">{meetingTitle}</span>
        </div>
      </div>

      {/* Chat area */}
      <div className="flex-1 overflow-y-auto">
        {messages.length === 0 ? (
          /* Empty state */
          <div className="flex h-full flex-col items-center justify-center px-4">
            <div className="mb-5 flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-br from-amber-200 to-orange-300 dark:from-amber-700 dark:to-orange-600">
              <svg className="h-5 w-5 text-amber-800 dark:text-amber-100" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 00-2.455 2.456z" />
              </svg>
            </div>
            <h2 className="mb-1 text-base font-medium text-gray-800 dark:text-gray-200">
              What would you like to know?
            </h2>
            <p className="mb-8 max-w-md text-center text-sm text-gray-400 dark:text-gray-500">
              I have the full transcript for &ldquo;{meetingTitle}&rdquo; loaded. Ask me anything about it.
            </p>
            <div className="grid w-full max-w-lg grid-cols-2 gap-2">
              {suggestions.map((q) => (
                <button
                  key={q}
                  onClick={() => sendMessage(q)}
                  className="rounded-xl border border-gray-150 bg-gray-50/50 px-4 py-3 text-left text-sm text-gray-600 transition-all hover:border-gray-250 hover:bg-gray-100/80 dark:border-gray-800 dark:bg-gray-900/50 dark:text-gray-400 dark:hover:border-gray-700 dark:hover:bg-gray-800/80"
                >
                  {q}
                </button>
              ))}
            </div>
          </div>
        ) : (
          /* Message list */
          <div className="mx-auto max-w-2xl px-4 py-8">
            {messages.map((msg, i) => (
              <div key={i} className={`mb-6 ${msg.role === "user" ? "flex justify-end" : ""}`}>
                {msg.role === "assistant" ? (
                  /* Assistant message — claude.ai style */
                  <div className="flex gap-3">
                    <div className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-amber-200 to-orange-300 dark:from-amber-700 dark:to-orange-600">
                      <svg className="h-3.5 w-3.5 text-amber-800 dark:text-amber-100" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09z" />
                      </svg>
                    </div>
                    <div className="min-w-0 flex-1">
                      {msg.content ? (
                        <div className="prose prose-sm dark:prose-invert max-w-none prose-p:leading-relaxed prose-p:my-1.5 prose-ul:my-1.5 prose-ol:my-1.5 prose-li:my-0.5 prose-headings:mt-4 prose-headings:mb-2">
                          <ReactMarkdown>{msg.content}</ReactMarkdown>
                        </div>
                      ) : (
                        streaming && i === messages.length - 1 && (
                          <div className="flex items-center gap-1.5 py-2">
                            <div className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-400" style={{ animationDelay: "0ms" }} />
                            <div className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-400" style={{ animationDelay: "150ms" }} />
                            <div className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-400" style={{ animationDelay: "300ms" }} />
                          </div>
                        )
                      )}
                    </div>
                  </div>
                ) : (
                  /* User message */
                  <div className="max-w-[80%] rounded-2xl bg-gray-100 px-4 py-2.5 dark:bg-gray-800">
                    <p className="text-sm leading-relaxed text-gray-800 whitespace-pre-wrap dark:text-gray-200">{msg.content}</p>
                  </div>
                )}
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Input area — claude.ai style */}
      <div className="border-t border-gray-100 bg-white px-4 pb-4 pt-3 dark:border-gray-800/60 dark:bg-gray-950">
        <div className="mx-auto max-w-2xl">
          <div className="relative rounded-2xl border border-gray-200 bg-white shadow-sm transition-shadow focus-within:border-gray-300 focus-within:shadow-md dark:border-gray-700 dark:bg-gray-900 dark:focus-within:border-gray-600">
            <textarea
              ref={inputRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Message Claude..."
              rows={1}
              className="w-full resize-none border-0 bg-transparent px-4 pb-10 pt-3.5 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-0 dark:text-gray-100 dark:placeholder-gray-500"
              style={{ maxHeight: "160px" }}
              onInput={(e) => {
                const t = e.target as HTMLTextAreaElement;
                t.style.height = "auto";
                t.style.height = Math.min(t.scrollHeight, 160) + "px";
              }}
            />
            <div className="absolute bottom-2 right-2 flex items-center gap-2">
              <span className="text-xs text-gray-300 dark:text-gray-600">
                {input.length > 0 ? "Enter ↵" : ""}
              </span>
              <button
                onClick={() => sendMessage()}
                disabled={!input.trim() || streaming}
                className="flex h-8 w-8 items-center justify-center rounded-lg bg-gray-900 text-white transition-all hover:bg-black disabled:bg-gray-200 disabled:text-gray-400 dark:bg-gray-100 dark:text-gray-900 dark:hover:bg-white dark:disabled:bg-gray-800 dark:disabled:text-gray-600"
              >
                <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 10.5L12 3m0 0l7.5 7.5M12 3v18" />
                </svg>
              </button>
            </div>
          </div>
          <p className="mt-1.5 text-center text-xs text-gray-300 dark:text-gray-600">
            Responses are generated by Claude Code using this meeting&apos;s transcript
          </p>
        </div>
      </div>
    </div>
  );
}
