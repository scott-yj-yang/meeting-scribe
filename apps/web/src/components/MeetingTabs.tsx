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
      <div className="border-b border-gray-200 dark:border-gray-700">
        <nav className="-mb-px flex gap-6" aria-label="Tabs">
          {TABS.map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`whitespace-nowrap border-b-2 px-1 py-3 text-sm font-medium transition-colors ${
                activeTab === tab
                  ? "border-blue-600 text-blue-600"
                  : "border-transparent text-gray-500 dark:text-gray-400 hover:border-gray-300 dark:hover:border-gray-600 hover:text-gray-700 dark:hover:text-gray-200"
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
                className="inline-flex items-center rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm font-medium text-gray-700 dark:text-gray-200 shadow-sm hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
              >
                {copied ? "Copied!" : "Copy"}
              </button>
            </div>
            {rawMarkdown ? (
              <pre className="overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-950 p-4 text-sm text-gray-800 dark:text-gray-200">
                {rawMarkdown}
              </pre>
            ) : (
              <p className="py-8 text-center text-sm text-gray-500 dark:text-gray-400">
                No raw markdown available.
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
