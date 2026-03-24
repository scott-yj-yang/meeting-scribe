interface MarkdownInput {
  title: string;
  date: Date;
  duration: number;
  meetingType: string | null;
  audioSources: string[];
  segments: { speaker: string; text: string; startTime: number; endTime: number }[];
}

export function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  const parts: string[] = [];
  if (h > 0) parts.push(`${h} hour${h !== 1 ? "s" : ""}`);
  if (m > 0) parts.push(`${m} minute${m !== 1 ? "s" : ""}`);
  if (s > 0 || parts.length === 0) parts.push(`${s} second${s !== 1 ? "s" : ""}`);
  return parts.join(" ");
}

function formatTimestamp(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  return `[${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}]`;
}

export function formatMeetingMarkdown(input: MarkdownInput): string {
  const participants = [...new Set(input.segments.map((s) => s.speaker))];
  const dateStr = input.date.toISOString().split(".")[0];
  const humanDate = input.date.toLocaleDateString("en-US", {
    year: "numeric", month: "long", day: "numeric", hour: "numeric", minute: "2-digit",
  });

  const frontmatter = [
    "---",
    `title: "${input.title}"`,
    `date: ${dateStr}`,
    `duration: ${input.duration}`,
    `meeting_type: ${input.meetingType ? `"${input.meetingType}"` : "null"}`,
    `audio_sources: ${JSON.stringify(input.audioSources)}`,
    `participants: ${JSON.stringify(participants)}`,
    "---",
  ].join("\n");

  const header = [
    `# Meeting Transcript: ${input.title}`,
    `**Date**: ${humanDate}`,
    `**Duration**: ${formatDuration(input.duration)}`,
  ].join("\n");

  const transcript = input.segments
    .map((seg) => `${formatTimestamp(seg.startTime)} **${seg.speaker}**: ${seg.text}`)
    .join("\n\n");

  return `${frontmatter}\n\n${header}\n\n## Transcript\n\n${transcript}\n\n## --- END TRANSCRIPT ---\n`;
}
