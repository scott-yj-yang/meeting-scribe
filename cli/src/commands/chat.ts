import { Command } from "commander";
import chalk from "chalk";
import { writeFileSync } from "fs";
import { execFileSync } from "child_process";
import { join } from "path";
import { tmpdir } from "os";
import { APIClient } from "../api-client.js";

export const chatCommand = new Command("chat")
  .description("Start an interactive chat session about a meeting")
  .argument("<meeting-id>", "meeting ID to chat about")
  .action(async (meetingId: string) => {
    const client = new APIClient();

    try {
      const meeting = await client.getMeeting(meetingId);
      const transcript: string = meeting.transcript ?? "";

      if (!transcript) {
        console.error(
          chalk.red(`No transcript found for meeting ${meetingId}.`),
        );
        process.exit(1);
      }

      // Write transcript to a temp file
      const tmpFile = join(tmpdir(), `meetingscribe-chat-${meetingId}.md`);
      writeFileSync(tmpFile, transcript, "utf-8");

      const contextPrompt = [
        `You are a helpful assistant for discussing a meeting transcript.`,
        `The transcript is available at: ${tmpFile}`,
        `Read the transcript first, then answer the user's questions about the meeting.`,
        `Be concise and reference specific parts of the transcript when possible.`,
      ].join("\n");

      console.log(
        chalk.blue(`Starting chat session for meeting ${meetingId}...`),
      );
      console.log(chalk.dim("(Use Ctrl+C to exit)\n"));

      execFileSync(
        "claude",
        ["--allowedTools", "Read,Grep", "-p", contextPrompt],
        { stdio: "inherit" },
      );
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(chalk.red(`Error: ${message}`));
      process.exit(1);
    }
  });
