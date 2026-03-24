import { NextResponse } from "next/server";
import { validateAuth, unauthorizedResponse } from "@/lib/auth";
import { getJobStatus } from "@/lib/summarize";

type Params = { params: Promise<{ id: string }> };

export async function GET(request: Request, { params }: Params) {
  if (!validateAuth(request.headers)) {
    return unauthorizedResponse();
  }

  const { id } = await params;

  const job = getJobStatus(id);

  if (!job) {
    return NextResponse.json({ status: "not_started" });
  }

  return NextResponse.json(job);
}
