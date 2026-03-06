#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env --allow-net --allow-run

import { readAll } from "jsr:@std/io@0.224/read-all";

const CACHE_FILE = "/tmp/claude-usage-cache.json";
const CACHE_TTL_MS = 60_000;

interface UsageResponse {
  five_hour?: { utilization?: number; resets_at?: string };
  seven_day?: { utilization?: number; resets_at?: string };
  type?: string;
  error?: { type?: string; message?: string };
}

interface KeychainCredentials {
  claudeAiOauth?: {
    accessToken?: string;
    expiresAt?: number;
  };
}

async function isCacheFresh(): Promise<boolean> {
  try {
    const stat = await Deno.stat(CACHE_FILE);
    if (stat.mtime && Date.now() - stat.mtime.getTime() < CACHE_TTL_MS) {
      return true;
    }
  } catch {
    // no cache
  }
  return false;
}

async function findKeychainServices(): Promise<string[]> {
  try {
    const cmd = new Deno.Command("security", {
      args: ["dump-keychain"],
      stdout: "piped",
      stderr: "null",
    });
    const output = await cmd.output();
    const text = new TextDecoder().decode(output.stdout);
    const services: string[] = [];
    for (const m of text.matchAll(/"svce"<blob>="(Claude Code-credentials[^"]*)"/g)) {
      if (!services.includes(m[1])) services.push(m[1]);
    }
    return services;
  } catch {
    return [];
  }
}

async function getTokenFromKeychain(): Promise<string | null> {
  try {
    const services = await findKeychainServices();
    for (const svc of services) {
      try {
        const cmd = new Deno.Command("security", {
          args: ["find-generic-password", "-s", svc, "-w"],
          stdout: "piped",
          stderr: "null",
        });
        const output = await cmd.output();
        if (!output.success) continue;
        const raw = new TextDecoder().decode(output.stdout).trim();
        const creds: KeychainCredentials = JSON.parse(raw);
        const oauth = creds.claudeAiOauth;
        if (!oauth?.accessToken) continue;
        if (oauth.expiresAt && oauth.expiresAt < Date.now()) continue;
        return oauth.accessToken;
      } catch {
        continue;
      }
    }
    return null;
  } catch {
    return null;
  }
}

async function getToken(): Promise<string | null> {
  // Try env var first (may be available in some hook contexts)
  const envToken = Deno.env.get("CLAUDE_CODE_SESSION_ACCESS_TOKEN");
  if (envToken) return envToken;
  // Fall back to macOS keychain
  return await getTokenFromKeychain();
}

async function fetchUsage(token: string): Promise<UsageResponse | null> {
  try {
    const resp = await fetch("https://api.anthropic.com/api/oauth/usage", {
      headers: {
        Authorization: `Bearer ${token}`,
        "anthropic-beta": "oauth-2025-04-20",
      },
      signal: AbortSignal.timeout(5000),
    });
    return await resp.json();
  } catch {
    return null;
  }
}

async function main() {
  // Drain stdin (hook requirement)
  await readAll(Deno.stdin);

  if (await isCacheFresh()) {
    Deno.exit(0);
  }

  const token = await getToken();
  if (!token) {
    Deno.exit(0);
  }

  const usage = await fetchUsage(token);
  if (!usage || usage.type === "error" || usage.error) {
    Deno.exit(0);
  }

  const cache = {
    fetched_at: Math.floor(Date.now() / 1000),
    five_hour: {
      utilization: Math.round(usage.five_hour?.utilization ?? 0),
      resets_at: usage.five_hour?.resets_at ?? "",
    },
    seven_day: {
      utilization: Math.round(usage.seven_day?.utilization ?? 0),
      resets_at: usage.seven_day?.resets_at ?? "",
    },
  };

  try {
    await Deno.writeTextFile(CACHE_FILE, JSON.stringify(cache));
  } catch {
    // ignore
  }
}

main().catch(() => {}).finally(() => Deno.exit(0));
