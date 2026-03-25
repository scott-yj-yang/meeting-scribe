import { Suspense } from "react";
import { prisma } from "@/lib/prisma";
import SearchBar from "@/components/SearchBar";
import DashboardClient from "@/components/DashboardClient";

const LIMIT = 20;

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; page?: string; type?: string }>;
}) {
  const { q, page: pageParam, type } = await searchParams;
  const page = Math.max(1, parseInt(pageParam ?? "1", 10));

  const conditions: Record<string, unknown>[] = [];

  if (q) {
    conditions.push({
      OR: [
        { title: { contains: q, mode: "insensitive" as const } },
        {
          transcript: {
            rawMarkdown: { contains: q, mode: "insensitive" as const },
          },
        },
      ],
    });
  }

  if (type && type !== "All") {
    conditions.push({ meetingType: type });
  }

  const where = conditions.length > 0 ? { AND: conditions } : undefined;

  const [meetings, total] = await Promise.all([
    prisma.meeting.findMany({
      where,
      orderBy: { date: "desc" },
      skip: (page - 1) * LIMIT,
      take: LIMIT,
      include: {
        summary: { select: { id: true } },
      },
    }),
    prisma.meeting.count({ where }),
  ]);

  const totalPages = Math.ceil(total / LIMIT);

  // Serialize meetings data for the client component
  const serializedMeetings = meetings.map((meeting) => ({
    id: meeting.id,
    title: meeting.title,
    date: meeting.date.toISOString(),
    duration: meeting.duration,
    meetingType: meeting.meetingType,
    hasSummary: meeting.summary !== null,
    calendarTitle: meeting.calendarTitle,
    calendarAttendees: meeting.calendarAttendees,
  }));

  return (
    <div className="mx-auto max-w-5xl">
      {/* Header */}
      <div className="mb-8 pt-2">
        <h1 className="text-3xl font-bold tracking-tight text-gray-900 dark:text-gray-100">
          MeetingScribe
        </h1>
        <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
          Your meetings, transcripts, and summaries in one place.
        </p>
      </div>

      {/* Filter bar */}
      <div className="mb-6">
        <Suspense fallback={null}>
          <SearchBar initialQuery={q ?? ""} initialType={type ?? "All"} />
        </Suspense>
      </div>

      {/* Meeting list with batch select, group by day */}
      <DashboardClient
        meetings={serializedMeetings}
        total={total}
        page={page}
        totalPages={totalPages}
        q={q}
        type={type}
      />
    </div>
  );
}
