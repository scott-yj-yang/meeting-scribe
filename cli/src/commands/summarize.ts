import { Command } from "commander";
import chalk from "chalk";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { execFileSync } from "child_process";
import { join } from "path";
import { tmpdir } from "os";
import { APIClient } from "../api-client.js";
import { getConfig } from "../config.js";

async function summarizeMeeting(
  meetingId: string,
  promptName: string,
): Promise<void> {
  const client = new APIClient();
  const config = getConfig();

  // Fetch formatted markdown via the export endpoint
  const transcript = await client.exportMeeting(meetingId);

  if (!transcript) {
    console.log(chalk.yellow(`No transcript for meeting ${meetingId}, skipping.`));
    return;
  }

  // Read prompt template
  // Check templates/ subdirectory first, then root prompts/
  let promptPath = join(config.promptsDir, "templates", `${promptName}.md`);
  if (!existsSync(promptPath)) {
    promptPath = join(config.promptsDir, `${promptName}.md`);
  }
  let promptContent: string;
  try {
    promptContent = readFileSync(promptPath, "utf-8");
  } catch {
    console.error(
      chalk.red(`Prompt template not found: ${promptPath}`),
    );
    process.exit(1);
  }

  // Write transcript to a temp file
  const tmpFile = join(tmpdir(), `meetingscribe-${meetingId}.md`);
  writeFileSync(tmpFile, transcript, "utf-8");

  console.log(
    chalk.dim(`Summarizing meeting ${meetingId} with prompt "${promptName}"...`),
  );

  // Invoke claude CLI — embed the file path in the prompt so Claude reads it
  const fullPrompt = `${promptContent}\n\nThe meeting transcript file is located at: ${tmpFile}\nPlease read that file and produce the summary.`;

  try {
    execFileSync(
      "claude",
      ["--allowedTools", "Read", "-p", fullPrompt],
      { stdio: "inherit" },
    );
  } catch {
    console.error(chalk.red("Claude CLI exited with an error."));
    process.exit(1);
  }
}

export const summarizeCommand = new Command("summarize")
  .description("Summarize a meeting transcript using Claude")
  .argument("[meeting-id]", "meeting ID to summarize")
  .option("--all-pending", "summarize all meetings with pending summaries")
  .option("--prompt <name>", "prompt template name", "summarize")
  .action(async (meetingId: string | undefined, opts) => {
    const promptName: string = opts.prompt;

    try {
      if (opts.allPending) {
        const client = new APIClient();
        const data = await client.listMeetings(1, 100);
        const meetings: Array<{ id: string; status: string }> =
          data.meetings ?? data;

        const pending = meetings.filter(
          (m) => m.status === "pending" || m.status === "recorded",
        );

        if (!pending.length) {
          console.log(chalk.yellow("No pending meetings to summarize."));
          return;
        }

        console.log(
          chalk.blue(`Found ${pending.length} pending meeting(s). Summarizing...`),
        );

        for (const m of pending) {
          await summarizeMeeting(m.id, promptName);
          console.log();
        }
      } else if (meetingId) {
        await summarizeMeeting(meetingId, promptName);
      } else {
        console.error(
          chalk.red(
            "Provide a <meeting-id> or use --all-pending.",
          ),
        );
        process.exit(1);
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(chalk.red(`Error: ${message}`));
      process.exit(1);
    }
  });
