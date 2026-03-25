import { NextRequest } from "next/server";
import { prisma } from "@/lib/prisma";
import { validateAuth, unauthorizedResponse } from "@/lib/auth";
import { formatMeetingMarkdown } from "@/lib/markdown";
import { spawn } from "child_process";

type Params = { params: Promise<{ id: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  if (!validateAuth(request.headers)) return unauthorizedResponse();

  const { id } = await params;
  const body = await request.json();
  const { message, history } = body as {
    message: string;
    history: { role: string; content: string }[];
  };

  if (!message) {
    return new Response(JSON.stringify({ error: "Message is required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Fetch meeting + transcript
  const meeting = await prisma.meeting.findUnique({
    where: { id },
    include: {
      transcript: { include: { segments: { orderBy: { startTime: "asc" } } } },
      summary: true,
    },
  });

  if (!meeting) {
    return new Response(JSON.stringify({ error: "Meeting not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Build the transcript markdown
  const transcriptMd = meeting.transcript
    ? formatMeetingMarkdown({
        title: meeting.title,
        date: meeting.date,
        duration: meeting.duration,
        meetingType: meeting.meetingType,
        audioSources: meeting.audioSources,
        segments: meeting.transcript.segments,
      })
    : "No transcript available.";

  // Build conversation context
  const systemPrompt = `You are a helpful assistant for discussing a meeting. Here is the full meeting transcript:

---
${transcriptMd}
---

${meeting.summary ? `Here is the existing summary:\n\n${meeting.summary.content}\n\n---\n\n` : ""}
Answer the user's questions about this meeting. Be concise, reference specific parts of the transcript, and quote relevant passages when helpful.`;

  // Build the full prompt with history
  let fullPrompt = systemPrompt + "\n\n";
  for (const msg of history || []) {
    if (msg.role === "user") {
      fullPrompt += `User: ${msg.content}\n\n`;
    } else {
      fullPrompt += `Assistant: ${msg.content}\n\n`;
    }
  }
  fullPrompt += `User: ${message}\n\nAssistant:`;

  // Stream response from Claude Code
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    start(controller) {
      const claude = spawn("claude", ["-p", fullPrompt, "--no-input"], {
        env: { ...process.env, PATH: process.env.PATH || "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" },
      });

      let buffer = "";

      claude.stdout.on("data", (data: Buffer) => {
        const text = data.toString();
        buffer += text;
        // Send as SSE
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ text })}\n\n`));
      });

      claude.stderr.on("data", (data: Buffer) => {
        // Ignore stderr (Claude Code progress output)
      });

      claude.on("close", (code: number) => {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ done: true, fullText: buffer })}\n\n`));
        controller.close();
      });

      claude.on("error", (err: Error) => {
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify({ error: err.message })}\n\n`)
        );
        controller.close();
      });
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}
