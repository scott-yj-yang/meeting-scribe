"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { apiBase } from "@/lib/api-base";

interface ClaudeHealthResponse {
  status: "ready" | "not-installed";
  claude: string;
  meetingctl: string;
  version?: string;
}

export default function ClaudeStatus() {
  const [data, setData] = useState<ClaudeHealthResponse | null>(null);
  const [open, setOpen] = useState(false);
  const popoverRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);

  const fetchStatus = useCallback(async () => {
    try {
      const res = await fetch(`${apiBase()}/api/health/claude`);
      if (res.ok) {
        const json = await res.json();
        setData(json);
      }
    } catch {
      setData({ status: "not-installed", claude: "not-found", meetingctl: "not-found" });
    }
  }, []);

  useEffect(() => {
    fetchStatus();
    const interval = setInterval(fetchStatus, 60_000);
    return () => clearInterval(interval);
  }, [fetchStatus]);

  // Close popover on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (
        popoverRef.current &&
        !popoverRef.current.contains(e.target as Node) &&
        buttonRef.current &&
        !buttonRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  const isReady = data?.status === "ready";

  return (
    <div className="relative">
      <button
        ref={buttonRef}
        onClick={() => setOpen((v) => !v)}
        title={isReady ? "Claude ready" : "Claude not installed"}
        className="flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm text-gray-500 dark:text-gray-400 transition-colors hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800"
        aria-expanded={open}
        aria-haspopup="true"
      >
        <span
          className={`inline-block h-2 w-2 rounded-full flex-shrink-0 ${
            data === null
              ? "bg-gray-300 dark:bg-gray-600"
              : isReady
              ? "bg-green-500"
              : "bg-red-500"
          }`}
        />
        <span className="hidden sm:inline text-xs">
          {data === null ? "Checking..." : isReady ? "Claude ready" : "Claude not installed"}
        </span>
      </button>

      {open && (
        <div
          ref={popoverRef}
          className="absolute right-0 top-full mt-1 z-50 w-64 rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 shadow-lg p-4"
          role="dialog"
          aria-label="Claude status details"
        >
          <div className="flex items-center gap-2 mb-3">
            <span
              className={`inline-block h-2.5 w-2.5 rounded-full flex-shrink-0 ${
                isReady ? "bg-green-500" : "bg-red-500"
              }`}
            />
            <span className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              {isReady ? "Claude Code ready" : "Claude Code not installed"}
            </span>
          </div>

          <div className="space-y-1.5 text-xs text-gray-600 dark:text-gray-400">
            <div className="flex justify-between">
              <span>claude</span>
              <span
                className={
                  data?.claude === "ready"
                    ? "text-green-600 dark:text-green-400"
                    : "text-red-500 dark:text-red-400"
                }
              >
                {data?.claude === "ready" ? "found" : "not found"}
              </span>
            </div>
            <div className="flex justify-between">
              <span>meetingctl</span>
              <span
                className={
                  data?.meetingctl === "ready"
                    ? "text-green-600 dark:text-green-400"
                    : "text-gray-400 dark:text-gray-500"
                }
              >
                {data?.meetingctl === "ready" ? "found" : "not found"}
              </span>
            </div>
            {data?.version && (
              <div className="flex justify-between">
                <span>version</span>
                <span className="text-gray-500 dark:text-gray-400 font-mono">
                  {data.version}
                </span>
              </div>
            )}
          </div>

          {!isReady && (
            <a
              href="https://docs.anthropic.com/en/docs/claude-code"
              target="_blank"
              rel="noopener noreferrer"
              className="mt-3 block text-center rounded-md bg-blue-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-700 transition-colors"
            >
              Install Claude Code
            </a>
          )}
        </div>
      )}
    </div>
  );
}
