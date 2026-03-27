import { NextResponse } from "next/server";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";
import { homedir } from "os";

const CONFIG_DIR = join(homedir(), ".meetingscribe");
const CONFIG_FILE = join(CONFIG_DIR, "notion.json");

interface NotionConfig {
  apiKey: string;
  databaseId: string;
  databaseName?: string;
}

function loadConfig(): NotionConfig {
  // Check config file first, then fall back to env vars
  if (existsSync(CONFIG_FILE)) {
    try {
      return JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
    } catch {}
  }
  return {
    apiKey: process.env.NOTION_API_KEY || "",
    databaseId: process.env.NOTION_DATABASE_ID || "",
  };
}

function saveConfig(config: NotionConfig) {
  mkdirSync(CONFIG_DIR, { recursive: true });
  writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
}

// GET — return current config (masked key)
export async function GET() {
  const config = loadConfig();
  return NextResponse.json({
    configured: !!config.apiKey && !!config.databaseId,
    apiKey: config.apiKey ? `${config.apiKey.slice(0, 8)}...${config.apiKey.slice(-4)}` : "",
    databaseId: config.databaseId,
    databaseName: config.databaseName || "",
  });
}

// POST — save config and validate
export async function POST(request: Request) {
  const body = await request.json();
  const { apiKey, databaseId } = body as { apiKey: string; databaseId: string };

  if (!apiKey || !databaseId) {
    return NextResponse.json({ error: "Both API key and database ID are required" }, { status: 400 });
  }

  // Extract database ID from URL if user pasted a full Notion URL
  let cleanDbId = databaseId;
  // Handle: https://www.notion.so/xxxxx?v=yyyyy
  const urlMatch = databaseId.match(/notion\.so\/(?:.*\/)?([a-f0-9]{32})/);
  if (urlMatch) {
    cleanDbId = urlMatch[1];
  }
  // Handle: xxxxx-xxxxx-xxxxx (with hyphens)
  cleanDbId = cleanDbId.replace(/-/g, "").slice(0, 32);

  // Validate by calling Notion API
  try {
    const res = await fetch(`https://api.notion.com/v1/databases/${cleanDbId}`, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Notion-Version": "2022-06-28",
      },
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      if (res.status === 401) {
        return NextResponse.json({ error: "Invalid API key. Check your Notion integration token." }, { status: 400 });
      }
      if (res.status === 404) {
        return NextResponse.json({
          error: "Database not found. Make sure you've shared the database with your integration (click ··· → Connections → add your integration).",
        }, { status: 400 });
      }
      return NextResponse.json({ error: `Notion API error: ${JSON.stringify(err)}` }, { status: 400 });
    }

    const db = await res.json();
    const dbName = db.title?.[0]?.plain_text || "Untitled";

    // Save config
    const config: NotionConfig = { apiKey, databaseId: cleanDbId, databaseName: dbName };
    saveConfig(config);

    // Also update process env for the current session
    process.env.NOTION_API_KEY = apiKey;
    process.env.NOTION_DATABASE_ID = cleanDbId;

    return NextResponse.json({
      success: true,
      databaseName: dbName,
      databaseId: cleanDbId,
    });
  } catch (error) {
    return NextResponse.json({ error: "Could not connect to Notion. Check your internet connection." }, { status: 500 });
  }
}

// DELETE — remove config
export async function DELETE() {
  try {
    const { unlinkSync } = require("fs");
    unlinkSync(CONFIG_FILE);
  } catch {}
  process.env.NOTION_API_KEY = "";
  process.env.NOTION_DATABASE_ID = "";
  return NextResponse.json({ success: true });
}
