export default function SettingsPage() {
  return (
    <div>
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900">Settings</h1>
        <p className="mt-1 text-sm text-gray-500">
          Configuration and reference for MeetingScribe.
        </p>
      </div>

      <div className="space-y-6">
        {/* Prompt Templates */}
        <div className="bg-white rounded-lg border border-gray-200 p-4 shadow-sm">
          <h2 className="text-base font-semibold text-gray-900 mb-2">
            Prompt Templates
          </h2>
          <p className="text-sm text-gray-600 mb-3">
            MeetingScribe uses Markdown prompt templates to generate meeting
            summaries. By default, templates are loaded from the{" "}
            <code className="rounded bg-gray-100 px-1 py-0.5 text-xs font-mono text-gray-800">
              prompts/
            </code>{" "}
            directory at the root of the repository.
          </p>
          <p className="text-sm text-gray-600">
            To use a custom prompts directory, set the{" "}
            <code className="rounded bg-gray-100 px-1 py-0.5 text-xs font-mono text-gray-800">
              MEETINGSCRIBE_PROMPTS_DIR
            </code>{" "}
            environment variable to the absolute path of your templates folder.
            Each{" "}
            <code className="rounded bg-gray-100 px-1 py-0.5 text-xs font-mono text-gray-800">
              .md
            </code>{" "}
            file in that directory becomes an available prompt template.
          </p>
        </div>

        {/* CLI Commands */}
        <div className="bg-white rounded-lg border border-gray-200 p-4 shadow-sm">
          <h2 className="text-base font-semibold text-gray-900 mb-2">
            CLI Commands
          </h2>
          <p className="text-sm text-gray-600 mb-4">
            Use{" "}
            <code className="rounded bg-gray-100 px-1 py-0.5 text-xs font-mono text-gray-800">
              meetingctl
            </code>{" "}
            to manage meetings from the terminal.
          </p>
          <div className="space-y-3">
            <div>
              <code className="block rounded bg-gray-100 px-3 py-2 text-xs font-mono text-gray-800">
                meetingctl list
              </code>
              <p className="mt-1 text-sm text-gray-600">
                List all recorded meetings with their IDs, titles, and dates.
              </p>
            </div>
            <div>
              <code className="block rounded bg-gray-100 px-3 py-2 text-xs font-mono text-gray-800">
                meetingctl summarize &lt;id&gt;
              </code>
              <p className="mt-1 text-sm text-gray-600">
                Generate or regenerate an AI summary for the specified meeting.
              </p>
            </div>
            <div>
              <code className="block rounded bg-gray-100 px-3 py-2 text-xs font-mono text-gray-800">
                meetingctl chat &lt;id&gt;
              </code>
              <p className="mt-1 text-sm text-gray-600">
                Start an interactive chat session about the specified meeting.
              </p>
            </div>
            <div>
              <code className="block rounded bg-gray-100 px-3 py-2 text-xs font-mono text-gray-800">
                meetingctl export &lt;id&gt;
              </code>
              <p className="mt-1 text-sm text-gray-600">
                Export the meeting transcript and summary as a Markdown file.
              </p>
            </div>
          </div>
        </div>

        {/* API Authentication */}
        <div className="bg-white rounded-lg border border-gray-200 p-4 shadow-sm">
          <h2 className="text-base font-semibold text-gray-900 mb-2">
            API Authentication
          </h2>
          <p className="text-sm text-gray-600 mb-3">
            The MeetingScribe API requires a secret key for authentication. Set
            the{" "}
            <code className="rounded bg-gray-100 px-1 py-0.5 text-xs font-mono text-gray-800">
              MEETINGSCRIBE_API_KEY
            </code>{" "}
            environment variable on both the server and any CLI or native
            clients that connect to it.
          </p>
          <p className="text-sm text-gray-600">
            All requests to protected API endpoints must include the header{" "}
            <code className="rounded bg-gray-100 px-1 py-0.5 text-xs font-mono text-gray-800">
              Authorization: Bearer &lt;your-key&gt;
            </code>
            . Requests without a valid key will receive a{" "}
            <code className="rounded bg-gray-100 px-1 py-0.5 text-xs font-mono text-gray-800">
              401 Unauthorized
            </code>{" "}
            response.
          </p>
        </div>
      </div>
    </div>
  );
}
