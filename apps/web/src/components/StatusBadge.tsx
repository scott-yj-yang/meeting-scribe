interface StatusBadgeProps {
  hasSummary: boolean;
}

export default function StatusBadge({ hasSummary }: StatusBadgeProps) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
        hasSummary
          ? "bg-green-100 text-green-800"
          : "bg-yellow-100 text-yellow-800"
      }`}
    >
      {hasSummary ? "Summarized" : "Pending"}
    </span>
  );
}
