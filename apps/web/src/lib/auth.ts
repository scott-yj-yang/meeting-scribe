export function validateAuth(headers: Headers): boolean {
  const apiKey = process.env.MEETINGSCRIBE_API_KEY;
  if (!apiKey) return true;

  const authHeader = headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) return false;

  const token = authHeader.slice(7);
  return token === apiKey;
}

export function unauthorizedResponse() {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}
