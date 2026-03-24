import { Command } from "commander";
import chalk from "chalk";
import { writeFileSync, mkdirSync } from "fs";
import { dirname, join } from "path";
import { APIClient } from "../api-client.js";
import { getConfig } from "../config.js";

export const exportCommand = new Command("export")
  .description("Export a meeting to markdown")
  .argument("<meeting-id>", "meeting ID to export")
  .option("-o, --output <path>", "output file path")
  .action(async (meetingId: string, opts) => {
    const client = new APIClient();
    const config = getConfig();

    try {
      const markdown = await client.exportMeeting(meetingId);

      const outputPath =
        opts.output || join(config.outputDir, `${meetingId}.md`);

      mkdirSync(dirname(outputPath), { recursive: true });
      writeFileSync(outputPath, markdown, "utf-8");

      console.log(chalk.green(`Exported to ${outputPath}`));
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(chalk.red(`Error: ${message}`));
      process.exit(1);
    }
  });
