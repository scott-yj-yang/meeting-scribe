import { Suspense } from "react";
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import MeetingRow from "@/components/MeetingRow";
import SearchBar from "@/components/SearchBar";

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

      {/* Meeting list */}
      {meetings.length === 0 ? (
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
      ) : (
        <div className="overflow-hidden rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900">
          {/* Table header */}
          <div className="flex items-center gap-4 border-b border-gray-200 dark:border-gray-800 px-4 py-2 text-xs font-medium uppercase tracking-wider text-gray-400 dark:text-gray-500">
            <div className="w-2 shrink-0" />
            <div className="flex-1">Title</div>
            <div className="hidden shrink-0 sm:block">Attendees</div>
            <div className="hidden shrink-0 sm:block w-20 text-center">Type</div>
            <div className="hidden shrink-0 text-right sm:block w-24">Duration</div>
            <div className="shrink-0 w-16 text-right">Date</div>
            <div className="w-8 shrink-0" />
          </div>

          {/* Rows */}
          {meetings.map((meeting) => (
            <MeetingRow
              key={meeting.id}
              id={meeting.id}
              title={meeting.title}
              date={meeting.date}
              duration={meeting.duration}
              meetingType={meeting.meetingType}
              hasSummary={meeting.summary !== null}
              calendarTitle={meeting.calendarTitle}
              calendarAttendees={meeting.calendarAttendees}
            />
          ))}
        </div>
      )}

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
    </div>
  );
}
