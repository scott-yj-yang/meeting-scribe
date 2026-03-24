// @vitest-environment node
import { describe, it, expect, beforeEach } from "vitest";
import { GET, POST } from "@/app/api/meetings/route";
import { prisma } from "@/lib/prisma";

function makeRequest(
  method: string,
  url: string,
  body?: unknown
): Request {
  const init: RequestInit = {
    method,
    headers: { "Content-Type": "application/json" },
  };
  if (body) init.body = JSON.stringify(body);
  return new Request(url, init);
}

const validPayload = {
  title: "Sprint Planning",
  date: "2026-03-24T10:00:00.000Z",
  duration: 3600,
  audioSources: ["mic-1"],
  rawMarkdown: "# Sprint Planning\n\nDiscussion about upcoming sprint.",
  segments: [
    { speaker: "Alice", text: "Let's plan the sprint.", startTime: 0, endTime: 5.2 },
    { speaker: "Bob", text: "Sounds good.", startTime: 5.3, endTime: 8.0 },
  ],
};

describe("/api/meetings", () => {
  beforeEach(async () => {
    // Clean up in correct order to respect foreign keys
    await prisma.segment.deleteMany();
    await prisma.summary.deleteMany();
    await prisma.transcript.deleteMany();
    await prisma.meeting.deleteMany();
  });

  describe("POST", () => {
    it("creates a meeting with transcript and segments (201)", async () => {
      const req = makeRequest("POST", "http://localhost/api/meetings", validPayload);
      const res = await POST(req);
      const data = await res.json();

      expect(res.status).toBe(201);
      expect(data.id).toBeDefined();
      expect(data.title).toBe("Sprint Planning");
      expect(data.duration).toBe(3600);
      expect(data.transcript).toBeDefined();
      expect(data.transcript.rawMarkdown).toBe(validPayload.rawMarkdown);
      expect(data.transcript.segments).toHaveLength(2);
      expect(data.transcript.segments[0].speaker).toBe("Alice");
      expect(data.transcript.segments[1].speaker).toBe("Bob");
      expect(data.summary).toBeNull();

      // Verify persisted in DB
      const dbMeeting = await prisma.meeting.findUnique({
        where: { id: data.id },
        include: { transcript: { include: { segments: true } } },
      });
      expect(dbMeeting).not.toBeNull();
      expect(dbMeeting!.transcript!.segments).toHaveLength(2);
    });

    it("rejects missing required fields (400)", async () => {
      const cases = [
        { ...validPayload, title: undefined },
        { ...validPayload, date: undefined },
        { ...validPayload, duration: undefined },
        { ...validPayload, rawMarkdown: undefined },
        { ...validPayload, segments: undefined },
      ];

      for (const payload of cases) {
        const req = makeRequest("POST", "http://localhost/api/meetings", payload);
        const res = await POST(req);
        expect(res.status).toBe(400);
        const data = await res.json();
        expect(data.error).toBeDefined();
      }
    });
  });

  describe("GET", () => {
    beforeEach(async () => {
      // Seed three meetings with different dates
      const meetings = [
        { title: "Standup Alpha", date: new Date("2026-03-20"), duration: 900 },
        { title: "Retro Beta", date: new Date("2026-03-22"), duration: 1800 },
        { title: "Planning Gamma", date: new Date("2026-03-24"), duration: 3600 },
      ];

      for (const m of meetings) {
        await prisma.meeting.create({
          data: {
            ...m,
            audioSources: [],
            transcript: {
              create: {
                rawMarkdown: `Transcript for ${m.title}`,
                segments: { create: [] },
              },
            },
          },
        });
      }
    });

    it("returns meetings sorted by date descending", async () => {
      const req = makeRequest("GET", "http://localhost/api/meetings");
      const res = await GET(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.meetings).toHaveLength(3);
      expect(data.total).toBe(3);
      expect(data.page).toBe(1);
      expect(data.limit).toBe(20);

      // Verify descending order
      expect(data.meetings[0].title).toBe("Planning Gamma");
      expect(data.meetings[1].title).toBe("Retro Beta");
      expect(data.meetings[2].title).toBe("Standup Alpha");
    });

    it("supports ?q= search query", async () => {
      const req = makeRequest("GET", "http://localhost/api/meetings?q=retro");
      const res = await GET(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.meetings).toHaveLength(1);
      expect(data.meetings[0].title).toBe("Retro Beta");
      expect(data.total).toBe(1);
    });

    it("supports search in transcript rawMarkdown", async () => {
      const req = makeRequest("GET", "http://localhost/api/meetings?q=Standup");
      const res = await GET(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.meetings).toHaveLength(1);
      expect(data.meetings[0].title).toBe("Standup Alpha");
    });

    it("supports ?page= and ?limit= pagination", async () => {
      const req = makeRequest("GET", "http://localhost/api/meetings?page=2&limit=1");
      const res = await GET(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.meetings).toHaveLength(1);
      expect(data.total).toBe(3);
      expect(data.page).toBe(2);
      expect(data.limit).toBe(1);
      // With desc ordering and page=2, limit=1, we get the second item
      expect(data.meetings[0].title).toBe("Retro Beta");
    });
  });
});
