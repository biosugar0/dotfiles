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
    total_lines_added?: number;
    total_lines_removed?: number;
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

// RGB colors (from article: better visibility)
const RESET = "\x1b[0m";
const GREEN = "\x1b[38;2;151;201;195m";
const YELLOW = "\x1b[38;2;229;192;123m";
const RED = "\x1b[38;2;224;108;117m";
const GRAY = "\x1b[38;2;74;88;92m";
const CYAN = "\x1b[36m";

const USAGE_CACHE_FILE = "/tmp/claude-usage-cache.json";
const USAGE_CACHE_TTL_MS = 360_000; // 6min
const USAGE_CACHE_STALE_MS = 1_800_000; // 30min: show stale data

function colorForPct(pct: number): string {
  return pct >= 80 ? RED : pct >= 50 ? YELLOW : GREEN;
}

function buildBar(pct: number): string {
  const filled = Math.round((pct * 10) / 100);
  const empty = 10 - filled;
  const color = colorForPct(pct);
  return `${color}${"▰".repeat(filled)}${"▱".repeat(empty)} ${pct}%${RESET}`;
}

function formatDuration(ms: number): string {
  const sec = Math.floor(ms / 1000);
  return `${Math.floor(sec / 60)}m${sec % 60}s`;
}

function visibleLength(s: string): number {
  return s.replace(/\x1b\[[0-9;]*m/g, "").length;
}

async function getGitBranch(cwd?: string): Promise<string> {
  try {
    const opts = cwd ? { cwd } : undefined;
    const { success } = await new Deno.Command("git", {
      args: ["rev-parse"],
      stdout: "null",
      stderr: "null",
      ...opts,
    }).output();
    if (!success) return "";

    const { stdout } = await new Deno.Command("git", {
      args: ["branch", "--show-current"],
      stdout: "piped",
      stderr: "null",
      ...opts,
    }).output();
    const branch = new TextDecoder().decode(stdout).trim();
    if (branch) return branch;

    const hashResult = await new Deno.Command("git", {
      args: ["rev-parse", "--short", "HEAD"],
      stdout: "piped",
      stderr: "null",
      ...opts,
    }).output();
    return new TextDecoder().decode(hashResult.stdout).trim() || "";
  } catch {
    return "";
  }
}

async function findKeychainServices(): Promise<string[]> {
  try {
    const output = await new Deno.Command("security", {
      args: ["dump-keychain"],
      stdout: "piped",
      stderr: "null",
    }).output();
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
    for (const svc of await findKeychainServices()) {
      try {
        const output = await new Deno.Command("security", {
          args: ["find-generic-password", "-s", svc, "-w"],
          stdout: "piped",
          stderr: "null",
        }).output();
        if (!output.success) continue;
        const raw = new TextDecoder().decode(output.stdout).trim();
        const creds = JSON.parse(raw);
        const oauth = creds?.claudeAiOauth;
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

async function fetchUsage(): Promise<UsageCache | null> {
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

async function getUsage(): Promise<UsageCache | null> {
  try {
    const stat = await Deno.stat(USAGE_CACHE_FILE);
    const age = stat.mtime ? Date.now() - stat.mtime.getTime() : Infinity;
    if (age <= USAGE_CACHE_TTL_MS) {
      return JSON.parse(await Deno.readTextFile(USAGE_CACHE_FILE));
    }
    // Cache stale — try refresh, fall back to stale data
    const fresh = await fetchUsage();
    if (fresh) return fresh;
    if (age <= USAGE_CACHE_STALE_MS) {
      return JSON.parse(await Deno.readTextFile(USAGE_CACHE_FILE));
    }
    return null;
  } catch {
    // No cache — try fetch
    return await fetchUsage();
  }
}

function formatResetTime(isoStr: string): string {
  if (!isoStr) return "";
  try {
    const d = new Date(isoStr);
    return new Intl.DateTimeFormat("ja-JP", {
      timeZone: "Asia/Tokyo",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(d);
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
  const linesAdded = input.cost?.total_lines_added ?? 0;
  const linesRemoved = input.cost?.total_lines_removed ?? 0;
  const exceeds200k = input.exceeds_200k_tokens ?? false;

  const [gitBranch, usageCache] = await Promise.all([
    getGitBranch(input.workspace?.current_dir),
    getUsage(),
  ]);

  const sep = `${GRAY} │ ${RESET}`;

  // Line 1: model | dir | lines | branch
  const infoParts = [`${CYAN}󰛩  ${model}${RESET}`, `  ${dir}`];
  if (linesAdded || linesRemoved) {
    infoParts.push(`✏️ +${linesAdded}/-${linesRemoved}`);
  }
  if (gitBranch) infoParts.push(`󰘬  ${gitBranch}`);
  const infoStr = infoParts.join(sep);

  // Line 2: context bar | duration | 200k warning
  const warn = exceeds200k ? ` ${RED}⚠ 200k+${RESET}` : "";
  const contextStr = `${buildBar(pct)}${warn}${sep}󰥔 ${formatDuration(duration)}`;

  let cols = 80;
  try {
    cols = Deno.consoleSize().columns;
  } catch {
    cols = parseInt(Deno.env.get("COLUMNS") ?? "80", 10) || 80;
  }
  const singleLine = `${infoStr}${sep}${contextStr}`;

  if (visibleLength(singleLine) <= cols) {
    console.log(singleLine);
  } else {
    console.log(infoStr);
    console.log(contextStr);
  }

  // Lines 3-4: rate limit
  if (usageCache) {
    const fiveReset = formatResetTime(usageCache.five_hour.resets_at);
    const sevenReset = formatResetTime(usageCache.seven_day.resets_at);
    const fiveColor = colorForPct(usageCache.five_hour.utilization);
    const sevenColor = colorForPct(usageCache.seven_day.utilization);
    console.log(
      `${fiveColor}⏱ 5h${RESET}  ${buildBar(usageCache.five_hour.utilization)}${fiveReset ? `  ${GRAY}Resets ${fiveReset}${RESET}` : ""}`,
    );
    console.log(
      `${sevenColor}📅 7d${RESET}  ${buildBar(usageCache.seven_day.utilization)}${sevenReset ? `  ${GRAY}Resets ${sevenReset}${RESET}` : ""}`,
    );
  }
}

if (import.meta.main) {
  main().catch(() => Deno.exit(1));
}
