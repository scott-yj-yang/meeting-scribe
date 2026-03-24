import { notFound } from "next/navigation";
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatDuration } from "@/lib/markdown";
import MeetingTabs from "@/components/MeetingTabs";

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
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

  return (
    <div>
      <div className="mb-6">
        <Link
          href="/"
          className="text-sm font-medium text-blue-600 hover:text-blue-800"
        >
          &larr; Back to meetings
        </Link>
      </div>

      <div className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{meeting.title}</h1>
          <div className="mt-2 flex flex-wrap items-center gap-3 text-sm text-gray-500">
            <span>{formattedDate}</span>
            <span>&middot;</span>
            <span>{formatDuration(meeting.duration)}</span>
            {meeting.meetingType && (
              <>
                <span>&middot;</span>
                <span className="inline-flex items-center rounded-md bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                  {meeting.meetingType}
                </span>
              </>
            )}
          </div>
        </div>

        <div className="flex shrink-0 gap-3">
          <Link
            href={`/meetings/${id}/edit`}
            className="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
          >
            Edit
          </Link>
          <a
            href={`/api/meetings/${id}/export`}
            className="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
          >
            Export .md
          </a>
        </div>
      </div>

      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
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
