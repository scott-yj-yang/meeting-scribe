"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import MeetingRow from "@/components/MeetingRow";

interface MeetingData {
  id: string;
  title: string;
  date: string; // serialized ISO string from server
  duration: number;
  meetingType: string | null;
  hasSummary: boolean;
  calendarTitle: string | null;
  calendarAttendees: string[];
}

interface DashboardClientProps {
  meetings: MeetingData[];
  total: number;
  page: number;
  totalPages: number;
  q?: string;
  type?: string;
}

function getDateGroupLabel(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();

  // Normalize both to start of day
  const meetingDay = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  const diffMs = today.getTime() - meetingDay.getTime();
  const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));

  if (diffDays === 0) return "Today";
  if (diffDays === 1) return "Yesterday";

  return date.toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

function groupMeetingsByDay(meetings: MeetingData[]): { label: string; meetings: MeetingData[] }[] {
  const groups: { label: string; meetings: MeetingData[] }[] = [];
  let currentLabel = "";

  for (const meeting of meetings) {
    const label = getDateGroupLabel(meeting.date);
    if (label !== currentLabel) {
      currentLabel = label;
      groups.push({ label, meetings: [] });
    }
    groups[groups.length - 1].meetings.push(meeting);
  }

  return groups;
}

export default function DashboardClient({
  meetings,
  total,
  page,
  totalPages,
  q,
  type,
}: DashboardClientProps) {
  const router = useRouter();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [deleting, setDeleting] = useState(false);

  const allSelected = meetings.length > 0 && selected.size === meetings.length;

  function toggleSelectAll() {
    if (allSelected) {
      setSelected(new Set());
    } else {
      setSelected(new Set(meetings.map((m) => m.id)));
    }
  }

  function toggleSelect(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }

  async function handleDeleteSelected() {
    if (selected.size === 0) return;
    setDeleting(true);
    try {
      await Promise.all(
        Array.from(selected).map((id) =>
          fetch(`/api/meetings/${id}`, { method: "DELETE" })
        )
      );
      setSelected(new Set());
      router.refresh();
    } catch {
      // Refresh anyway to show whatever was deleted
      router.refresh();
    } finally {
      setDeleting(false);
    }
  }

  const groups = groupMeetingsByDay(meetings);

  if (meetings.length === 0) {
    return (
      <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 py-16 text-center">
        <div className="mx-auto mb-3 flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 dark:bg-gray-800">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            strokeWidth={1.5}
            stroke="currentColor"
            className="h-5 w-5 text-gray-400 dark:text-gray-500"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m5.231 13.481L15 17.25m-4.5-15H5.625c-.621 0-1.125.504-1.125 1.125v16.5c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Zm3.75 11.625a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z"
            />
          </svg>
        </div>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {q || type ? "No meetings match your filters." : "No meetings yet."}
        </p>
        {(q || type) && (
          <Link
            href="/"
            className="mt-2 inline-block text-sm font-medium text-gray-900 dark:text-gray-100 underline decoration-gray-300 dark:decoration-gray-600 underline-offset-4 hover:decoration-gray-500 dark:hover:decoration-gray-400"
          >
            Clear filters
          </Link>
        )}
      </div>
    );
  }

  return (
    <>
      <div className="overflow-hidden rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900">
        {/* Table header */}
        <div className="flex items-center gap-4 border-b border-gray-200 dark:border-gray-800 px-4 py-2 text-xs font-medium uppercase tracking-wider text-gray-400 dark:text-gray-500">
          <div className="w-6 shrink-0 flex items-center justify-center">
            <input
              type="checkbox"
              checked={allSelected}
              onChange={toggleSelectAll}
              className="h-3.5 w-3.5 rounded border-gray-300 dark:border-gray-600 text-blue-600 focus:ring-blue-500 cursor-pointer"
              aria-label="Select all meetings"
            />
          </div>
          <div className="w-2 shrink-0" />
          <div className="flex-1">Title</div>
          <div className="hidden shrink-0 sm:block">Attendees</div>
          <div className="hidden shrink-0 sm:block w-20 text-center">Type</div>
          <div className="hidden shrink-0 text-right sm:block w-24">Duration</div>
          <div className="shrink-0 w-16 text-right">Date</div>
          <div className="w-8 shrink-0" />
        </div>

        {/* Grouped rows */}
        {groups.map((group) => (
          <div key={group.label}>
            {/* Day group header */}
            <div className="border-b border-gray-100 dark:border-gray-800 bg-gray-50/80 dark:bg-gray-900/80 px-4 py-1.5">
              <span className="text-xs font-semibold text-gray-500 dark:text-gray-400">
                {group.label}
              </span>
            </div>
            {group.meetings.map((meeting) => (
              <div key={meeting.id} className="flex items-center">
                <div
                  className="shrink-0 flex items-center justify-center pl-4"
                  onClick={(e) => e.stopPropagation()}
                >
                  <input
                    type="checkbox"
                    checked={selected.has(meeting.id)}
                    onChange={() => toggleSelect(meeting.id)}
                    className="h-3.5 w-3.5 rounded border-gray-300 dark:border-gray-600 text-blue-600 focus:ring-blue-500 cursor-pointer"
                    aria-label={`Select ${meeting.title}`}
                  />
                </div>
                <div className="flex-1 min-w-0">
                  <MeetingRow
                    id={meeting.id}
                    title={meeting.title}
                    date={new Date(meeting.date)}
                    duration={meeting.duration}
                    meetingType={meeting.meetingType}
                    hasSummary={meeting.hasSummary}
                    calendarTitle={meeting.calendarTitle}
                    calendarAttendees={meeting.calendarAttendees}
                  />
                </div>
              </div>
            ))}
          </div>
        ))}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="mt-6 flex items-center justify-center gap-4 text-sm">
          {page > 1 ? (
            <a
              href={`/?page=${page - 1}${q ? `&q=${encodeURIComponent(q)}` : ""}${type ? `&type=${encodeURIComponent(type)}` : ""}`}
              className="font-medium text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100"
            >
              Previous
            </a>
          ) : (
            <span className="font-medium text-gray-300 dark:text-gray-600">
              Previous
            </span>
          )}
          <span className="text-gray-400 dark:text-gray-500">
            {page} / {totalPages}
          </span>
          {page < totalPages ? (
            <a
              href={`/?page=${page + 1}${q ? `&q=${encodeURIComponent(q)}` : ""}${type ? `&type=${encodeURIComponent(type)}` : ""}`}
              className="font-medium text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100"
            >
              Next
            </a>
          ) : (
            <span className="font-medium text-gray-300 dark:text-gray-600">
              Next
            </span>
          )}
        </div>
      )}

      {/* Floating action bar for batch delete */}
      {selected.size > 0 && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-50">
          <div className="flex items-center gap-4 rounded-full border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 px-6 py-3 shadow-lg">
            <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
              {selected.size} selected
            </span>
            <button
              onClick={handleDeleteSelected}
              disabled={deleting}
              className="inline-flex items-center rounded-full bg-red-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:opacity-50"
            >
              {deleting ? "Deleting..." : "Delete Selected"}
            </button>
          </div>
        </div>
      )}
    </>
  );
}
