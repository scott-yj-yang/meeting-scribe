"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

interface SearchBarProps {
  initialQuery?: string;
  initialType?: string;
}

const FILTER_TYPES = ["All", "1:1", "Subgroup", "Lab Meeting", "Casual", "Standup"] as const;

export default function SearchBar({
  initialQuery = "",
  initialType = "All",
}: SearchBarProps) {
  const router = useRouter();
  const [query, setQuery] = useState(initialQuery);

  function navigate(q: string, type: string) {
    const params = new URLSearchParams();
    if (q.trim()) params.set("q", q.trim());
    if (type && type !== "All") params.set("type", type);
    const qs = params.toString();
    router.push(qs ? `/?${qs}` : "/");
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    navigate(query, initialType);
  }

  function handleTypeClick(type: string) {
    navigate(query, type);
  }

  return (
    <div className="space-y-3">
      {/* Filter pills */}
      <div className="flex flex-wrap items-center gap-2">
        {FILTER_TYPES.map((type) => (
          <button
            key={type}
            onClick={() => handleTypeClick(type)}
            className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
              initialType === type
                ? "bg-gray-900 text-white dark:bg-gray-100 dark:text-gray-900"
                : "bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700"
            }`}
          >
            {type}
          </button>
        ))}
      </div>

      {/* Search input */}
      <form onSubmit={handleSubmit} className="w-full">
        <div className="relative">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            strokeWidth={1.5}
            stroke="currentColor"
            className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 dark:text-gray-500"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"
            />
          </svg>
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search meetings..."
            className="w-full rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 py-2 pl-9 pr-4 text-sm text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500 transition-colors focus:border-gray-300 dark:focus:border-gray-600 focus:outline-none focus:ring-0"
          />
        </div>
      </form>
    </div>
  );
}
