import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { validateAuth, unauthorizedResponse } from "@/lib/auth";
import { formatMeetingMarkdown } from "@/lib/markdown";

type Params = { params: Promise<{ id: string }> };

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

export async function GET(request: Request, { params }: Params) {
  if (!validateAuth(request.headers)) {
    return unauthorizedResponse();
  }

  try {
    const { id } = await params;

    const meeting = await prisma.meeting.findUnique({
      where: { id },
      include: {
        transcript: {
          include: {
            segments: { orderBy: { startTime: "asc" } },
          },
        },
      },
    });

    if (!meeting || !meeting.transcript) {
      return NextResponse.json({ error: "Meeting not found" }, { status: 404 });
    }

    const markdown = formatMeetingMarkdown({
      title: meeting.title,
      date: meeting.date,
      duration: meeting.duration,
      meetingType: meeting.meetingType,
      audioSources: meeting.audioSources,
      segments: meeting.transcript.segments,
    });

    const dateStr = meeting.date.toISOString().split("T")[0];
    const slug = slugify(meeting.title);
    const filename = `${dateStr}-${slug}.md`;

    return new Response(markdown, {
      status: 200,
      headers: {
        "Content-Type": "text/markdown; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filename}"`,
      },
    });
  } catch (error) {
    console.error("GET /api/meetings/[id]/export error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
