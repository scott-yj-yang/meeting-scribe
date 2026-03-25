"use client";

import { useState } from "react";
import { useRouter, usePathname } from "next/navigation";

export default function MeetingActions({ meetingId }: { meetingId: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const [confirming, setConfirming] = useState(false);

  const isDetailPage = pathname?.startsWith(`/meetings/${meetingId}`);

  const handleDelete = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();

    if (!confirming) {
      setConfirming(true);
      return;
    }

    await fetch(`/api/meetings/${meetingId}`, { method: "DELETE" });

    if (isDetailPage) {
      router.push("/");
    } else {
      router.refresh();
    }
    setConfirming(false);
  };

  const handleCancel = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setConfirming(false);
  };

  return (
    <div className="flex items-center gap-2" onClick={(e) => { e.preventDefault(); e.stopPropagation(); }}>
      {confirming ? (
        <>
          <button
            onClick={handleDelete}
            className="rounded px-2 py-1 text-xs font-medium text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/30"
          >
            Confirm
          </button>
          <button
            onClick={handleCancel}
            className="rounded px-2 py-1 text-xs text-gray-500 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800"
          >
            Cancel
          </button>
        </>
      ) : (
        <button
          onClick={handleDelete}
          className="rounded p-1 text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-400"
          title="Delete meeting"
        >
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="h-4 w-4">
            <path fillRule="evenodd" d="M8.75 1A2.75 2.75 0 006 3.75v.443c-.795.077-1.584.176-2.365.298a.75.75 0 10.23 1.482l.149-.022.841 10.518A2.75 2.75 0 007.596 19h4.807a2.75 2.75 0 002.742-2.53l.841-10.519.149.023a.75.75 0 00.23-1.482A41.03 41.03 0 0014 4.193V3.75A2.75 2.75 0 0011.25 1h-2.5zM10 4c.84 0 1.673.025 2.5.075V3.75c0-.69-.56-1.25-1.25-1.25h-2.5c-.69 0-1.25.56-1.25 1.25v.325C8.327 4.025 9.16 4 10 4zM8.58 7.72a.75.75 0 00-1.5.06l.3 7.5a.75.75 0 101.5-.06l-.3-7.5zm4.34.06a.75.75 0 10-1.5-.06l-.3 7.5a.75.75 0 101.5.06l.3-7.5z" clipRule="evenodd" />
          </svg>
        </button>
      )}
    </div>
  );
}
