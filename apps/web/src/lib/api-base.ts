/**
 * Returns the base URL for API calls.
 * - In browser/dev mode: '' (relative URLs, same-origin)
 * - In bundled desktop app: 'app:/' (intercepted by WKURLSchemeHandler)
 */
export function apiBase(): string {
  if (typeof window !== "undefined" && (window as unknown as Record<string, unknown>).__MEETINGSCRIBE_DESKTOP__) {
    return "app:/";
  }
  return "";
}
