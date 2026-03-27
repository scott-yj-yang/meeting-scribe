// scripts/terminal-server.js
// Tiny WebSocket server that spawns PTY sessions for web terminal
// Run alongside the Next.js server

const { WebSocketServer } = require("ws");
const pty = require("node-pty");
const http = require("http");

const PORT = 3001;
const server = http.createServer();
const wss = new WebSocketServer({ server });

wss.on("connection", (ws, req) => {
  // Parse meeting context from URL: ws://localhost:3001?meetingId=xxx&transcript=/path/to/file
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const meetingId = url.searchParams.get("meetingId");
  const title = url.searchParams.get("title") || "meeting";

  console.log(`[Terminal] New session for meeting: ${meetingId}`);

  // Find claude binary
  const home = process.env.HOME || require("os").homedir();
  const PATH = [
    `${home}/.local/bin`,
    "/opt/homebrew/bin",
    "/usr/local/bin",
    process.env.PATH,
  ].join(":");

  // Build the initial prompt with meeting context
  const contextPrompt = meetingId
    ? `You are helping review a meeting. Fetch the transcript from http://localhost:3000/api/meetings/${meetingId}/export and read it. Then help the user with questions about the meeting "${title}". Start by giving a brief overview.`
    : "You are a helpful assistant.";

  // Spawn claude in a PTY
  const shell = pty.spawn("claude", ["-p", contextPrompt, "--allowedTools", "Read,Grep,WebFetch"], {
    name: "xterm-256color",
    cols: 120,
    rows: 30,
    cwd: home,
    env: { ...process.env, PATH, HOME: home, TERM: "xterm-256color" },
  });

  // PTY -> WebSocket
  shell.onData((data) => {
    try {
      ws.send(data);
    } catch {}
  });

  // WebSocket -> PTY
  ws.on("message", (msg) => {
    const data = msg.toString();
    // Handle resize
    if (data.startsWith("\x01resize:")) {
      const [cols, rows] = data.slice(8).split(",").map(Number);
      shell.resize(cols, rows);
      return;
    }
    shell.write(data);
  });

  shell.onExit(({ exitCode }) => {
    console.log(`[Terminal] Session ended (exit ${exitCode})`);
    ws.close();
  });

  ws.on("close", () => {
    console.log("[Terminal] Client disconnected");
    shell.kill();
  });
});

server.listen(PORT, () => {
  console.log(`[Terminal] WebSocket server on ws://localhost:${PORT}`);
});
