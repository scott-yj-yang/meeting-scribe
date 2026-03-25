import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { validateAuth, unauthorizedResponse } from "@/lib/auth";
import { startSummarizeJob, getJobStatus, clearJobStatus } from "@/lib/summarize";

type Params = { params: Promise<{ id: string }> };

export async function POST(request: Request, { params }: Params) {
  if (!validateAuth(request.headers)) {
    return unauthorizedResponse();
  }

  try {
    const { id } = await params;

    const meeting = await prisma.meeting.findUnique({ where: { id } });

    if (!meeting) {
      return NextResponse.json({ error: "Meeting not found" }, { status: 404 });
    }

    const existingJob = getJobStatus(id);
    if (existingJob?.status === "running") {
      return NextResponse.json(
        { error: "Summarization already in progress" },
        { status: 409 }
      );
    }

    // Clear any completed/failed job so we can re-run
    if (existingJob) {
      clearJobStatus(id);
    }

    // Read optional customInstruction from the request body
    let customInstruction: string | undefined;
    try {
      const body = await request.json();
      if (body.customInstruction && typeof body.customInstruction === "string") {
        customInstruction = body.customInstruction;
      }
    } catch {
      // Body may be empty or not JSON — that's fine, proceed without custom instruction
    }

    startSummarizeJob(id, customInstruction);

    return NextResponse.json({ status: "started", meetingId: id }, { status: 202 });
  } catch (error) {
    console.error("POST /api/meetings/[id]/summarize error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
