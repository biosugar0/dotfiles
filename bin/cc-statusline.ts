#!/usr/bin/env -S deno run --allow-read --allow-run --allow-env --allow-write --allow-net

import { readAll } from "jsr:@std/io@0.224/read-all";

type StatusLineInput = {
  model?: { id?: string; display_name?: string };
  workspace?: { current_dir?: string; project_dir?: string };
  context_window?: {
    used_percentage?: number;
    remaining_percentage?: number;
    context_window_size?: number;
    current_usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
    };
  };
  cost?: {
    total_cost_usd?: number;
    total_duration_ms?: number;
    total_api_duration_ms?: number;
  };
  exceeds_200k_tokens?: boolean;
  vim?: { mode?: string };
  agent?: { name?: string };
};

type UsageCache = {
  fetched_at: number;
  five_hour: { utilization: number; resets_at: string };
  seven_day: { utilization: number; resets_at: string };
};

const RESET = "\x1b[0m";
const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";

const CACHE_FILE = "/tmp/cc-statusline-git-cache";
const CACHE_MAX_AGE_MS = 5000;
const USAGE_CACHE_FILE = "/tmp/claude-usage-cache.json";
const USAGE_CACHE_MAX_AGE_MS = 600_000; // 10min: show even if stop hook hasn't run recently

async function getGitBranch(): Promise<string> {
  try {
    const stat = await Deno.stat(CACHE_FILE).catch(() => null);
    if (stat?.mtime && Date.now() - stat.mtime.getTime() < CACHE_MAX_AGE_MS) {
      return await Deno.readTextFile(CACHE_FILE);
    }
  } catch {
    // cache miss
  }

  const branch = await fetchGitBranch();
  try {
    await Deno.writeTextFile(CACHE_FILE, branch);
  } catch {
    // ignore cache write failure
  }
  return branch;
}

async function fetchGitBranch(): Promise<string> {
  try {
    const { success } = await new Deno.Command("git", {
      args: ["rev-parse"],
      stdout: "null",
      stderr: "null",
    }).output();
    if (!success) return "";

    const { stdout } = await new Deno.Command("git", {
      args: ["branch", "--show-current"],
      stdout: "piped",
      stderr: "null",
    }).output();
    const branch = new TextDecoder().decode(stdout).trim();
    if (branch) return branch;

    const hashResult = await new Deno.Command("git", {
      args: ["rev-parse", "--short", "HEAD"],
      stdout: "piped",
      stderr: "null",
    }).output();
    const hash = new TextDecoder().decode(hashResult.stdout).trim();
    if (hash) return `HEAD (${hash})`;
  } catch {
    // ignore
  }
  return "";
}

function buildContextBar(pct: number): string {
  const width = 10;
  const filled = Math.round((pct * width) / 100);
  const empty = width - filled;
  const color = pct >= 90 ? RED : pct >= 70 ? YELLOW : GREEN;
  return `${color}${"▰".repeat(filled)}${"▱".repeat(empty)} ${pct}%${RESET}`;
}

function formatDuration(ms: number): string {
  const sec = Math.floor(ms / 1000);
  return `${Math.floor(sec / 60)}m${sec % 60}s`;
}

// ANSI escape codeを除いた可視文字幅を計算
function visibleLength(s: string): number {
  return s.replace(/\x1b\[[0-9;]*m/g, "").length;
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
    // Try each service, prefer one with valid (non-expired) token
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
        const creds = JSON.parse(raw);
        const oauth = creds?.claudeAiOauth;
        if (!oauth?.accessToken) continue;
        // Check expiry
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

async function fetchAndCacheUsage(): Promise<UsageCache | null> {
  try {
    const token = await getTokenFromKeychain();
    if (!token) return null;
    const resp = await fetch("https://api.anthropic.com/api/oauth/usage", {
      headers: {
        Authorization: `Bearer ${token}`,
        "anthropic-beta": "oauth-2025-04-20",
      },
      signal: AbortSignal.timeout(3000),
    });
    const data = await resp.json();
    if (data?.error || data?.type === "error") return null;
    const cache: UsageCache = {
      fetched_at: Math.floor(Date.now() / 1000),
      five_hour: {
        utilization: Math.round(data.five_hour?.utilization ?? 0),
        resets_at: data.five_hour?.resets_at ?? "",
      },
      seven_day: {
        utilization: Math.round(data.seven_day?.utilization ?? 0),
        resets_at: data.seven_day?.resets_at ?? "",
      },
    };
    await Deno.writeTextFile(USAGE_CACHE_FILE, JSON.stringify(cache));
    return cache;
  } catch {
    return null;
  }
}

// Lock file to prevent concurrent fetches from multiple statusline invocations
const USAGE_LOCK_FILE = "/tmp/claude-usage-cache.lock";

async function tryAcquireLock(): Promise<boolean> {
  try {
    const stat = await Deno.stat(USAGE_LOCK_FILE).catch(() => null);
    if (stat?.mtime && Date.now() - stat.mtime.getTime() < 30_000) return false;
    await Deno.writeTextFile(USAGE_LOCK_FILE, String(Date.now()));
    return true;
  } catch {
    return false;
  }
}

async function releaseLock(): Promise<void> {
  try { await Deno.remove(USAGE_LOCK_FILE); } catch { /* ignore */ }
}

async function readUsageCache(): Promise<UsageCache | null> {
  try {
    const stat = await Deno.stat(USAGE_CACHE_FILE);
    const age = stat.mtime ? Date.now() - stat.mtime.getTime() : Infinity;
    if (age <= USAGE_CACHE_MAX_AGE_MS) {
      const text = await Deno.readTextFile(USAGE_CACHE_FILE);
      return JSON.parse(text);
    }
    // Cache is stale - try to refresh inline
    if (await tryAcquireLock()) {
      try {
        const fresh = await fetchAndCacheUsage();
        if (fresh) return fresh;
      } finally {
        await releaseLock();
      }
    }
    // Return stale data if not too old (30min)
    if (age <= 1_800_000) {
      const text = await Deno.readTextFile(USAGE_CACHE_FILE);
      return JSON.parse(text);
    }
    return null;
  } catch {
    // No cache at all - try to fetch
    if (await tryAcquireLock()) {
      try {
        return await fetchAndCacheUsage();
      } finally {
        await releaseLock();
      }
    }
    return null;
  }
}

function buildRateLimitBar(pct: number): string {
  const width = 10;
  const filled = Math.round((pct * width) / 100);
  const empty = width - filled;
  const color = pct >= 80 ? RED : pct >= 50 ? YELLOW : GREEN;
  return `${color}${"▰".repeat(filled)}${"▱".repeat(empty)} ${pct}%${RESET}`;
}

function formatResetTime(isoStr: string): string {
  if (!isoStr) return "";
  try {
    const d = new Date(isoStr);
    const fmt = new Intl.DateTimeFormat("ja-JP", {
      timeZone: "Asia/Tokyo",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    });
    return fmt.format(d);
  } catch {
    return "";
  }
}

async function main() {
  const stdin = await readAll(Deno.stdin);
  const input: StatusLineInput = JSON.parse(new TextDecoder().decode(stdin));

  const model = input.model?.display_name ?? "Unknown";
  const dir = input.workspace?.current_dir?.split("/").pop() ?? ".";
  const pct = Math.round(input.context_window?.used_percentage ?? 0);
  const duration = input.cost?.total_duration_ms ?? 0;
  const exceeds200k = input.exceeds_200k_tokens ?? false;
  const [gitBranch, usageCache] = await Promise.all([
    getGitBranch(),
    readUsageCache(),
  ]);

  const infoParts = [`${CYAN}󰛩  ${model}${RESET}`, `  ${dir}`];
  if (gitBranch) infoParts.push(`󰘬  ${gitBranch}`);
  const infoStr = infoParts.join(" | ");

  const warn = exceeds200k ? ` ${RED}⚠ 200k+${RESET}` : "";
  const contextParts = [
    `${buildContextBar(pct)}${warn}`,
    `󰥔 ${formatDuration(duration)}`,
  ];
  const contextStr = contextParts.join(" | ");

  let cols = 80;
  try {
    cols = Deno.consoleSize().columns;
  } catch {
    cols = parseInt(Deno.env.get("COLUMNS") ?? "80", 10) || 80;
  }
  const singleLine = `${infoStr} | ${contextStr}`;

  if (visibleLength(singleLine) <= cols) {
    console.log(singleLine);
  } else {
    console.log(infoStr);
    console.log(contextStr);
  }

  if (usageCache) {
    const fiveReset = formatResetTime(usageCache.five_hour.resets_at);
    const sevenReset = formatResetTime(usageCache.seven_day.resets_at);
    const fiveLine = `⏱ 5h ${buildRateLimitBar(usageCache.five_hour.utilization)}${fiveReset ? ` | Resets ${fiveReset}` : ""}`;
    const sevenLine = `📅 7d ${buildRateLimitBar(usageCache.seven_day.utilization)}${sevenReset ? ` | Resets ${sevenReset}` : ""}`;
    console.log(fiveLine);
    console.log(sevenLine);
  }
}

if (import.meta.main) {
  main().catch(() => Deno.exit(1));
}
