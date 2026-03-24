#!/usr/bin/env npx tsx
import { Command } from "commander";
import { listCommand } from "../src/commands/list.js";
import { summarizeCommand } from "../src/commands/summarize.js";
import { chatCommand } from "../src/commands/chat.js";
import { exportCommand } from "../src/commands/export.js";

const program = new Command();
program.name("meetingctl").description("MeetingScribe CLI").version("0.1.0");

program.addCommand(listCommand);
program.addCommand(summarizeCommand);
program.addCommand(chatCommand);
program.addCommand(exportCommand);

program.parse();
