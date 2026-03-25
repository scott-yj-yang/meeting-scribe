interface StatusBadgeProps {
  hasSummary: boolean;
}

export default function StatusBadge({ hasSummary }: StatusBadgeProps) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
        hasSummary
          ? "bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200"
          : "bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200"
      }`}
    >
      {hasSummary ? "Summarized" : "Pending"}
    </span>
  );
}
