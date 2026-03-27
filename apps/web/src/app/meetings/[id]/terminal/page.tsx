"use client";
import { useEffect, useRef, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";

export default function TerminalPage() {
  const { id } = useParams<{ id: string }>();
  const termRef = useRef<HTMLDivElement>(null);
  const [title, setTitle] = useState("");
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    fetch(`/api/meetings/${id}`)
      .then((r) => r.json())
      .then((d) => setTitle(d.title || ""));
  }, [id]);

  useEffect(() => {
    if (!termRef.current) return;

    let terminal: any;
    let ws: WebSocket;
    let cleanupResize: (() => void) | undefined;

    async function init() {
      const { Terminal } = await import("@xterm/xterm");
      const { FitAddon } = await import("@xterm/addon-fit");
      const { WebLinksAddon } = await import("@xterm/addon-web-links");

      // Import CSS
      await import("@xterm/xterm/css/xterm.css");

      const fitAddon = new FitAddon();
      terminal = new Terminal({
        cursorBlink: true,
        fontSize: 13,
        fontFamily:
          "'SF Mono', 'Fira Code', 'Cascadia Code', Menlo, monospace",
        theme: {
          background: "#0a0a0a",
          foreground: "#e4e4e7",
          cursor: "#e4e4e7",
          selectionBackground: "#3f3f46",
          black: "#18181b",
          red: "#ef4444",
          green: "#22c55e",
          yellow: "#eab308",
          blue: "#3b82f6",
          magenta: "#a855f7",
          cyan: "#06b6d4",
          white: "#e4e4e7",
        },
        allowProposedApi: true,
      });

      terminal.loadAddon(fitAddon);
      terminal.loadAddon(new WebLinksAddon());
      terminal.open(termRef.current!);
      fitAddon.fit();

      // Connect WebSocket
      const wsUrl = `ws://localhost:3001?meetingId=${id}&title=${encodeURIComponent(title)}`;
      ws = new WebSocket(wsUrl);

      ws.onopen = () => {
        setConnected(true);
        // Send initial size
        ws.send(`\x01resize:${terminal.cols},${terminal.rows}`);
      };

      ws.onmessage = (event) => {
        terminal.write(event.data);
      };

      ws.onclose = () => {
        setConnected(false);
        terminal.write("\r\n\x1b[90m[Session ended]\x1b[0m\r\n");
      };

      // Terminal input -> WebSocket
      terminal.onData((data: string) => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(data);
        }
      });

      // Handle resize
      const resizeObserver = new ResizeObserver(() => {
        fitAddon.fit();
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(`\x01resize:${terminal.cols},${terminal.rows}`);
        }
      });
      resizeObserver.observe(termRef.current!);

      cleanupResize = () => resizeObserver.disconnect();
    }

    init();

    return () => {
      cleanupResize?.();
      terminal?.dispose();
      ws?.close();
    };
  }, [id, title]);

  return (
    <div className="flex h-[calc(100vh-48px)] flex-col bg-[#0a0a0a]">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-2">
        <div className="flex items-center gap-3">
          <Link
            href={`/meetings/${id}`}
            className="text-xs text-zinc-500 hover:text-zinc-300"
          >
            &larr; Back
          </Link>
          <span className="text-xs text-zinc-600">|</span>
          <span className="text-xs text-zinc-400">{title}</span>
        </div>
        <div className="flex items-center gap-2">
          <span
            className={`inline-block h-2 w-2 rounded-full ${connected ? "bg-green-500" : "bg-red-500"}`}
          />
          <span className="text-xs text-zinc-500">
            {connected ? "Connected" : "Disconnected"}
          </span>
        </div>
      </div>
      {/* Terminal */}
      <div ref={termRef} className="flex-1" />
    </div>
  );
}
