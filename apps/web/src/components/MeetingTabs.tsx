"use client";

import { useState } from "react";
import SummaryView from "./SummaryView";
import TranscriptView from "./TranscriptView";

interface Segment {
  id: string;
  speaker: string;
  text: string;
  startTime: number;
  endTime: number;
}

interface MeetingTabsProps {
  meetingId: string;
  summaryContent: string | null;
  segments: Segment[];
  rawMarkdown: string | null;
}

const TABS = ["Summary", "Transcript", "Raw Markdown"] as const;
type Tab = (typeof TABS)[number];

export default function MeetingTabs({
  meetingId,
  summaryContent,
  segments,
  rawMarkdown,
}: MeetingTabsProps) {
  const [activeTab, setActiveTab] = useState<Tab>("Summary");
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    if (!rawMarkdown) return;
    await navigator.clipboard.writeText(rawMarkdown);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div>
      {/* Notion-style tabs */}
      <div className="border-b border-gray-200 dark:border-gray-700">
        <nav className="-mb-px flex gap-1" aria-label="Tabs">
          {TABS.map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`whitespace-nowrap rounded-t-md px-3 py-2 text-sm font-medium transition-colors ${
                activeTab === tab
                  ? "border-b-2 border-gray-900 dark:border-gray-100 text-gray-900 dark:text-gray-100"
                  : "text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-300"
              }`}
            >
              {tab}
            </button>
          ))}
        </nav>
      </div>

      <div className="mt-6">
        {activeTab === "Summary" && (
          <SummaryView content={summaryContent} meetingId={meetingId} />
        )}
        {activeTab === "Transcript" && (
          <TranscriptView segments={segments} />
        )}
        {activeTab === "Raw Markdown" && (
          <div>
            <div className="mb-3 flex justify-end">
              <button
                onClick={handleCopy}
                className="inline-flex items-center gap-1.5 rounded-md border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3 py-1.5 text-xs font-medium text-gray-600 dark:text-gray-300 transition-colors hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none"
              >
                {copied ? (
                  <>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" className="h-3.5 w-3.5 text-emerald-500">
                      <path fillRule="evenodd" d="M12.416 3.376a.75.75 0 0 1 .208 1.04l-5 7.5a.75.75 0 0 1-1.154.114l-3-3a.75.75 0 0 1 1.06-1.06l2.353 2.353 4.493-6.74a.75.75 0 0 1 1.04-.207Z" clipRule="evenodd" />
                    </svg>
                    Copied
                  </>
                ) : (
                  <>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" className="h-3.5 w-3.5">
                      <path d="M5.5 3.5A1.5 1.5 0 0 1 7 2h2.879a1.5 1.5 0 0 1 1.06.44l2.122 2.12a1.5 1.5 0 0 1 .439 1.061V9.5A1.5 1.5 0 0 1 12 11V8.621a3 3 0 0 0-.879-2.121L9 4.379A3 3 0 0 0 6.879 3.5H5.5Z" />
                      <path d="M4 5a1.5 1.5 0 0 0-1.5 1.5v6A1.5 1.5 0 0 0 4 14h5a1.5 1.5 0 0 0 1.5-1.5V8.621a1.5 1.5 0 0 0-.44-1.06L7.94 5.439A1.5 1.5 0 0 0 6.878 5H4Z" />
                    </svg>
                    Copy
                  </>
                )}
              </button>
            </div>
            {rawMarkdown ? (
              <pre className="overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-800 bg-gray-50 dark:bg-gray-950 p-4 text-sm leading-relaxed text-gray-700 dark:text-gray-300 font-mono">
                {rawMarkdown}
              </pre>
            ) : (
              <p className="py-12 text-center text-sm text-gray-400 dark:text-gray-500">
                No raw markdown available.
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
