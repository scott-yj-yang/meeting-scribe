import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";

const NOTION_VERSION = "2022-06-28";

function getNotionConfig() {
  // Check config file first (set via web UI), then env vars
  const configFile = join(homedir(), ".meetingscribe", "notion.json");
  if (existsSync(configFile)) {
    try {
      const config = JSON.parse(readFileSync(configFile, "utf-8"));
      if (config.apiKey && config.databaseId) return config;
    } catch {}
  }
  return {
    apiKey: process.env.NOTION_API_KEY || "",
    databaseId: process.env.NOTION_DATABASE_ID || "",
  };
}

export function isNotionConfigured(): boolean {
  const { apiKey, databaseId } = getNotionConfig();
  return !!apiKey && !!databaseId;
}

interface NotionMeetingInput {
  title: string;
  date: Date;
  duration: number;
  meetingType: string | null;
  summaryMarkdown: string;
}

/**
 * Create a page in the Notion meeting database with the meeting summary.
 * The summary is converted from markdown to Notion blocks.
 */
export async function syncToNotion(input: NotionMeetingInput): Promise<string> {
  const { apiKey: NOTION_API_KEY, databaseId: NOTION_DATABASE_ID } = getNotionConfig();
  if (!NOTION_API_KEY || !NOTION_DATABASE_ID) {
    throw new Error("Notion is not configured. Go to Settings to set up Notion integration.");
  }

  // Convert markdown summary to Notion blocks
  const blocks = markdownToNotionBlocks(input.summaryMarkdown);

  const body = {
    parent: { database_id: NOTION_DATABASE_ID },
    properties: {
      // Title property (the database's title column)
      title: {
        title: [{ text: { content: input.title } }],
      },
      Date: {
        date: { start: input.date.toISOString().split("T")[0] },
      },
      "Duration ": {
        number: Math.round(input.duration / 60), // minutes
      },
      ...(input.meetingType && {
        Type: {
          select: { name: input.meetingType },
        },
      }),
      Status: {
        status: { name: "Done" },
      },
    },
    children: blocks,
  };

  const res = await fetch("https://api.notion.com/v1/pages", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${NOTION_API_KEY}`,
      "Notion-Version": NOTION_VERSION,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const error = await res.json().catch(() => ({}));
    throw new Error(`Notion API error ${res.status}: ${JSON.stringify(error)}`);
  }

  const page = await res.json();
  return page.url;
}

/**
 * Convert markdown text to an array of Notion blocks.
 * Handles: headings, bullet lists, checkboxes, bold, paragraphs.
 */
function markdownToNotionBlocks(markdown: string): object[] {
  const lines = markdown.split("\n");
  const blocks: object[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    // Heading 1: # ...
    if (trimmed.startsWith("# ")) {
      blocks.push({
        object: "block",
        type: "heading_1",
        heading_1: { rich_text: parseInlineMarkdown(trimmed.slice(2)) },
      });
    }
    // Heading 2: ## ...
    else if (trimmed.startsWith("## ")) {
      blocks.push({
        object: "block",
        type: "heading_2",
        heading_2: { rich_text: parseInlineMarkdown(trimmed.slice(3)) },
      });
    }
    // Heading 3: ### ...
    else if (trimmed.startsWith("### ")) {
      blocks.push({
        object: "block",
        type: "heading_3",
        heading_3: { rich_text: parseInlineMarkdown(trimmed.slice(4)) },
      });
    }
    // Checkbox: - [ ] or - [x]
    else if (trimmed.match(/^- \[[ x]\] /)) {
      const checked = trimmed.startsWith("- [x]");
      const text = trimmed.replace(/^- \[[ x]\] /, "");
      blocks.push({
        object: "block",
        type: "to_do",
        to_do: {
          rich_text: parseInlineMarkdown(text),
          checked,
        },
      });
    }
    // Bullet: - ...
    else if (trimmed.startsWith("- ")) {
      blocks.push({
        object: "block",
        type: "bulleted_list_item",
        bulleted_list_item: { rich_text: parseInlineMarkdown(trimmed.slice(2)) },
      });
    }
    // Blockquote: > ...
    else if (trimmed.startsWith("> ")) {
      blocks.push({
        object: "block",
        type: "quote",
        quote: { rich_text: parseInlineMarkdown(trimmed.slice(2)) },
      });
    }
    // Regular paragraph
    else {
      blocks.push({
        object: "block",
        type: "paragraph",
        paragraph: { rich_text: parseInlineMarkdown(trimmed) },
      });
    }
  }

  // Notion API limits children to 100 blocks per request
  return blocks.slice(0, 100);
}

/**
 * Parse inline markdown (bold, italic, code) into Notion rich_text array.
 */
function parseInlineMarkdown(text: string): object[] {
  const segments: object[] = [];
  // Simple regex-based parser for **bold**, *italic*, `code`
  const regex = /(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|([^*`]+))/g;
  let match;

  while ((match = regex.exec(text)) !== null) {
    if (match[2]) {
      // **bold**
      segments.push({
        type: "text",
        text: { content: match[2] },
        annotations: { bold: true },
      });
    } else if (match[3]) {
      // *italic*
      segments.push({
        type: "text",
        text: { content: match[3] },
        annotations: { italic: true },
      });
    } else if (match[4]) {
      // `code`
      segments.push({
        type: "text",
        text: { content: match[4] },
        annotations: { code: true },
      });
    } else if (match[5]) {
      // plain text
      segments.push({
        type: "text",
        text: { content: match[5] },
      });
    }
  }

  return segments.length > 0
    ? segments
    : [{ type: "text", text: { content: text } }];
}
