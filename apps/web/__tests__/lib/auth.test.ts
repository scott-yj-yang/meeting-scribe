import { describe, it, expect, afterEach } from "vitest";
import { validateAuth } from "@/lib/auth";

describe("validateAuth", () => {
  const originalEnv = process.env;

  afterEach(() => {
    process.env = originalEnv;
  });

  it("allows all requests when MEETINGSCRIBE_API_KEY is empty", () => {
    process.env = { ...originalEnv, MEETINGSCRIBE_API_KEY: "" };
    expect(validateAuth(new Headers())).toBe(true);
  });

  it("allows all requests when MEETINGSCRIBE_API_KEY is not set", () => {
    process.env = { ...originalEnv };
    delete process.env.MEETINGSCRIBE_API_KEY;
    expect(validateAuth(new Headers())).toBe(true);
  });

  it("rejects requests without token when API key is configured", () => {
    process.env = { ...originalEnv, MEETINGSCRIBE_API_KEY: "secret-key" };
    expect(validateAuth(new Headers())).toBe(false);
  });

  it("rejects requests with wrong token", () => {
    process.env = { ...originalEnv, MEETINGSCRIBE_API_KEY: "secret-key" };
    expect(validateAuth(new Headers({ Authorization: "Bearer wrong-key" }))).toBe(false);
  });

  it("accepts requests with correct Bearer token", () => {
    process.env = { ...originalEnv, MEETINGSCRIBE_API_KEY: "secret-key" };
    expect(validateAuth(new Headers({ Authorization: "Bearer secret-key" }))).toBe(true);
  });
});
