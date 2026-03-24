import { describe, it, expect, afterEach } from "vitest";
import { homedir } from "os";
import { join } from "path";
import { getConfig } from "../src/config.js";

describe("getConfig", () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    // Restore original env
    process.env = { ...originalEnv };
  });

  it("returns defaults when no env vars are set", () => {
    delete process.env.MEETINGSCRIBE_API_URL;
    delete process.env.MEETINGSCRIBE_API_KEY;
    delete process.env.MEETINGSCRIBE_PROMPTS_DIR;
    delete process.env.MEETINGSCRIBE_OUTPUT_DIR;

    const config = getConfig();

    expect(config.apiUrl).toBe("http://localhost:3000");
    expect(config.apiKey).toBe("");
    expect(config.promptsDir).toBe(join(process.cwd(), "prompts"));
    expect(config.outputDir).toBe(join(homedir(), "MeetingScribe"));
  });

  it("reads env vars when set", () => {
    process.env.MEETINGSCRIBE_API_URL = "https://api.example.com";
    process.env.MEETINGSCRIBE_API_KEY = "test-key-123";
    process.env.MEETINGSCRIBE_PROMPTS_DIR = "/custom/prompts";
    process.env.MEETINGSCRIBE_OUTPUT_DIR = "/custom/output";

    const config = getConfig();

    expect(config.apiUrl).toBe("https://api.example.com");
    expect(config.apiKey).toBe("test-key-123");
    expect(config.promptsDir).toBe("/custom/prompts");
    expect(config.outputDir).toBe("/custom/output");
  });

  it("allows partial env var overrides", () => {
    delete process.env.MEETINGSCRIBE_API_URL;
    process.env.MEETINGSCRIBE_API_KEY = "my-key";
    delete process.env.MEETINGSCRIBE_PROMPTS_DIR;
    delete process.env.MEETINGSCRIBE_OUTPUT_DIR;

    const config = getConfig();

    expect(config.apiUrl).toBe("http://localhost:3000");
    expect(config.apiKey).toBe("my-key");
    expect(config.promptsDir).toBe(join(process.cwd(), "prompts"));
    expect(config.outputDir).toBe(join(homedir(), "MeetingScribe"));
  });
});
