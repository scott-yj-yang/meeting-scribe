"use client";

import { useEffect, useRef } from "react";

const AUTO_SUMMARIZE_KEY = "meetingscribe_auto_summarize";

interface AutoSummarizeTriggerProps {
  meetingId: string;
  hasSummary: boolean;
}

export default function AutoSummarizeTrigger({
  meetingId,
  hasSummary,
}: AutoSummarizeTriggerProps) {
  const triggered = useRef(false);

  useEffect(() => {
    if (hasSummary || triggered.current) return;

    const autoSummarize = localStorage.getItem(AUTO_SUMMARIZE_KEY) === "true";
    if (!autoSummarize) return;

    triggered.current = true;

    fetch(`/api/meetings/${meetingId}/summarize`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    })
      .then((res) => {
        if (!res.ok) return;
        // Poll for completion then reload
        const poll = () => {
          fetch(`/api/meetings/${meetingId}/summarize/status`)
            .then((r) => r.json())
            .then((data) => {
              if (data.status === "completed") {
                window.location.reload();
              } else if (data.status === "failed") {
                // silently fail — user can manually trigger
              } else {
                setTimeout(poll, 3000);
              }
            })
            .catch(() => {});
        };
        poll();
      })
      .catch(() => {});
  }, [meetingId, hasSummary]);

  return null;
}
