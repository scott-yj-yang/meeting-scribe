import { describe, it, expect } from "vitest";
import { formatMeetingMarkdown, formatDuration } from "@/lib/markdown";

describe("formatDuration", () => {
  it("formats seconds into human-readable duration", () => {
    expect(formatDuration(1823)).toBe("30 minutes 23 seconds");
  });
  it("formats hours correctly", () => {
    expect(formatDuration(3661)).toBe("1 hour 1 minute 1 second");
  });
  it("handles zero", () => {
    expect(formatDuration(0)).toBe("0 seconds");
  });
});

describe("formatMeetingMarkdown", () => {
  it("produces correct markdown with YAML frontmatter", () => {
    const result = formatMeetingMarkdown({
      title: "Weekly Standup",
      date: new Date("2026-03-24T10:00:00Z"),
      duration: 1823,
      meetingType: "standup",
      audioSources: ["system", "microphone"],
      segments: [
        { speaker: "Local Speaker", text: "Good morning.", startTime: 12, endTime: 15 },
        { speaker: "Remote Speaker", text: "Hey there!", startTime: 18, endTime: 21 },
      ],
    });

    expect(result).toContain('title: "Weekly Standup"');
    expect(result).toContain("duration: 1823");
    expect(result).toContain("[00:00:12] **Local Speaker**: Good morning.");
    expect(result).toContain("[00:00:18] **Remote Speaker**: Hey there!");
    expect(result).toContain("## --- END TRANSCRIPT ---");
  });

  it("extracts unique participant names", () => {
    const result = formatMeetingMarkdown({
      title: "Test",
      date: new Date("2026-03-24T10:00:00Z"),
      duration: 60,
      meetingType: null,
      audioSources: ["microphone"],
      segments: [
        { speaker: "Alice", text: "Hi", startTime: 0, endTime: 2 },
        { speaker: "Bob", text: "Hi", startTime: 3, endTime: 5 },
        { speaker: "Alice", text: "Bye", startTime: 6, endTime: 8 },
      ],
    });
    expect(result).toContain('participants: ["Alice","Bob"]');
  });
});
