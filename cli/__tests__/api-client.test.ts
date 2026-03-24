import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { APIClient } from "../src/api-client.js";

// Mock global fetch
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

describe("APIClient", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env.MEETINGSCRIBE_API_URL = "http://test-api:4000";
    process.env.MEETINGSCRIBE_API_KEY = "test-bearer-token";
    mockFetch.mockReset();
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("constructs correct URL for listMeetings", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ meetings: [] }),
    });

    const client = new APIClient();
    await client.listMeetings(2, 15);

    expect(mockFetch).toHaveBeenCalledWith(
      "http://test-api:4000/api/meetings?page=2&limit=15",
      expect.objectContaining({
        headers: expect.objectContaining({
          "Content-Type": "application/json",
          Authorization: "Bearer test-bearer-token",
        }),
      }),
    );
  });

  it("constructs correct URL for getMeeting", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ id: "abc-123" }),
    });

    const client = new APIClient();
    await client.getMeeting("abc-123");

    expect(mockFetch).toHaveBeenCalledWith(
      "http://test-api:4000/api/meetings/abc-123",
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: "Bearer test-bearer-token",
        }),
      }),
    );
  });

  it("constructs correct URL for exportMeeting", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      text: () => Promise.resolve("# Meeting Export"),
    });

    const client = new APIClient();
    const result = await client.exportMeeting("xyz-789");

    expect(mockFetch).toHaveBeenCalledWith(
      "http://test-api:4000/api/meetings/xyz-789/export",
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: "Bearer test-bearer-token",
        }),
      }),
    );
    expect(result).toBe("# Meeting Export");
  });

  it("includes Bearer token in headers when apiKey is set", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({}),
    });

    const client = new APIClient();
    await client.listMeetings();

    const callHeaders = mockFetch.mock.calls[0][1].headers;
    expect(callHeaders["Authorization"]).toBe("Bearer test-bearer-token");
  });

  it("omits Authorization header when apiKey is empty", async () => {
    process.env.MEETINGSCRIBE_API_KEY = "";
    mockFetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({}),
    });

    const client = new APIClient();
    await client.listMeetings();

    const callHeaders = mockFetch.mock.calls[0][1].headers;
    expect(callHeaders["Authorization"]).toBeUndefined();
  });

  it("throws on non-OK response", async () => {
    mockFetch.mockResolvedValue({
      ok: false,
      status: 404,
    });

    const client = new APIClient();
    await expect(client.getMeeting("bad-id")).rejects.toThrow("API error: 404");
  });

  it("uses default pagination values", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ meetings: [] }),
    });

    const client = new APIClient();
    await client.listMeetings();

    expect(mockFetch).toHaveBeenCalledWith(
      "http://test-api:4000/api/meetings?page=1&limit=20",
      expect.any(Object),
    );
  });
});
