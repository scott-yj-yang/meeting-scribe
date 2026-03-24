import { Command } from "commander";
import chalk from "chalk";
import { APIClient } from "../api-client.js";

export const listCommand = new Command("list")
  .description("List recent meetings")
  .option("-l, --limit <number>", "number of meetings to show", "10")
  .action(async (opts) => {
    const client = new APIClient();
    const limit = parseInt(opts.limit, 10);

    try {
      const data = await client.listMeetings(1, limit);
      const meetings: Array<{
        id: string;
        date: string;
        duration: number | null;
        status: string;
        title: string;
      }> = data.meetings ?? data;

      if (!meetings.length) {
        console.log(chalk.yellow("No meetings found."));
        return;
      }

      // Table header
      console.log(
        chalk.bold(
          `${"ID".padEnd(10)} ${"Date".padEnd(12)} ${"Duration".padEnd(10)} ${"Status".padEnd(12)} Title`,
        ),
      );
      console.log("-".repeat(72));

      for (const m of meetings) {
        const shortId = m.id.slice(0, 8);
        const date = new Date(m.date).toLocaleDateString();
        const duration = m.duration ? `${m.duration}m` : "—";
        const statusColor =
          m.status === "completed" ? chalk.green : chalk.yellow;

        console.log(
          `${shortId.padEnd(10)} ${date.padEnd(12)} ${duration.padEnd(10)} ${statusColor(m.status.padEnd(12))} ${m.title}`,
        );
      }

      console.log();
      console.log(chalk.dim(`Showing ${meetings.length} meeting(s).`));
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(chalk.red(`Error: ${message}`));
      process.exit(1);
    }
  });
