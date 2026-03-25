import { execFile } from "child_process";
import { join } from "path";
import { prisma } from "@/lib/prisma";

const jobs = new Map<string, { status: "running" | "completed" | "failed"; result?: string; error?: string; startedAt: number }>();

export function getJobStatus(meetingId: string) {
  const job = jobs.get(meetingId);
  if (!job) return null;

  // Expire stale running jobs after 5 minutes
  if (job.status === "running" && Date.now() - job.startedAt > 5 * 60 * 1000) {
    jobs.set(meetingId, { ...job, status: "failed", error: "Timed out after 5 minutes" });
    return jobs.get(meetingId) || null;
  }

  return job;
}

export function clearJobStatus(meetingId: string) {
  jobs.delete(meetingId);
}

export function startSummarizeJob(meetingId: string, customInstruction?: string): void {
  jobs.set(meetingId, { status: "running", startedAt: Date.now() });

  // The web app runs from apps/web/, so the project root is ../../
  const projectRoot = join(process.cwd(), "../..");
  const promptsDir = process.env.MEETINGSCRIBE_PROMPTS_DIR || join(projectRoot, "prompts");

  const args = ["summarize", meetingId];
  if (customInstruction) {
    args.push("--instruction", customInstruction);
  }

  execFile(
    "meetingctl",
    args,
    {
      timeout: 300000,
      cwd: projectRoot,
      env: { ...process.env, MEETINGSCRIBE_PROMPTS_DIR: promptsDir },
    },
    async (error, stdout, stderr) => {
      if (error) {
        jobs.set(meetingId, { status: "failed", error: stderr || error.message });
      } else {
        // Save summary to database
        try {
          // Strip the "Summarizing meeting..." prefix line from meetingctl output
          const summaryContent = stdout
            .replace(/^Summarizing meeting.*\n/, "")
            .trim();

          await prisma.summary.upsert({
            where: { meetingId },
            create: {
              meetingId,
              content: summaryContent,
              promptUsed: customInstruction ? `summarize (custom: ${customInstruction})` : "summarize",
            },
            update: {
              content: summaryContent,
              promptUsed: customInstruction ? `summarize (custom: ${customInstruction})` : "summarize",
              generatedAt: new Date(),
            },
          });

          jobs.set(meetingId, { status: "completed", result: summaryContent });
        } catch (dbError) {
          const errMsg = dbError instanceof Error ? dbError.message : String(dbError);
          jobs.set(meetingId, { status: "failed", error: `Summary generated but failed to save: ${errMsg}` });
        }
      }
    }
  );
}
