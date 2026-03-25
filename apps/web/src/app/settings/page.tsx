"use client";

import { useEffect, useState } from "react";

const AUTO_SUMMARIZE_KEY = "meetingscribe_auto_summarize";

export default function SettingsPage() {
  const [autoSummarize, setAutoSummarize] = useState(false);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setAutoSummarize(localStorage.getItem(AUTO_SUMMARIZE_KEY) === "true");
    setMounted(true);
  }, []);

  function handleToggle() {
    const next = !autoSummarize;
    setAutoSummarize(next);
    localStorage.setItem(AUTO_SUMMARIZE_KEY, String(next));
  }

  return (
    <div className="page-transition">
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Settings</h1>
        <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
          Configuration and reference for MeetingScribe.
        </p>
      </div>

      <div className="space-y-6">
        {/* Auto-summarize Toggle */}
        <div className="bg-white dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700 p-4 shadow-sm">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                Auto-summarize
              </h2>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-300">
                Automatically summarize meetings after upload when no summary exists.
              </p>
            </div>
            {mounted && (
              <button
                type="button"
                role="switch"
                aria-checked={autoSummarize}
                onClick={handleToggle}
                className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900 ${
                  autoSummarize ? "bg-blue-600" : "bg-gray-200 dark:bg-gray-700"
                }`}
              >
                <span
                  className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow ring-0 transition-transform duration-200 ease-in-out ${
                    autoSummarize ? "translate-x-5" : "translate-x-0"
                  }`}
                />
              </button>
            )}
          </div>
        </div>

        {/* Prompt Templates */}
        <div className="bg-white dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700 p-4 shadow-sm">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100 mb-2">
            Prompt Templates
          </h2>
          <p className="text-sm text-gray-600 dark:text-gray-300 mb-3">
            MeetingScribe uses Markdown prompt templates to generate meeting
            summaries. By default, templates are loaded from the{" "}
            <code className="rounded bg-gray-100 dark:bg-gray-800 px-1 py-0.5 text-xs font-mono text-gray-800 dark:text-gray-200">
              prompts/
            </code>{" "}
            directory at the root of the repository.
          </p>
          <p className="text-sm text-gray-600 dark:text-gray-300">
            To use a custom prompts directory, set the{" "}
            <code className="rounded bg-gray-100 dark:bg-gray-800 px-1 py-0.5 text-xs font-mono text-gray-800 dark:text-gray-200">
              MEETINGSCRIBE_PROMPTS_DIR
            </code>{" "}
            environment variable to the absolute path of your templates folder.
            Each{" "}
            <code className="rounded bg-gray-100 dark:bg-gray-800 px-1 py-0.5 text-xs font-mono text-gray-800 dark:text-gray-200">
              .md
            </code>{" "}
            file in that directory becomes an available prompt template.
          </p>
        </div>

        {/* CLI Commands */}
        <div className="bg-white dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700 p-4 shadow-sm">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100 mb-2">
            CLI Commands
          </h2>
          <p className="text-sm text-gray-600 dark:text-gray-300 mb-4">
            Use{" "}
            <code className="rounded bg-gray-100 dark:bg-gray-800 px-1 py-0.5 text-xs font-mono text-gray-800 dark:text-gray-200">
              meetingctl
            </code>{" "}
            to manage meetings from the terminal.
          </p>
          <div className="space-y-3">
            <div>
              <code className="block rounded bg-gray-100 dark:bg-gray-800 px-3 py-2 text-xs font-mono text-gray-800 dark:text-gray-200">
                meetingctl list
              </code>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-300">
                List all recorded meetings with their IDs, titles, and dates.
              </p>
            </div>
            <div>
              <code className="block rounded bg-gray-100 dark:bg-gray-800 px-3 py-2 text-xs font-mono text-gray-800 dark:text-gray-200">
                meetingctl summarize &lt;id&gt;
              </code>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-300">
                Generate or regenerate an AI summary for the specified meeting.
              </p>
            </div>
            <div>
              <code className="block rounded bg-gray-100 dark:bg-gray-800 px-3 py-2 text-xs font-mono text-gray-800 dark:text-gray-200">
                meetingctl chat &lt;id&gt;
              </code>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-300">
                Start an interactive chat session about the specified meeting.
              </p>
            </div>
            <div>
              <code className="block rounded bg-gray-100 dark:bg-gray-800 px-3 py-2 text-xs font-mono text-gray-800 dark:text-gray-200">
                meetingctl export &lt;id&gt;
              </code>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-300">
                Export the meeting transcript and summary as a Markdown file.
              </p>
            </div>
          </div>
        </div>

        {/* API Authentication */}
        <div className="bg-white dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700 p-4 shadow-sm">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100 mb-2">
            API Authentication
          </h2>
          <p className="text-sm text-gray-600 dark:text-gray-300 mb-3">
            The MeetingScribe API requires a secret key for authentication. Set
            the{" "}
            <code className="rounded bg-gray-100 dark:bg-gray-800 px-1 py-0.5 text-xs font-mono text-gray-800 dark:text-gray-200">
              MEETINGSCRIBE_API_KEY
            </code>{" "}
            environment variable on both the server and any CLI or native
            clients that connect to it.
          </p>
          <p className="text-sm text-gray-600 dark:text-gray-300">
            All requests to protected API endpoints must include the header{" "}
            <code className="rounded bg-gray-100 dark:bg-gray-800 px-1 py-0.5 text-xs font-mono text-gray-800 dark:text-gray-200">
              Authorization: Bearer &lt;your-key&gt;
            </code>
            . Requests without a valid key will receive a{" "}
            <code className="rounded bg-gray-100 dark:bg-gray-800 px-1 py-0.5 text-xs font-mono text-gray-800 dark:text-gray-200">
              401 Unauthorized
            </code>{" "}
            response.
          </p>
        </div>
      </div>
    </div>
  );
}
