"use client";

import { useState, useEffect, useRef, Fragment } from "react";

interface Segment {
  id: string;
  speaker: string;
  text: string;
  startTime: number;
  endTime: number;
}

interface TranscriptViewProps {
  segments: Segment[];
  highlightTime?: number | null;
}

function formatTimestamp(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

/** Visual separator for time gaps > 30 seconds between segments. */
function TimeGap({ seconds }: { seconds: number }) {
  const m = Math.floor(seconds / 60);
  const label = m > 0 ? `${m} min gap` : `${Math.floor(seconds)}s gap`;
  return (
    <div className="flex items-center gap-2 py-1.5">
      <div className="flex-1 border-t border-dashed border-gray-300 dark:border-gray-600" />
      <span className="text-[11px] text-gray-400 dark:text-gray-500">{label}</span>
      <div className="flex-1 border-t border-dashed border-gray-300 dark:border-gray-600" />
    </div>
  );
}

export default function TranscriptView({ segments, highlightTime }: TranscriptViewProps) {
  const [filter, setFilter] = useState("");
  const containerRef = useRef<HTMLDivElement>(null);

  const filtered = filter
    ? segments.filter(
        (seg) =>
          seg.text.toLowerCase().includes(filter.toLowerCase()) ||
          seg.speaker.toLowerCase().includes(filter.toLowerCase()),
      )
    : segments;

  // Scroll to and highlight the segment matching highlightTime
  useEffect(() => {
    if (highlightTime == null || segments.length === 0) return;

    // Find the segment containing this timestamp, or the closest one
    const target =
      segments.find((s) => s.startTime <= highlightTime && highlightTime < s.endTime) ??
      segments.reduce((closest, seg) =>
        Math.abs(seg.startTime - highlightTime) < Math.abs(closest.startTime - highlightTime)
          ? seg
          : closest,
      );

    if (target) {
      const el = document.getElementById(`seg-${target.id}`);
      el?.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }, [highlightTime, segments]);

  return (
    <div ref={containerRef}>
      <div className="mb-4">
        <input
          type="text"
          placeholder="Filter by speaker or text..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="w-full rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
        />
      </div>

      {filtered.length === 0 ? (
        <p className="py-8 text-center text-sm text-gray-500 dark:text-gray-400">
          {segments.length === 0
            ? "No transcript segments available."
            : "No segments match your filter."}
        </p>
      ) : (
        <div className="space-y-1">
          {filtered.map((seg, idx) => {
            const prev = idx > 0 ? filtered[idx - 1] : null;
            const gap = prev ? seg.startTime - prev.endTime : 0;
            const isHighlighted =
              highlightTime != null &&
              seg.startTime <= highlightTime &&
              (seg.endTime > highlightTime ||
                Math.abs(seg.startTime - highlightTime) < 1);

            return (
              <Fragment key={seg.id}>
                {gap > 30 && <TimeGap seconds={gap} />}
                <div
                  id={`seg-${seg.id}`}
                  className={`flex gap-3 rounded-md px-2 py-1.5 transition-all duration-500 ${
                    isHighlighted
                      ? "bg-yellow-100 dark:bg-yellow-900/30 ring-2 ring-yellow-400 dark:ring-yellow-600"
                      : ""
                  }`}
                >
                  <span className="shrink-0 pt-0.5 font-mono text-xs text-gray-400 dark:text-gray-500 tabular-nums">
                    {formatTimestamp(seg.startTime)}
                  </span>
                  <p className="text-sm text-gray-800 dark:text-gray-200 leading-relaxed">
                    <span className="font-semibold text-gray-900 dark:text-gray-100">
                      {seg.speaker}:
                    </span>{" "}
                    {seg.text}
                  </p>
                </div>
              </Fragment>
            );
          })}
        </div>
      )}
    </div>
  );
}
