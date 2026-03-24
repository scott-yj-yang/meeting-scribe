import { Suspense } from "react";
import { prisma } from "@/lib/prisma";
import MeetingCard from "@/components/MeetingCard";
import SearchBar from "@/components/SearchBar";

const LIMIT = 20;

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; page?: string }>;
}) {
  const { q, page: pageParam } = await searchParams;
  const page = Math.max(1, parseInt(pageParam ?? "1", 10));

  const where = q
    ? {
        OR: [
          { title: { contains: q, mode: "insensitive" as const } },
          {
            transcript: {
              rawMarkdown: { contains: q, mode: "insensitive" as const },
            },
          },
        ],
      }
    : undefined;

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
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Meetings</h1>
      </div>

      <div className="mb-6">
        <Suspense fallback={null}>
          <SearchBar initialQuery={q ?? ""} />
        </Suspense>
      </div>

      {meetings.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-white py-12 text-center">
          <p className="text-sm text-gray-500">
            {q ? `No meetings found matching "${q}".` : "No meetings yet."}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {meetings.map((meeting) => (
            <MeetingCard
              key={meeting.id}
              id={meeting.id}
              title={meeting.title}
              date={meeting.date}
              duration={meeting.duration}
              meetingType={meeting.meetingType}
              hasSummary={meeting.summary !== null}
            />
          ))}
        </div>
      )}

      {totalPages > 1 && (
        <div className="mt-6 text-center text-sm text-gray-500">
          Page {page} of {totalPages}
        </div>
      )}
    </div>
  );
}
