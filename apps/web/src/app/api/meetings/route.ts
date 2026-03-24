import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { validateAuth, unauthorizedResponse } from "@/lib/auth";
import type { CreateMeetingInput } from "@/types/meeting";

export async function POST(request: Request) {
  if (!validateAuth(request.headers)) {
    return unauthorizedResponse();
  }

  try {
    const body = (await request.json()) as Partial<CreateMeetingInput>;

    const { title, date, duration, audioSources, meetingType, rawMarkdown, segments } = body;

    if (!title || !date || duration === undefined || !rawMarkdown || !segments) {
      return NextResponse.json(
        { error: "Missing required fields: title, date, duration, rawMarkdown, segments" },
        { status: 400 }
      );
    }

    const meeting = await prisma.meeting.create({
      data: {
        title,
        date: new Date(date),
        duration,
        audioSources: audioSources ?? [],
        meetingType: meetingType ?? null,
        transcript: {
          create: {
            rawMarkdown,
            segments: {
              create: segments.map((s) => ({
                speaker: s.speaker,
                text: s.text,
                startTime: s.startTime,
                endTime: s.endTime,
              })),
            },
          },
        },
      },
      include: {
        transcript: { include: { segments: true } },
        summary: true,
      },
    });

    return NextResponse.json(meeting, { status: 201 });
  } catch (error) {
    console.error("POST /api/meetings error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}

export async function GET(request: Request) {
  if (!validateAuth(request.headers)) {
    return unauthorizedResponse();
  }

  try {
    const { searchParams } = new URL(request.url);
    const q = searchParams.get("q") ?? undefined;
    const page = Math.max(1, parseInt(searchParams.get("page") ?? "1", 10));
    const limit = Math.max(1, parseInt(searchParams.get("limit") ?? "20", 10));

    const where = q
      ? {
          OR: [
            { title: { contains: q, mode: "insensitive" as const } },
            { transcript: { rawMarkdown: { contains: q, mode: "insensitive" as const } } },
          ],
        }
      : undefined;

    const [meetings, total] = await Promise.all([
      prisma.meeting.findMany({
        where,
        orderBy: { date: "desc" },
        skip: (page - 1) * limit,
        take: limit,
        include: {
          summary: { select: { id: true, generatedAt: true } },
        },
      }),
      prisma.meeting.count({ where }),
    ]);

    return NextResponse.json({ meetings, total, page, limit });
  } catch (error) {
    console.error("GET /api/meetings error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
