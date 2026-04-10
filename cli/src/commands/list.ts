import { Command } from "commander";
import chalk from "chalk";
import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";

interface MeetingMeta {
  id: string;
  title: string;
  // Stored either as an ISO-8601 string (web-era) or as a Swift
  // `Date.timeIntervalSinceReferenceDate` number (native Swift app).
  date: string | number;
  duration: number;
  meetingType?: string;
}

// Unix seconds offset of Swift's reference date (2001-01-01 UTC).
const SWIFT_REFERENCE_EPOCH_OFFSET = 978307200;

function toDate(value: string | number | undefined): Date | null {
  if (value === undefined || value === null) return null;
  const parsed =
    typeof value === "number"
      ? new Date((value + SWIFT_REFERENCE_EPOCH_OFFSET) * 1000)
      : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

async function walkMeetings(baseDir: string): Promise<MeetingMeta[]> {
  const found: MeetingMeta[] = [];
  let years: string[] = [];
  try {
    years = await fs.readdir(baseDir);
  } catch {
    return [];
  }
  for (const year of years) {
    const yearPath = path.join(baseDir, year);
    let months: string[] = [];
    try {
      months = await fs.readdir(yearPath);
    } catch {
      continue;
    }
    for (const month of months) {
      const monthPath = path.join(yearPath, month);
      let meetings: string[] = [];
      try {
        meetings = await fs.readdir(monthPath);
      } catch {
        continue;
      }
      for (const m of meetings) {
        const metaPath = path.join(monthPath, m, "metadata.json");
        try {
          const content = await fs.readFile(metaPath, "utf-8");
          const meta = JSON.parse(content) as MeetingMeta;
          found.push(meta);
        } catch {
          continue;
        }
      }
    }
  }
  return found.sort((a, b) => {
    const aTime = toDate(a.date)?.getTime() ?? 0;
    const bTime = toDate(b.date)?.getTime() ?? 0;
    return bTime - aTime;
  });
}

export const listCommand = new Command("list")
  .description("List recent meetings from ~/MeetingScribe")
  .option("-l, --limit <number>", "number of meetings to show", "10")
  .option("-d, --dir <path>", "meeting directory", path.join(os.homedir(), "MeetingScribe"))
  .action(async (opts) => {
    const limit = parseInt(opts.limit, 10);
    const meetings = (await walkMeetings(opts.dir)).slice(0, limit);

    if (!meetings.length) {
      console.log(chalk.yellow(`No meetings found in ${opts.dir}.`));
      return;
    }

    console.log(
      chalk.bold(
        `${"ID".padEnd(10)} ${"Date".padEnd(12)} ${"Duration".padEnd(10)} ${"Type".padEnd(12)} Title`,
      ),
    );
    console.log("-".repeat(72));

    for (const m of meetings) {
      const shortId = m.id.slice(0, 8);
      const parsedDate = toDate(m.date);
      const date = parsedDate ? parsedDate.toLocaleDateString() : "—";
      const dur = m.duration ? `${Math.floor(m.duration / 60)}m` : "—";
      const type = m.meetingType ?? "—";

      console.log(
        `${shortId.padEnd(10)} ${date.padEnd(12)} ${dur.padEnd(10)} ${chalk.cyan(type.padEnd(12))} ${m.title}`,
      );
    }

    console.log();
    console.log(chalk.dim(`Showing ${meetings.length} meeting(s) from ${opts.dir}.`));
  });
