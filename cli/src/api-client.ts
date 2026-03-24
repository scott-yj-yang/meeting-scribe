import { getConfig } from "./config.js";

export class APIClient {
  private baseUrl: string;
  private apiKey: string;

  constructor() {
    const config = getConfig();
    this.baseUrl = config.apiUrl;
    this.apiKey = config.apiKey;
  }

  private headers(): Record<string, string> {
    const h: Record<string, string> = { "Content-Type": "application/json" };
    if (this.apiKey) h["Authorization"] = `Bearer ${this.apiKey}`;
    return h;
  }

  async listMeetings(page = 1, limit = 20) {
    const res = await fetch(
      `${this.baseUrl}/api/meetings?page=${page}&limit=${limit}`,
      { headers: this.headers() },
    );
    if (!res.ok) throw new Error(`API error: ${res.status}`);
    return res.json();
  }

  async getMeeting(id: string) {
    const res = await fetch(`${this.baseUrl}/api/meetings/${id}`, {
      headers: this.headers(),
    });
    if (!res.ok) throw new Error(`API error: ${res.status}`);
    return res.json();
  }

  async exportMeeting(id: string): Promise<string> {
    const res = await fetch(`${this.baseUrl}/api/meetings/${id}/export`, {
      headers: this.headers(),
    });
    if (!res.ok) throw new Error(`API error: ${res.status}`);
    return res.text();
  }
}
