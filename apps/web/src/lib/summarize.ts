import { execFile } from "child_process";

const jobs = new Map<string, { status: "running" | "completed" | "failed"; result?: string; error?: string }>();

export function getJobStatus(meetingId: string) {
  return jobs.get(meetingId) || null;
}

export function startSummarizeJob(meetingId: string): void {
  jobs.set(meetingId, { status: "running" });

  execFile("meetingctl", ["summarize", meetingId], { timeout: 300000 }, (error, stdout, stderr) => {
    if (error) {
      jobs.set(meetingId, { status: "failed", error: stderr || error.message });
    } else {
      jobs.set(meetingId, { status: "completed", result: stdout });
    }
  });
}
