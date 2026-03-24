import { execFile } from "child_process";
import { join } from "path";

const jobs = new Map<string, { status: "running" | "completed" | "failed"; result?: string; error?: string }>();

export function getJobStatus(meetingId: string) {
  return jobs.get(meetingId) || null;
}

export function startSummarizeJob(meetingId: string): void {
  jobs.set(meetingId, { status: "running" });

  // The web app runs from apps/web/, so the project root is ../../
  const projectRoot = join(process.cwd(), "../..");
  const promptsDir = process.env.MEETINGSCRIBE_PROMPTS_DIR || join(projectRoot, "prompts");

  execFile(
    "meetingctl",
    ["summarize", meetingId],
    {
      timeout: 300000,
      cwd: projectRoot,
      env: { ...process.env, MEETINGSCRIBE_PROMPTS_DIR: promptsDir },
    },
    (error, stdout, stderr) => {
      if (error) {
        jobs.set(meetingId, { status: "failed", error: stderr || error.message });
      } else {
        jobs.set(meetingId, { status: "completed", result: stdout });
      }
    }
  );
}
