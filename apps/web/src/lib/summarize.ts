import { execFile } from "child_process";
import { join } from "path";
import { prisma } from "@/lib/prisma";

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
              promptUsed: "summarize",
            },
            update: {
              content: summaryContent,
              promptUsed: "summarize",
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
