"use client";

import { useEffect, useState, useCallback } from "react";

const AUTO_SUMMARIZE_KEY = "meetingscribe_auto_summarize";

export default function SettingsPage() {
  const [autoSummarize, setAutoSummarize] = useState(false);
  const [mounted, setMounted] = useState(false);

  // Notion state
  const [notionConfigured, setNotionConfigured] = useState(false);
  const [notionDbName, setNotionDbName] = useState("");
  const [notionMaskedKey, setNotionMaskedKey] = useState("");
  const [notionDbId, setNotionDbId] = useState("");
  const [showNotionSetup, setShowNotionSetup] = useState(false);
  const [notionApiKey, setNotionApiKey] = useState("");
  const [notionDatabaseInput, setNotionDatabaseInput] = useState("");
  const [notionSaving, setNotionSaving] = useState(false);
  const [notionError, setNotionError] = useState("");
  const [notionStep, setNotionStep] = useState(1);

  const loadNotionConfig = useCallback(() => {
    fetch("/api/settings/notion")
      .then((r) => r.json())
      .then((data) => {
        setNotionConfigured(data.configured);
        setNotionMaskedKey(data.apiKey);
        setNotionDbName(data.databaseName);
        setNotionDbId(data.databaseId);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    setAutoSummarize(localStorage.getItem(AUTO_SUMMARIZE_KEY) === "true");
    setMounted(true);
    loadNotionConfig();
  }, [loadNotionConfig]);

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

        {/* Notion Integration */}
        <div className="bg-white dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700 p-4 shadow-sm">
          <div className="flex items-center justify-between mb-3">
            <div>
              <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                Notion Integration
              </h2>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-300">
                Sync meeting summaries to a Notion database.
              </p>
            </div>
            {notionConfigured && (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-green-50 px-2.5 py-1 text-xs font-medium text-green-700 dark:bg-green-900/30 dark:text-green-400">
                <span className="h-1.5 w-1.5 rounded-full bg-green-500" />
                Connected
              </span>
            )}
          </div>

          {notionConfigured && !showNotionSetup ? (
            <div className="space-y-3">
              <div className="rounded-lg bg-gray-50 dark:bg-gray-800 p-3 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs text-gray-500 dark:text-gray-400">Database</span>
                  <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{notionDbName || "Connected"}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-gray-500 dark:text-gray-400">API Key</span>
                  <code className="text-xs text-gray-600 dark:text-gray-400 font-mono">{notionMaskedKey}</code>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-gray-500 dark:text-gray-400">Database ID</span>
                  <code className="text-xs text-gray-600 dark:text-gray-400 font-mono">{notionDbId.slice(0, 12)}...</code>
                </div>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => { setShowNotionSetup(true); setNotionStep(1); }}
                  className="text-xs text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300"
                >
                  Reconfigure
                </button>
                <button
                  onClick={async () => {
                    await fetch("/api/settings/notion", { method: "DELETE" });
                    setNotionConfigured(false);
                    setNotionDbName("");
                    setNotionMaskedKey("");
                  }}
                  className="text-xs text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300"
                >
                  Disconnect
                </button>
              </div>
            </div>
          ) : showNotionSetup || !notionConfigured ? (
            <div className="space-y-4">
              {/* Step indicator */}
              <div className="flex items-center gap-2">
                {[1, 2, 3].map((s) => (
                  <div key={s} className="flex items-center gap-2">
                    <div className={`flex h-6 w-6 items-center justify-center rounded-full text-xs font-medium ${
                      notionStep > s ? "bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-400"
                      : notionStep === s ? "bg-blue-100 text-blue-700 dark:bg-blue-900/50 dark:text-blue-400"
                      : "bg-gray-100 text-gray-400 dark:bg-gray-800 dark:text-gray-500"
                    }`}>
                      {notionStep > s ? "✓" : s}
                    </div>
                    {s < 3 && <div className="h-px w-8 bg-gray-200 dark:bg-gray-700" />}
                  </div>
                ))}
              </div>

              {notionStep === 1 && (
                <div className="space-y-3">
                  <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">Step 1: Create a Notion Integration</h3>
                  <ol className="list-decimal list-inside space-y-2 text-sm text-gray-600 dark:text-gray-300">
                    <li>
                      Go to{" "}
                      <a href="https://www.notion.so/profile/integrations" target="_blank" rel="noopener noreferrer"
                        className="text-blue-600 hover:underline dark:text-blue-400">
                        notion.so/profile/integrations
                      </a>
                    </li>
                    <li>Click <strong>&quot;New integration&quot;</strong></li>
                    <li>Name it <strong>&quot;MeetingScribe&quot;</strong></li>
                    <li>Select your workspace and click <strong>&quot;Save&quot;</strong></li>
                    <li>Copy the <strong>Internal Integration Secret</strong> (starts with <code className="rounded bg-gray-100 dark:bg-gray-800 px-1 text-xs">ntn_</code>)</li>
                  </ol>
                  <button onClick={() => setNotionStep(2)}
                    className="rounded-md bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700">
                    I have my API key →
                  </button>
                </div>
              )}

              {notionStep === 2 && (
                <div className="space-y-3">
                  <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">Step 2: Create a Meeting Database</h3>
                  <ol className="list-decimal list-inside space-y-2 text-sm text-gray-600 dark:text-gray-300">
                    <li>In Notion, create a new <strong>full-page database</strong></li>
                    <li>Add these properties: <strong>Date</strong> (date), <strong>Duration</strong> (number), <strong>Type</strong> (select), <strong>Status</strong> (status)</li>
                    <li>Click the <strong>···</strong> menu → <strong>Connections</strong> → add your <strong>&quot;MeetingScribe&quot;</strong> integration</li>
                    <li>Copy the <strong>database URL</strong> from your browser (or the Share link)</li>
                  </ol>
                  <button onClick={() => setNotionStep(3)}
                    className="rounded-md bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700">
                    Database is ready →
                  </button>
                  <button onClick={() => setNotionStep(1)}
                    className="ml-2 text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400">
                    ← Back
                  </button>
                </div>
              )}

              {notionStep === 3 && (
                <div className="space-y-3">
                  <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">Step 3: Connect</h3>
                  <div>
                    <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">Integration API Key</label>
                    <input
                      type="password"
                      value={notionApiKey}
                      onChange={(e) => setNotionApiKey(e.target.value)}
                      placeholder="ntn_..."
                      className="w-full rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">Database URL or ID</label>
                    <input
                      type="text"
                      value={notionDatabaseInput}
                      onChange={(e) => setNotionDatabaseInput(e.target.value)}
                      placeholder="https://www.notion.so/your-database-id?v=... or paste the ID"
                      className="w-full rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
                    />
                    <p className="mt-1 text-xs text-gray-400">You can paste the full Notion URL — we&apos;ll extract the database ID automatically.</p>
                  </div>

                  {notionError && (
                    <div className="rounded-md bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-3">
                      <p className="text-sm text-red-700 dark:text-red-400">{notionError}</p>
                    </div>
                  )}

                  <div className="flex items-center gap-2">
                    <button
                      onClick={async () => {
                        setNotionSaving(true);
                        setNotionError("");
                        try {
                          const res = await fetch("/api/settings/notion", {
                            method: "POST",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({ apiKey: notionApiKey, databaseId: notionDatabaseInput }),
                          });
                          const data = await res.json();
                          if (!res.ok) {
                            setNotionError(data.error || "Failed to connect");
                          } else {
                            setShowNotionSetup(false);
                            setNotionApiKey("");
                            setNotionDatabaseInput("");
                            loadNotionConfig();
                          }
                        } catch {
                          setNotionError("Network error");
                        }
                        setNotionSaving(false);
                      }}
                      disabled={notionSaving || !notionApiKey || !notionDatabaseInput}
                      className="rounded-md bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700 disabled:opacity-50"
                    >
                      {notionSaving ? "Connecting..." : "Connect to Notion"}
                    </button>
                    <button onClick={() => { setShowNotionSetup(false); setNotionStep(1); setNotionError(""); }}
                      className="text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400">
                      Cancel
                    </button>
                    <button onClick={() => setNotionStep(2)}
                      className="text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400">
                      ← Back
                    </button>
                  </div>
                </div>
              )}
            </div>
          ) : null}
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
