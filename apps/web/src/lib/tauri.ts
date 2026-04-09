/**
 * Tauri desktop integration bridge.
 * Detects if running inside Tauri and provides native feature wrappers.
 * Falls back gracefully to browser APIs when not in Tauri.
 */

/** Check if running inside a Tauri webview */
export function isTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI__" in window;
}

/** Invoke a Tauri command (throws outside Tauri) */
async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  if (!isTauri()) throw new Error("Not running in Tauri");
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<T>(cmd, args);
}

/** Show a notification when transcription or summarization completes */
export async function showNotification(title: string, body: string): Promise<void> {
  if ("Notification" in window && Notification.permission === "granted") {
    new Notification(title, { body });
  } else if ("Notification" in window && Notification.permission === "default") {
    const perm = await Notification.requestPermission();
    if (perm === "granted") {
      new Notification(title, { body });
    }
  }
}

/** Open native file picker for audio files. Returns file path or null. */
export async function pickAudioFile(): Promise<{ path: string; name: string; size: number } | null> {
  if (!isTauri()) return null;
  return invoke("pick_audio_file");
}

/** Check if the backend server is healthy */
export async function checkServerHealth(): Promise<boolean> {
  if (!isTauri()) return true; // In browser, assume server is the host
  return invoke("check_server_health");
}

/** Get the desktop platform name */
export async function getPlatform(): Promise<string | null> {
  if (!isTauri()) return null;
  return invoke("get_platform");
}
