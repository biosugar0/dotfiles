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
  worktree?: {
    name?: string;
    path?: string;
    branch?: string;
    original_repo_dir?: string;
  };
  session_id?: string;
  transcript_path?: string;
};

type UsageCache = {
  fetched_at: number;
  five_hour: { utilization: number; resets_at: string };
  seven_day: { utilization: number; resets_at: string };
};

type SummaryCache = {
  summary: string;
  updated_at: number;
};

const SUMMARY_CACHE_DIR = "/tmp/claude-session-summaries";
const SUMMARY_CACHE_TTL_MS = 300_000; // 5min

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

async function getFirstUserMessage(transcriptPath: string): Promise<string> {
  try {
    const file = await Deno.open(transcriptPath, { read: true });
    const decoder = new TextDecoder();
    let buffer = "";
    const chunk = new Uint8Array(4096);
    // Read up to 64KB to find first user message
    for (let total = 0; total < 65536; ) {
      const n = await file.read(chunk);
      if (!n) break;
      total += n;
      buffer += decoder.decode(chunk.subarray(0, n), { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const obj = JSON.parse(line);
          if (obj.type === "user" && typeof obj.message?.content === "string") {
            file.close();
            return obj.message.content.slice(0, 500);
          }
        } catch {
          continue;
        }
      }
    }
    file.close();
    return "";
  } catch {
    return "";
  }
}

async function getRecentUserMessages(
  transcriptPath: string,
  maxMessages = 3,
): Promise<string[]> {
  try {
    const stat = await Deno.stat(transcriptPath);
    const fileSize = stat.size ?? 0;
    // Read last 64KB
    const readSize = Math.min(fileSize, 65536);
    const file = await Deno.open(transcriptPath, { read: true });
    await file.seek(-readSize, Deno.SeekMode.End);
    const buf = new Uint8Array(readSize);
    await file.read(buf);
    file.close();
    const text = new TextDecoder().decode(buf);
    const messages: string[] = [];
    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      try {
        const obj = JSON.parse(line);
        if (obj.type === "user" && typeof obj.message?.content === "string") {
          messages.push(obj.message.content.slice(0, 200));
        }
      } catch {
        continue;
      }
    }
    return messages.slice(-maxMessages);
  } catch {
    return [];
  }
}

async function summarizeWithHaiku(
  firstMessage: string,
  recentMessages: string[],
  token: string,
): Promise<string> {
  try {
    const recentPart = recentMessages.length > 0
      ? `\n\n最近の指示:\n${recentMessages.map((m, i) => `${i + 1}. ${m}`).join("\n")}`
      : "";
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "anthropic-version": "2023-06-01",
        "anthropic-beta": "oauth-2025-04-20",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 64,
        messages: [
          {
            role: "user",
            content: `セッション情報から「メインの作業:今の具体的な作業」形式で40文字以内の日本語で要約せよ。
ルール:
- 必ず「メインの作業:具体的な作業内容」のコロン区切り形式にする
- コロンの前=最初の指示から判断するセッション全体のテーマ(短く)
- コロンの後=最近の指示から判断する今まさにやっていること(「〜中」で終える)
- 接頭辞・装飾不要
良い例: "statusline改善:要約プロンプト調整中", "OAuth対応:キャッシュTTL変更中", "バグ修正:ログ出力のフォーマット修正中"
悪い例: "ステータスライン機能追加", "セッション管理の改善"

最初の指示:
${firstMessage}${recentPart}`,
          },
        ],
      }),
      signal: AbortSignal.timeout(5000),
    });
    const data = await resp.json();
    const text = data?.content?.[0]?.text?.trim() ?? "";
    return text.slice(0, 40);
  } catch {
    return "";
  }
}

async function getSessionSummary(
  sessionId: string,
  transcriptPath: string,
): Promise<string> {
  const cacheFile = `${SUMMARY_CACHE_DIR}/${sessionId}.json`;
  try {
    await Deno.mkdir(SUMMARY_CACHE_DIR, { recursive: true });
  } catch { /* ignore */ }

  // Check cache with TTL
  try {
    const cached: SummaryCache = JSON.parse(
      await Deno.readTextFile(cacheFile),
    );
    if (cached.summary && Date.now() - cached.updated_at < SUMMARY_CACHE_TTL_MS) {
      return cached.summary;
    }
    // Stale — try refresh, fall back to stale
    const fresh = await refreshSummary(transcriptPath, cacheFile);
    return fresh || cached.summary || "";
  } catch { /* no cache */ }

  // No cache — generate fresh
  return await refreshSummary(transcriptPath, cacheFile);
}

async function refreshSummary(
  transcriptPath: string,
  cacheFile: string,
): Promise<string> {
  const [firstMsg, recentMsgs] = await Promise.all([
    getFirstUserMessage(transcriptPath),
    getRecentUserMessages(transcriptPath),
  ]);
  if (!firstMsg) return "";

  const token = await getTokenFromKeychain();
  if (!token) return "";

  const summary = await summarizeWithHaiku(firstMsg, recentMsgs, token);
  if (summary) {
    const cache: SummaryCache = { summary, updated_at: Date.now() };
    try {
      await Deno.writeTextFile(cacheFile, JSON.stringify(cache));
    } catch { /* ignore */ }
  }
  return summary;
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

  const [gitBranch, usageCache, sessionSummary] = await Promise.all([
    input.worktree?.branch
      ? Promise.resolve(input.worktree.branch)
      : getGitBranch(input.workspace?.current_dir),
    getUsage(),
    input.session_id && input.transcript_path
      ? getSessionSummary(input.session_id, input.transcript_path)
      : Promise.resolve(""),
  ]);

  const sep = `${GRAY} │ ${RESET}`;

  // Line 1: model | dir | lines | branch
  const infoParts = [`${CYAN}󰛩  ${model}${RESET}`, `  ${dir}`];
  if (linesAdded || linesRemoved) {
    infoParts.push(`✏️ +${linesAdded}/-${linesRemoved}`);
  }
  if (gitBranch) {
    const branchLabel = input.worktree?.name
      ? `󰘬  ${gitBranch} ${GRAY}(wt: ${input.worktree.name})${RESET}`
      : `󰘬  ${gitBranch}`;
    infoParts.push(branchLabel);
  }
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

  // Session summary (separate line)
  if (sessionSummary) {
    console.log(`${YELLOW}📋 ${sessionSummary}${RESET}`);
  }

  // Rate limit
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
