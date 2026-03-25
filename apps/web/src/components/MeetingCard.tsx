import Link from "next/link";
import { formatDuration } from "@/lib/markdown";
import StatusBadge from "./StatusBadge";

interface MeetingCardProps {
  id: string;
  title: string;
  date: Date;
  duration: number;
  meetingType: string | null;
  hasSummary: boolean;
}

export default function MeetingCard({
  id,
  title,
  date,
  duration,
  meetingType,
  hasSummary,
}: MeetingCardProps) {
  const formattedDate = new Date(date).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

  return (
    <Link
      href={`/meetings/${id}`}
      className="block rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 p-5 shadow-sm transition-shadow hover:shadow-md"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-base font-semibold text-gray-900 dark:text-gray-100">
            {title}
          </h3>
          <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">{formattedDate}</p>
          <p className="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
            {formatDuration(duration)}
          </p>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-2">
          <StatusBadge hasSummary={hasSummary} />
          {meetingType && (
            <span className="inline-flex items-center rounded-md bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
              {meetingType}
            </span>
          )}
        </div>
      </div>
    </Link>
  );
}
