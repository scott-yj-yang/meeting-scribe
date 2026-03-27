import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { validateAuth, unauthorizedResponse } from "@/lib/auth";
import { startSummarizeJob, getJobStatus, clearJobStatus, forceCancel } from "@/lib/summarize";

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

    // Read body
    let customInstruction: string | undefined;
    let force = false;
    try {
      const body = await request.json();
      if (body.customInstruction && typeof body.customInstruction === "string") {
        customInstruction = body.customInstruction;
      }
      if (body.force === true) {
        force = true;
      }
    } catch {
      // Body may be empty
    }

    const existingJob = getJobStatus(id);

    if (existingJob?.status === "running") {
      if (force) {
        // Force cancel the stuck job and start fresh
        forceCancel(id);
        clearJobStatus(id);
      } else {
        const elapsed = existingJob.elapsedSeconds || 0;
        return NextResponse.json(
          {
            error: "Summarization already in progress",
            elapsed,
            hint: "Send { \"force\": true } to force restart",
          },
          { status: 409 }
        );
      }
    }

    // Clear any completed/failed job
    if (existingJob) {
      clearJobStatus(id);
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

// DELETE to cancel a running job
export async function DELETE(request: Request, { params }: Params) {
  if (!validateAuth(request.headers)) {
    return unauthorizedResponse();
  }

  const { id } = await params;
  forceCancel(id);
  clearJobStatus(id);
  return NextResponse.json({ status: "cancelled" });
}
