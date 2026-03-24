// @vitest-environment node
import { describe, it, expect, beforeEach } from "vitest";
import { GET, PATCH, DELETE } from "@/app/api/meetings/[id]/route";
import { GET as ExportGET } from "@/app/api/meetings/[id]/export/route";
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

function makeParams(id: string) {
  return { params: Promise.resolve({ id }) };
}

describe("/api/meetings/[id]", () => {
  let meetingId: string;

  beforeEach(async () => {
    // Clean up in correct order to respect foreign keys
    await prisma.segment.deleteMany();
    await prisma.summary.deleteMany();
    await prisma.transcript.deleteMany();
    await prisma.meeting.deleteMany();

    // Seed a meeting with transcript + segments
    const meeting = await prisma.meeting.create({
      data: {
        title: "Sprint Planning",
        date: new Date("2026-03-24T10:00:00.000Z"),
        duration: 3600,
        audioSources: ["mic-1"],
        meetingType: "standup",
        transcript: {
          create: {
            rawMarkdown: "# Sprint Planning\n\nDiscussion about upcoming sprint.",
            segments: {
              create: [
                { speaker: "Alice", text: "Let's plan the sprint.", startTime: 0, endTime: 5.2 },
                { speaker: "Bob", text: "Sounds good.", startTime: 5.3, endTime: 8.0 },
              ],
            },
          },
        },
      },
    });

    meetingId = meeting.id;
  });

  describe("GET", () => {
    it("returns meeting with transcript and summary (200)", async () => {
      const req = makeRequest("GET", `http://localhost/api/meetings/${meetingId}`);
      const res = await GET(req, makeParams(meetingId));
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.id).toBe(meetingId);
      expect(data.title).toBe("Sprint Planning");
      expect(data.duration).toBe(3600);
      expect(data.transcript).toBeDefined();
      expect(data.transcript.rawMarkdown).toContain("Sprint Planning");
      expect(data.transcript.segments).toHaveLength(2);
      // Segments ordered by startTime ascending
      expect(data.transcript.segments[0].speaker).toBe("Alice");
      expect(data.transcript.segments[1].speaker).toBe("Bob");
      // summary is null when none exists
      expect(data.summary).toBeNull();
    });

    it("returns 404 for nonexistent meeting", async () => {
      const fakeId = "00000000-0000-0000-0000-000000000000";
      const req = makeRequest("GET", `http://localhost/api/meetings/${fakeId}`);
      const res = await GET(req, makeParams(fakeId));
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBeDefined();
    });
  });

  describe("PATCH", () => {
    it("updates meeting title", async () => {
      const req = makeRequest("PATCH", `http://localhost/api/meetings/${meetingId}`, {
        title: "Updated Title",
      });
      const res = await PATCH(req, makeParams(meetingId));
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.title).toBe("Updated Title");
      expect(data.transcript).toBeDefined();
      expect(data.summary).toBeNull();

      // Verify persisted
      const dbMeeting = await prisma.meeting.findUnique({ where: { id: meetingId } });
      expect(dbMeeting!.title).toBe("Updated Title");
    });

    it("updates meeting meetingType", async () => {
      const req = makeRequest("PATCH", `http://localhost/api/meetings/${meetingId}`, {
        meetingType: "retrospective",
      });
      const res = await PATCH(req, makeParams(meetingId));
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.meetingType).toBe("retrospective");
    });
  });

  describe("DELETE", () => {
    it("removes meeting and cascades (204)", async () => {
      const req = makeRequest("DELETE", `http://localhost/api/meetings/${meetingId}`);
      const res = await DELETE(req, makeParams(meetingId));

      expect(res.status).toBe(204);

      // Verify deleted from DB
      const dbMeeting = await prisma.meeting.findUnique({ where: { id: meetingId } });
      expect(dbMeeting).toBeNull();

      // Verify transcript also deleted (cascade)
      const transcripts = await prisma.transcript.findMany({ where: { meetingId } });
      expect(transcripts).toHaveLength(0);

      // Verify segments also deleted (cascade)
      const segments = await prisma.segment.findMany();
      expect(segments).toHaveLength(0);
    });
  });
});

describe("/api/meetings/[id]/export", () => {
  let meetingId: string;

  beforeEach(async () => {
    await prisma.segment.deleteMany();
    await prisma.summary.deleteMany();
    await prisma.transcript.deleteMany();
    await prisma.meeting.deleteMany();

    const meeting = await prisma.meeting.create({
      data: {
        title: "Sprint Planning",
        date: new Date("2026-03-24T10:00:00.000Z"),
        duration: 3600,
        audioSources: ["mic-1"],
        meetingType: "standup",
        transcript: {
          create: {
            rawMarkdown: "# Sprint Planning\n\nDiscussion about upcoming sprint.",
            segments: {
              create: [
                { speaker: "Alice", text: "Let's plan the sprint.", startTime: 0, endTime: 5.2 },
                { speaker: "Bob", text: "Sounds good.", startTime: 5.3, endTime: 8.0 },
              ],
            },
          },
        },
      },
    });

    meetingId = meeting.id;
  });

  describe("GET", () => {
    it("returns markdown with correct Content-Type", async () => {
      const req = makeRequest("GET", `http://localhost/api/meetings/${meetingId}/export`);
      const res = await ExportGET(req, makeParams(meetingId));

      expect(res.status).toBe(200);
      expect(res.headers.get("Content-Type")).toBe("text/markdown; charset=utf-8");

      const disposition = res.headers.get("Content-Disposition");
      expect(disposition).toContain("attachment");
      expect(disposition).toContain("2026-03-24");
      expect(disposition).toContain("sprint-planning");
      expect(disposition).toContain(".md");

      const body = await res.text();
      expect(body).toContain("Sprint Planning");
      expect(body).toContain("Alice");
      expect(body).toContain("Bob");
    });

    it("returns 404 for nonexistent meeting", async () => {
      const fakeId = "00000000-0000-0000-0000-000000000000";
      const req = makeRequest("GET", `http://localhost/api/meetings/${fakeId}/export`);
      const res = await ExportGET(req, makeParams(fakeId));
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBeDefined();
    });
  });
});
