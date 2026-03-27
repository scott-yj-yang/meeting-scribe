"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import ReactMarkdown from "react-markdown";

interface SummaryViewProps {
  content: string | null;
  meetingId: string;
}

function formatElapsed(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function SummarizingSkeleton({ elapsed, onCancel }: { elapsed: number; onCancel: () => void }) {
  return (
    <div className="py-8">
      <div className="mb-6 text-center">
        <div className="flex items-center justify-center gap-3">
          <p className="text-sm font-medium text-gray-700 dark:text-gray-300">
            Summarizing... {formatElapsed(elapsed)}
          </p>
          <button
            onClick={onCancel}
            className="inline-flex items-center rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2.5 py-1 text-xs font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-1"
          >
            Cancel
          </button>
        </div>
      </div>
      <div className="space-y-4">
        {/* Skeleton bars */}
        <div className="space-y-3">
          <div className="h-5 w-3/4 rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" />
          <div className="h-4 w-full rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" style={{ animationDelay: "0.1s" }} />
          <div className="h-4 w-5/6 rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" style={{ animationDelay: "0.2s" }} />
          <div className="h-4 w-full rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" style={{ animationDelay: "0.3s" }} />
          <div className="h-4 w-2/3 rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" style={{ animationDelay: "0.4s" }} />
        </div>
        <div className="space-y-3 pt-2">
          <div className="h-5 w-1/2 rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" style={{ animationDelay: "0.5s" }} />
          <div className="h-4 w-full rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" style={{ animationDelay: "0.6s" }} />
          <div className="h-4 w-4/5 rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" style={{ animationDelay: "0.7s" }} />
          <div className="h-4 w-full rounded bg-gray-200 dark:bg-gray-700 animate-skeleton-pulse" style={{ animationDelay: "0.8s" }} />
        </div>
      </div>
    </div>
  );
}

export default function SummaryView({ content, meetingId }: SummaryViewProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showResummarize, setShowResummarize] = useState(false);
  const [customInstruction, setCustomInstruction] = useState("");
  const [claudeReady, setClaudeReady] = useState<boolean | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const startTimeRef = useRef<number | null>(null);
  const cancelledRef = useRef(false);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    fetch("/api/health/claude")
      .then((res) => res.json())
      .then((data) => setClaudeReady(data.status === "ready"))
      .catch(() => setClaudeReady(false));
  }, []);

  // Start/stop the live timer whenever loading changes
  useEffect(() => {
    if (loading) {
      startTimeRef.current = Date.now();
      setElapsed(0);
      cancelledRef.current = false;
      timerRef.current = setInterval(() => {
        setElapsed(Math.floor((Date.now() - (startTimeRef.current ?? Date.now())) / 1000));
      }, 1000);
    } else {
      if (timerRef.current !== null) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    }
    return () => {
      if (timerRef.current !== null) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [loading]);

  const handleCancel = useCallback(async () => {
    // Cancel on server too
    await fetch(`/api/meetings/${meetingId}/summarize`, { method: "DELETE" }).catch(() => {});
    cancelledRef.current = true;
    setLoading(false);
    setElapsed(0);
  }, [meetingId]);

  const handleSummarize = useCallback(async (instruction?: string, force?: boolean) => {
    setLoading(true);
    setError(null);
    try {
      const body: Record<string, unknown> = {};
      if (instruction) body.customInstruction = instruction;
      if (force) body.force = true;

      let res = await fetch(`/api/meetings/${meetingId}/summarize`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });

      // If 409 (already running), auto-force retry
      if (res.status === 409) {
        res = await fetch(`/api/meetings/${meetingId}/summarize`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ ...body, force: true }),
        });
      }

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error || "Failed to start summarization");
      }

      // Poll for completion
      const poll = async () => {
        // Stop polling if user cancelled
        if (cancelledRef.current) return;

        const statusRes = await fetch(
          `/api/meetings/${meetingId}/summarize/status`,
        );
        if (!statusRes.ok) {
          throw new Error("Failed to check summarization status");
        }
        const statusData = await statusRes.json();

        if (cancelledRef.current) return;

        if (statusData.status === "completed") {
          window.location.reload();
          return;
        }
        if (statusData.status === "failed") {
          throw new Error(statusData.error || "Summarization failed");
        }
        setTimeout(poll, 3000);
      };
      await poll();
    } catch (err) {
      if (!cancelledRef.current) {
        setError(err instanceof Error ? err.message : "An error occurred");
        setLoading(false);
      }
    }
  }, [meetingId]);

  const handleResummarize = () => {
    handleSummarize(customInstruction || undefined);
    setShowResummarize(false);
    setCustomInstruction("");
  };

  const [notionLoading, setNotionLoading] = useState(false);
  const [notionUrl, setNotionUrl] = useState<string | null>(null);
  const [notionError, setNotionError] = useState<string | null>(null);

  const handleSendToNotion = useCallback(async () => {
    setNotionLoading(true);
    setNotionError(null);
    try {
      const res = await fetch(`/api/meetings/${meetingId}/notion`, {
        method: "POST",
      });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error || "Failed to sync to Notion");
      }
      setNotionUrl(data.url);
    } catch (err) {
      setNotionError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setNotionLoading(false);
    }
  }, [meetingId]);

  if (loading) {
    return <SummarizingSkeleton elapsed={elapsed} onCancel={handleCancel} />;
  }

  if (content) {
    return (
      <div>
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <button
            onClick={handleSendToNotion}
            disabled={notionLoading}
            className="inline-flex items-center rounded-md bg-gray-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-gray-700 disabled:opacity-50"
          >
            {notionLoading ? "Sending..." : "Send to Notion"}
          </button>
          <button
            onClick={() => setShowResummarize(!showResummarize)}
            className="inline-flex items-center rounded-md border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3 py-1.5 text-xs font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700"
          >
            Resummarize
          </button>
          {notionUrl && (
            <a
              href={notionUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-blue-600 hover:underline"
            >
              View in Notion
            </a>
          )}
          {notionError && (
            <span className="text-xs text-red-600">{notionError}</span>
          )}
        </div>

        {showResummarize && (
          <div className="mb-4 rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Custom instructions (optional)
            </label>
            <textarea
              value={customInstruction}
              onChange={(e) => setCustomInstruction(e.target.value)}
              placeholder="e.g. Focus on action items, be more concise, include technical details..."
              className="w-full rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-900 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
              rows={3}
            />
            <div className="mt-3 flex items-center gap-2">
              <button
                onClick={handleResummarize}
                className="inline-flex items-center rounded-md bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
              >
                Regenerate Summary
              </button>
              <button
                onClick={() => { setShowResummarize(false); setCustomInstruction(""); }}
                className="inline-flex items-center rounded-md border border-gray-300 dark:border-gray-600 px-3 py-1.5 text-xs font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"
              >
                Cancel
              </button>
            </div>
          </div>
        )}

        {error && (
          <div className="mb-4 flex items-center gap-3 rounded-md border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 px-3 py-2">
            <p className="flex-1 text-sm text-red-700 dark:text-red-400">{error}</p>
            <button
              onClick={() => handleSummarize(customInstruction || undefined)}
              className="shrink-0 inline-flex items-center rounded-md bg-red-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-1"
            >
              Retry
            </button>
          </div>
        )}

        <div className="prose prose-sm dark:prose-invert max-w-none">
          <ReactMarkdown>{content}</ReactMarkdown>
        </div>
      </div>
    );
  }

  return (
    <div className="py-12 text-center">
      <p className="mb-4 text-sm text-gray-500 dark:text-gray-400">No summary yet.</p>
      {error && (
        <div className="mb-4 flex items-center justify-center gap-3 rounded-md border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 px-3 py-2 mx-auto max-w-md">
          <p className="flex-1 text-sm text-red-700 dark:text-red-400 text-left">{error}</p>
          <button
            onClick={() => handleSummarize()}
            className="shrink-0 inline-flex items-center rounded-md bg-red-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-1"
          >
            Retry
          </button>
        </div>
      )}
      {claudeReady === false && (
        <p className="mb-3 text-xs text-amber-600 dark:text-amber-400">
          Claude Code not installed —{" "}
          <a
            href="https://docs.anthropic.com/en/docs/claude-code"
            target="_blank"
            rel="noopener noreferrer"
            className="underline hover:no-underline"
          >
            install it
          </a>{" "}
          to enable summarization.
        </p>
      )}
      <button
        onClick={() => handleSummarize()}
        disabled={loading || claudeReady === false}
        title={claudeReady === false ? "Claude Code not installed" : undefined}
        className="inline-flex items-center rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Summarize with Claude
      </button>
    </div>
  );
}
