import { homedir } from "os";
import { join } from "path";

export function getConfig() {
  return {
    apiUrl: process.env.MEETINGSCRIBE_API_URL || "http://localhost:3000",
    apiKey: process.env.MEETINGSCRIBE_API_KEY || "",
    promptsDir:
      process.env.MEETINGSCRIBE_PROMPTS_DIR ||
      join(process.cwd(), "prompts"),
    outputDir:
      process.env.MEETINGSCRIBE_OUTPUT_DIR || join(homedir(), "MeetingScribe"),
  };
}
