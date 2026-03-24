import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { validateAuth, unauthorizedResponse } from "@/lib/auth";
import { syncToNotion, isNotionConfigured } from "@/lib/notion";

type Params = { params: Promise<{ id: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  if (!validateAuth(request.headers)) return unauthorizedResponse();

  if (!isNotionConfigured()) {
    return NextResponse.json(
      { error: "Notion is not configured. Set NOTION_API_KEY and NOTION_DATABASE_ID environment variables." },
      { status: 400 }
    );
  }

  const { id } = await params;

  const meeting = await prisma.meeting.findUnique({
    where: { id },
    include: { summary: true },
  });

  if (!meeting) {
    return NextResponse.json({ error: "Meeting not found" }, { status: 404 });
  }

  if (!meeting.summary) {
    return NextResponse.json(
      { error: "Meeting has no summary. Summarize it first." },
      { status: 400 }
    );
  }

  try {
    const notionUrl = await syncToNotion({
      title: meeting.title,
      date: meeting.date,
      duration: meeting.duration,
      meetingType: meeting.meetingType,
      summaryMarkdown: meeting.summary.content,
    });

    return NextResponse.json({ url: notionUrl });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
