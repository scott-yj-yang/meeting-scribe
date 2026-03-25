import { notFound } from "next/navigation";
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatDuration } from "@/lib/markdown";
import MeetingTabs from "@/components/MeetingTabs";
import ChatLauncher from "@/components/ChatLauncher";
import AutoSummarizeTrigger from "@/components/AutoSummarizeTrigger";

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

function formatTimeRange(start: Date, end: Date): string {
  const fmt = (d: Date) =>
    new Date(d).toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
    });
  return `${fmt(start)} - ${fmt(end)}`;
}

export default async function MeetingDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const meeting = await prisma.meeting.findUnique({
    where: { id },
    include: {
      transcript: {
        include: {
          segments: {
            orderBy: { startTime: "asc" },
          },
        },
      },
      summary: true,
    },
  });

  if (!meeting) {
    notFound();
  }

  const formattedDate = new Date(meeting.date).toLocaleDateString("en-US", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });

  const hasCalendar =
    meeting.calendarTitle ||
    meeting.calendarOrganizer ||
    meeting.calendarAttendees.length > 0;

  return (
    <div className="mx-auto max-w-4xl page-transition">
      {/* Breadcrumb */}
      <div className="mb-8">
        <Link
          href="/"
          className="inline-flex items-center gap-1 text-sm text-gray-400 dark:text-gray-500 transition-colors hover:text-gray-600 dark:hover:text-gray-300"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 16 16"
            fill="currentColor"
            className="h-3.5 w-3.5"
          >
            <path
              fillRule="evenodd"
              d="M9.78 4.22a.75.75 0 0 1 0 1.06L7.06 8l2.72 2.72a.75.75 0 1 1-1.06 1.06L5.47 8.53a.75.75 0 0 1 0-1.06l3.25-3.25a.75.75 0 0 1 1.06 0Z"
              clipRule="evenodd"
            />
          </svg>
          Back to meetings
        </Link>
      </div>

      {/* Title - Notion-style large title */}
      <h1 className="mb-4 text-4xl font-bold tracking-tight text-gray-900 dark:text-gray-100">
        {meeting.title}
      </h1>

      {/* Metadata row */}
      <div className="mb-6 flex flex-wrap items-center gap-3 text-sm text-gray-500 dark:text-gray-400">
        <span>{formattedDate}</span>
        <span className="text-gray-300 dark:text-gray-600">/</span>
        <span>{formatDuration(meeting.duration)}</span>
        {meeting.meetingType && (
          <>
            <span className="text-gray-300 dark:text-gray-600">/</span>
            <span
              className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${getTypeColor(meeting.meetingType)}`}
            >
              {meeting.meetingType}
            </span>
          </>
        )}
      </div>

      {/* Calendar section */}
      {hasCalendar && (
        <div className="mb-6 rounded-lg border border-gray-200 dark:border-gray-800 bg-gray-50/50 dark:bg-gray-900/50 p-4">
          <div className="mb-2 flex items-center gap-2 text-xs font-medium uppercase tracking-wider text-gray-400 dark:text-gray-500">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 16 16"
              fill="currentColor"
              className="h-3.5 w-3.5"
            >
              <path
                fillRule="evenodd"
                d="M4 1.75a.75.75 0 0 1 1.5 0V3h5V1.75a.75.75 0 0 1 1.5 0V3a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2V1.75ZM4.5 6a1 1 0 0 0-1 1v4.5a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1h-7Z"
                clipRule="evenodd"
              />
            </svg>
            Calendar Event
          </div>
          <div className="space-y-2">
            {meeting.calendarTitle && (
              <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                {meeting.calendarTitle}
              </p>
            )}
            <div className="flex flex-wrap items-center gap-3 text-sm text-gray-500 dark:text-gray-400">
              {meeting.calendarOrganizer && (
                <span className="flex items-center gap-1">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 16 16"
                    fill="currentColor"
                    className="h-3.5 w-3.5"
                  >
                    <path d="M8 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM12.735 14c.618 0 1.093-.561.872-1.139a6.002 6.002 0 0 0-11.215 0c-.22.578.254 1.139.872 1.139h9.47Z" />
                  </svg>
                  {meeting.calendarOrganizer}
                </span>
              )}
              {meeting.calendarStart && meeting.calendarEnd && (
                <span className="flex items-center gap-1">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 16 16"
                    fill="currentColor"
                    className="h-3.5 w-3.5"
                  >
                    <path
                      fillRule="evenodd"
                      d="M1 8a7 7 0 1 1 14 0A7 7 0 0 1 1 8Zm7.75-4.25a.75.75 0 0 0-1.5 0V8c0 .414.336.75.75.75h3.25a.75.75 0 0 0 0-1.5h-2.5v-3.5Z"
                      clipRule="evenodd"
                    />
                  </svg>
                  {formatTimeRange(meeting.calendarStart, meeting.calendarEnd)}
                </span>
              )}
            </div>
            {meeting.calendarAttendees.length > 0 && (
              <div className="flex flex-wrap gap-1.5 pt-1">
                {meeting.calendarAttendees.map((attendee, i) => (
                  <span
                    key={i}
                    className="inline-flex items-center rounded-md bg-white dark:bg-gray-800 px-2 py-0.5 text-xs text-gray-700 dark:text-gray-300 ring-1 ring-inset ring-gray-200 dark:ring-gray-700"
                  >
                    {attendee}
                  </span>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Action buttons row */}
      <div className="mb-8 flex flex-wrap items-center gap-3">
        <Link
          href={`/meetings/${id}/edit`}
          className="inline-flex items-center gap-1.5 rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 transition-colors hover:bg-gray-50 dark:hover:bg-gray-800 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 dark:focus:ring-offset-gray-950"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 16 16"
            fill="currentColor"
            className="h-3.5 w-3.5"
          >
            <path d="M13.488 2.513a1.75 1.75 0 0 0-2.475 0L6.75 6.774a2.75 2.75 0 0 0-.596.892l-.848 2.047a.75.75 0 0 0 .98.98l2.047-.848a2.75 2.75 0 0 0 .892-.596l4.261-4.262a1.75 1.75 0 0 0 0-2.474Z" />
            <path d="M4.75 3.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h6.5c.69 0 1.25-.56 1.25-1.25V9A.75.75 0 0 1 14 9v2.25A2.75 2.75 0 0 1 11.25 14h-6.5A2.75 2.75 0 0 1 2 11.25v-6.5A2.75 2.75 0 0 1 4.75 2H7a.75.75 0 0 1 0 1.5H4.75Z" />
          </svg>
          Edit
        </Link>
        <a
          href={`/api/meetings/${id}/export`}
          className="inline-flex items-center gap-1.5 rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 transition-colors hover:bg-gray-50 dark:hover:bg-gray-800 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 dark:focus:ring-offset-gray-950"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 16 16"
            fill="currentColor"
            className="h-3.5 w-3.5"
          >
            <path d="M8.75 2.75a.75.75 0 0 0-1.5 0v5.69L5.03 6.22a.75.75 0 0 0-1.06 1.06l3.5 3.5a.75.75 0 0 0 1.06 0l3.5-3.5a.75.75 0 0 0-1.06-1.06L8.75 8.44V2.75Z" />
            <path d="M3.5 9.75a.75.75 0 0 0-1.5 0v1.5A2.75 2.75 0 0 0 4.75 14h6.5A2.75 2.75 0 0 0 14 11.25v-1.5a.75.75 0 0 0-1.5 0v1.5c0 .69-.56 1.25-1.25 1.25h-6.5c-.69 0-1.25-.56-1.25-1.25v-1.5Z" />
          </svg>
          Export .md
        </a>
        <ChatLauncher meetingId={id} />
      </div>

      {/* Auto-summarize trigger */}
      <AutoSummarizeTrigger meetingId={meeting.id} hasSummary={meeting.summary !== null} />

      {/* Content tabs */}
      <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6">
        <MeetingTabs
          meetingId={meeting.id}
          summaryContent={meeting.summary?.content ?? null}
          segments={
            meeting.transcript?.segments.map((seg) => ({
              id: seg.id,
              speaker: seg.speaker,
              text: seg.text,
              startTime: seg.startTime,
              endTime: seg.endTime,
            })) ?? []
          }
          rawMarkdown={meeting.transcript?.rawMarkdown ?? null}
        />
      </div>
    </div>
  );
}
