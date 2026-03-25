"use client";

import { useState } from "react";

interface Segment {
  id: string;
  speaker: string;
  text: string;
  startTime: number;
  endTime: number;
}

interface TranscriptViewProps {
  segments: Segment[];
}

function formatTimestamp(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

export default function TranscriptView({ segments }: TranscriptViewProps) {
  const [filter, setFilter] = useState("");

  const filtered = filter
    ? segments.filter(
        (seg) =>
          seg.text.toLowerCase().includes(filter.toLowerCase()) ||
          seg.speaker.toLowerCase().includes(filter.toLowerCase()),
      )
    : segments;

  return (
    <div>
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
        <div className="space-y-3">
          {filtered.map((seg) => (
            <div key={seg.id} className="flex gap-3">
              <span className="shrink-0 font-mono text-sm text-gray-400 dark:text-gray-500">
                {formatTimestamp(seg.startTime)}
              </span>
              <p className="text-sm text-gray-800 dark:text-gray-200">
                <span className="font-bold text-gray-900 dark:text-gray-100">{seg.speaker}:</span>{" "}
                {seg.text}
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
