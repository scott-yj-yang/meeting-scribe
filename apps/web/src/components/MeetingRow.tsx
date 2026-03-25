"use client";

import Link from "next/link";
import { formatDuration } from "@/lib/markdown";
import MeetingActions from "./MeetingActions";

interface MeetingRowProps {
  id: string;
  title: string;
  date: Date;
  duration: number;
  meetingType: string | null;
  hasSummary: boolean;
  calendarTitle: string | null;
  calendarAttendees: string[];
}

const MEETING_TYPE_COLORS: Record<string, string> = {
  "1:1": "bg-sky-50 text-sky-700 ring-sky-600/20 dark:bg-sky-950/50 dark:text-sky-300 dark:ring-sky-500/30",
  Subgroup:
    "bg-violet-50 text-violet-700 ring-violet-600/20 dark:bg-violet-950/50 dark:text-violet-300 dark:ring-violet-500/30",
  "Lab Meeting":
    "bg-amber-50 text-amber-700 ring-amber-600/20 dark:bg-amber-950/50 dark:text-amber-300 dark:ring-amber-500/30",
  Casual:
    "bg-rose-50 text-rose-700 ring-rose-600/20 dark:bg-rose-950/50 dark:text-rose-300 dark:ring-rose-500/30",
  Standup:
    "bg-emerald-50 text-emerald-700 ring-emerald-600/20 dark:bg-emerald-950/50 dark:text-emerald-300 dark:ring-emerald-500/30",
};

function getTypeColor(type: string): string {
  return (
    MEETING_TYPE_COLORS[type] ??
    "bg-blue-50 text-blue-700 ring-blue-600/20 dark:bg-blue-950/50 dark:text-blue-300 dark:ring-blue-500/30"
  );
}

function getRelativeTime(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - new Date(date).getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHour = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHour / 24);
  const diffWeek = Math.floor(diffDay / 7);
  const diffMonth = Math.floor(diffDay / 30);

  if (diffSec < 60) return "just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHour < 24) return `${diffHour}h ago`;
  if (diffDay === 1) return "yesterday";
  if (diffDay < 7) return `${diffDay}d ago`;
  if (diffWeek < 5) return `${diffWeek}w ago`;
  if (diffMonth < 12) return `${diffMonth}mo ago`;
  return new Date(date).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function getInitials(name: string): string {
  return name
    .split(/[\s@]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
}

const AVATAR_COLORS = [
  "bg-blue-100 text-blue-700 dark:bg-blue-900/60 dark:text-blue-300",
  "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/60 dark:text-emerald-300",
  "bg-amber-100 text-amber-700 dark:bg-amber-900/60 dark:text-amber-300",
  "bg-rose-100 text-rose-700 dark:bg-rose-900/60 dark:text-rose-300",
  "bg-purple-100 text-purple-700 dark:bg-purple-900/60 dark:text-purple-300",
  "bg-cyan-100 text-cyan-700 dark:bg-cyan-900/60 dark:text-cyan-300",
];

function hashString(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0;
  }
  return Math.abs(hash);
}

export default function MeetingRow({
  id,
  title,
  date,
  duration,
  meetingType,
  hasSummary,
  calendarTitle,
  calendarAttendees,
}: MeetingRowProps) {
  return (
    <Link
      href={`/meetings/${id}`}
      className="group flex items-center gap-4 border-b border-gray-100 dark:border-gray-800 px-4 py-3 transition-colors hover:bg-gray-50 dark:hover:bg-gray-900/50"
    >
      {/* Status dot */}
      <div className="shrink-0">
        <span
          className={`inline-block h-2 w-2 rounded-full ${
            hasSummary
              ? "bg-emerald-500 dark:bg-emerald-400"
              : "bg-amber-400 dark:bg-amber-500"
          }`}
          title={hasSummary ? "Summarized" : "Pending summary"}
        />
      </div>

      {/* Title + calendar */}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-semibold text-gray-900 dark:text-gray-100">
            {title}
          </span>
          {calendarTitle && (
            <span className="hidden items-center gap-1 truncate text-xs text-gray-400 dark:text-gray-500 sm:inline-flex">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 16 16"
                fill="currentColor"
                className="h-3 w-3 shrink-0"
              >
                <path
                  fillRule="evenodd"
                  d="M4 1.75a.75.75 0 0 1 1.5 0V3h5V1.75a.75.75 0 0 1 1.5 0V3a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2V1.75ZM4.5 6a1 1 0 0 0-1 1v4.5a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1h-7Z"
                  clipRule="evenodd"
                />
              </svg>
              {calendarTitle}
            </span>
          )}
        </div>
      </div>

      {/* Attendees */}
      <div className="hidden shrink-0 sm:flex">
        {calendarAttendees.length > 0 && (
          <div className="flex -space-x-1.5">
            {calendarAttendees.slice(0, 4).map((attendee, i) => {
              const initials = getInitials(attendee);
              const colorIdx = hashString(attendee) % AVATAR_COLORS.length;
              return (
                <span
                  key={i}
                  className={`inline-flex h-6 w-6 items-center justify-center rounded-full text-[10px] font-medium ring-2 ring-white dark:ring-gray-950 ${AVATAR_COLORS[colorIdx]}`}
                  title={attendee}
                >
                  {initials}
                </span>
              );
            })}
            {calendarAttendees.length > 4 && (
              <span className="inline-flex h-6 w-6 items-center justify-center rounded-full bg-gray-100 dark:bg-gray-800 text-[10px] font-medium text-gray-500 dark:text-gray-400 ring-2 ring-white dark:ring-gray-950">
                +{calendarAttendees.length - 4}
              </span>
            )}
          </div>
        )}
      </div>

      {/* Meeting type pill */}
      <div className="hidden shrink-0 sm:block">
        {meetingType ? (
          <span
            className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${getTypeColor(meetingType)}`}
          >
            {meetingType}
          </span>
        ) : (
          <span className="inline-block w-16" />
        )}
      </div>

      {/* Duration */}
      <div className="hidden shrink-0 text-right sm:block">
        <span className="text-xs text-gray-400 dark:text-gray-500">
          {formatDuration(duration)}
        </span>
      </div>

      {/* Date */}
      <div className="shrink-0 text-right">
        <span className="text-xs text-gray-400 dark:text-gray-500">
          {getRelativeTime(date)}
        </span>
      </div>

      {/* Delete button - visible on hover */}
      <div className="shrink-0 opacity-0 transition-opacity group-hover:opacity-100">
        <MeetingActions meetingId={id} />
      </div>
    </Link>
  );
}
