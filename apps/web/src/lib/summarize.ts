import { execFile } from "child_process";
import { join } from "path";
import { homedir } from "os";
import { prisma } from "@/lib/prisma";

interface Job {
  status: "running" | "completed" | "failed";
  result?: string;
  error?: string;
  startedAt: number;
}

const jobs = new Map<string, Job>();

// Shorten stale timeout to 2 minutes (meetingctl usually finishes in 30-60s)
const STALE_TIMEOUT_MS = 2 * 60 * 1000;

export function getJobStatus(meetingId: string) {
  const job = jobs.get(meetingId);
  if (!job) return null;

  // Auto-expire stale running jobs
  if (job.status === "running" && Date.now() - job.startedAt > STALE_TIMEOUT_MS) {
    console.log(`[Summarize] Job ${meetingId} expired after ${STALE_TIMEOUT_MS / 1000}s`);
    jobs.set(meetingId, {
      ...job,
      status: "failed",
      error: "Timed out. meetingctl may not be installed or Claude Code may not be available.",
    });
    return jobs.get(meetingId) || null;
  }

  return { ...job, elapsedSeconds: Math.floor((Date.now() - job.startedAt) / 1000) };
}

export function clearJobStatus(meetingId: string) {
  jobs.delete(meetingId);
}

export function forceCancel(meetingId: string) {
  const job = jobs.get(meetingId);
  if (job) {
    jobs.set(meetingId, { ...job, status: "failed", error: "Cancelled by user" });
  }
}

function findExecutable(name: string): string | null {
  const home = homedir();
  const searchPaths = [
    join(home, ".local/bin", name),
    join(home, ".nvm/versions/node", name),  // won't match but that's fine
    "/opt/homebrew/bin/" + name,
    "/usr/local/bin/" + name,
    "/usr/bin/" + name,
  ];

  const { execFileSync } = require("child_process");
  try {
    const result = execFileSync("which", [name], {
      env: { ...process.env, PATH: buildPath() },
      encoding: "utf-8",
      timeout: 3000,
    }).trim();
    if (result) return result;
  } catch {}

  return null;
}

function buildPath(): string {
  const home = homedir();
  const extra = [
    join(home, ".local/bin"),
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
  ];

  // Also look for nvm node versions
  const nvm = join(home, ".nvm/versions/node");
  try {
    const { readdirSync } = require("fs");
    const versions = readdirSync(nvm);
    if (versions.length > 0) {
      // Use the latest version
      const latest = versions.sort().pop();
      extra.unshift(join(nvm, latest, "bin"));
    }
  } catch {}

  return [...extra, process.env.PATH || ""].join(":");
}

export function startSummarizeJob(meetingId: string, customInstruction?: string, template?: string): void {
  jobs.set(meetingId, { status: "running", startedAt: Date.now() });

  const projectRoot = join(process.cwd(), "../..");
  const promptsDir = process.env.MEETINGSCRIBE_PROMPTS_DIR || join(projectRoot, "prompts");
  const fullPath = buildPath();

  // Check if meetingctl exists
  const meetingctlPath = findExecutable("meetingctl");
  if (!meetingctlPath) {
    console.error("[Summarize] meetingctl not found in PATH");
    jobs.set(meetingId, {
      status: "failed",
      error: "meetingctl CLI not found. Run: cd cli && npm link",
      startedAt: Date.now(),
    });
    return;
  }

  // Check if claude exists
  const claudePath = findExecutable("claude");
  if (!claudePath) {
    console.error("[Summarize] claude not found in PATH");
    jobs.set(meetingId, {
      status: "failed",
      error: "Claude Code CLI not installed. Visit: https://claude.ai/download",
      startedAt: Date.now(),
    });
    return;
  }

  console.log(`[Summarize] Starting job for ${meetingId}`);
  console.log(`[Summarize]   meetingctl: ${meetingctlPath}`);
  console.log(`[Summarize]   claude: ${claudePath}`);
  console.log(`[Summarize]   prompts: ${promptsDir}`);

  const args = ["summarize", meetingId];
  if (template && template !== "default") {
    args.push("--prompt", template);
  }
  if (customInstruction) {
    args.push("--instruction", customInstruction);
  }

  const child = execFile(
    meetingctlPath,
    args,
    {
      timeout: 300000,
      cwd: projectRoot,
      env: {
        ...process.env,
        PATH: fullPath,
        HOME: homedir(),
        MEETINGSCRIBE_PROMPTS_DIR: promptsDir,
      },
    },
    async (error, stdout, stderr) => {
      if (error) {
        const errMsg = stderr || error.message || "Unknown error";
        console.error(`[Summarize] Job ${meetingId} failed:`, errMsg);
        jobs.set(meetingId, {
          status: "failed",
          error: errMsg,
          startedAt: jobs.get(meetingId)?.startedAt || Date.now(),
        });
      } else {
        try {
          const summaryContent = stdout
            .replace(/^Summarizing meeting.*\n/, "")
            .trim();

          if (!summaryContent) {
            jobs.set(meetingId, {
              status: "failed",
              error: "Claude returned empty output",
              startedAt: jobs.get(meetingId)?.startedAt || Date.now(),
            });
            return;
          }

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

          console.log(`[Summarize] Job ${meetingId} completed (${summaryContent.length} chars)`);
          jobs.set(meetingId, { status: "completed", result: summaryContent, startedAt: jobs.get(meetingId)?.startedAt || Date.now() });
        } catch (dbError) {
          const errMsg = dbError instanceof Error ? dbError.message : String(dbError);
          console.error(`[Summarize] DB save failed:`, errMsg);
          jobs.set(meetingId, {
            status: "failed",
            error: `Summary generated but failed to save: ${errMsg}`,
            startedAt: jobs.get(meetingId)?.startedAt || Date.now(),
          });
        }
      }
    }
  );

  // Log if the child process itself fails to spawn
  child.on("error", (err) => {
    console.error(`[Summarize] Spawn error:`, err.message);
    jobs.set(meetingId, {
      status: "failed",
      error: `Failed to start: ${err.message}`,
      startedAt: Date.now(),
    });
  });
}
