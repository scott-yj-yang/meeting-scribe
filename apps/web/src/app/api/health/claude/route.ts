import { NextResponse } from "next/server";
import { execFile } from "child_process";
import { homedir } from "os";

export async function GET() {
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

  const result: { claude: string; meetingctl: string; version?: string } = {
    claude: "not-found",
    meetingctl: "not-found",
  };

  // Check claude
  try {
    const version = await new Promise<string>((resolve, reject) => {
      execFile("claude", ["--version"],
        { env: { ...process.env, PATH: fullPath, HOME: home }, timeout: 5000 },
        (err, stdout) => err ? reject(err) : resolve(stdout.trim())
      );
    });
    result.claude = "ready";
    result.version = version;
  } catch {
    result.claude = "not-found";
  }

  // Check meetingctl
  try {
    await new Promise<string>((resolve, reject) => {
      execFile("meetingctl", ["--version"],
        { env: { ...process.env, PATH: fullPath, HOME: home }, timeout: 5000 },
        (err, stdout) => err ? reject(err) : resolve(stdout.trim())
      );
    });
    result.meetingctl = "ready";
  } catch {
    result.meetingctl = "not-found";
  }

  const status = result.claude === "ready" ? "ready" : "not-installed";
  return NextResponse.json({ status, ...result });
}
