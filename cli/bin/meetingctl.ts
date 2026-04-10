#!/usr/bin/env npx tsx
import { Command } from "commander";
import { listCommand } from "../src/commands/list.js";

const program = new Command();
program.name("meetingctl").description("MeetingScribe CLI").version("0.1.0");

program.addCommand(listCommand);

program.parse();
