import { NextRequest } from "next/server";
import { prisma } from "@/lib/prisma";
import { validateAuth, unauthorizedResponse } from "@/lib/auth";
import { formatMeetingMarkdown } from "@/lib/markdown";
import { spawn } from "child_process";
import { homedir } from "os";

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

  const systemPrompt = `You are a helpful assistant for discussing a meeting. Here is the full meeting transcript:

---
${transcriptMd}
---

${meeting.summary ? `Here is the existing summary:\n\n${meeting.summary.content}\n\n---\n\n` : ""}
Answer the user's questions about this meeting. Be concise, reference specific parts of the transcript, and quote relevant passages when helpful.`;

  let fullPrompt = systemPrompt + "\n\n";
  for (const msg of history || []) {
    if (msg.role === "user") {
      fullPrompt += `User: ${msg.content}\n\n`;
    } else {
      fullPrompt += `Assistant: ${msg.content}\n\n`;
    }
  }
  fullPrompt += `User: ${message}\n\nRespond directly to the user's question:`;

  // Find claude binary
  const home = homedir();
  const extraPaths = [
    `${home}/.local/bin`,
    `${home}/.nvm/versions/node/v24.11.0/bin`,
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
  ].join(":");

  const fullPath = `${extraPaths}:${process.env.PATH || ""}`;

  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    start(controller) {
      console.log("[Chat] Spawning claude for meeting", id);

      const claude = spawn("claude", ["-p", fullPrompt, "--no-input"], {
        env: {
          ...process.env,
          PATH: fullPath,
          HOME: home,
        },
        shell: false,
      });

      let buffer = "";
      let hasOutput = false;

      claude.stdout.on("data", (data: Buffer) => {
        hasOutput = true;
        const text = data.toString();
        buffer += text;
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ text })}\n\n`));
      });

      claude.stderr.on("data", (data: Buffer) => {
        const text = data.toString();
        console.log("[Chat] stderr:", text.substring(0, 200));
      });

      claude.on("close", (code: number) => {
        console.log("[Chat] Process exited with code", code, "output length:", buffer.length);
        if (!hasOutput && code !== 0) {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify({ text: "Error: Claude Code exited without output. Make sure it's installed and authenticated." })}\n\n`)
          );
        }
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ done: true })}\n\n`));
        controller.close();
      });

      claude.on("error", (err: Error) => {
        console.error("[Chat] Spawn error:", err.message);
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify({ text: `Error: ${err.message}` })}\n\n`)
        );
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ done: true })}\n\n`));
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
