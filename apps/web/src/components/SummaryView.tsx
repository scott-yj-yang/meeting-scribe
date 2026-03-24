"use client";

import { useState, useCallback } from "react";
import ReactMarkdown from "react-markdown";

interface SummaryViewProps {
  content: string | null;
  meetingId: string;
}

export default function SummaryView({ content, meetingId }: SummaryViewProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSummarize = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/meetings/${meetingId}/summarize`, {
        method: "POST",
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error || "Failed to start summarization");
      }

      // Poll for completion
      const poll = async () => {
        const statusRes = await fetch(
          `/api/meetings/${meetingId}/summarize/status`,
        );
        if (!statusRes.ok) {
          throw new Error("Failed to check summarization status");
        }
        const statusData = await statusRes.json();
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
      setError(err instanceof Error ? err.message : "An error occurred");
      setLoading(false);
    }
  }, [meetingId]);

  if (content) {
    return (
      <div className="prose prose-sm max-w-none">
        <ReactMarkdown>{content}</ReactMarkdown>
      </div>
    );
  }

  return (
    <div className="py-12 text-center">
      <p className="mb-4 text-sm text-gray-500">No summary yet.</p>
      {error && <p className="mb-4 text-sm text-red-600">{error}</p>}
      <button
        onClick={handleSummarize}
        disabled={loading}
        className="inline-flex items-center rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {loading ? "Summarizing..." : "Summarize with Claude"}
      </button>
    </div>
  );
}
