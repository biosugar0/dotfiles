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
  rate_limits?: {
    five_hour?: { used_percentage: number; resets_at: number };
    seven_day?: { used_percentage: number; resets_at: number };
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
  session_name?: string;
  transcript_path?: string;
};

type SummaryCache = {
  summary: string;
  slug: string;
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

function colorForPct(pct: number): string {
  return pct >= 80 ? RED : pct >= 50 ? YELLOW : GREEN;
}

function buildBar(pct: number): string {
  const filled = Math.round((pct * 5) / 100);
  const empty = 5 - filled;
  const color = colorForPct(pct);
  return `${color}${"▰".repeat(filled)}${"▱".repeat(empty)} ${pct}%${RESET}`;
}

function formatDuration(ms: number): string {
  const totalMin = Math.floor(ms / 60000);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  return h > 0 ? `${h}h${m}m` : `${m}m`;
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
  const envToken = Deno.env.get("CLAUDE_CODE_OAUTH_TOKEN");
  if (envToken) return envToken;
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

function extractUserText(content: unknown): string {
  if (typeof content === "string") return content;
  // Array content is typically tool_result blocks, not human input — skip
  return "";
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
          if (obj.type === "user") {
            const text = extractUserText(obj.message?.content);
            if (text && text.length >= 10) {
              file.close();
              return text.slice(0, 500);
            }
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
    // Read last 256KB (tool_result blocks can be large, need enough range to find human messages)
    const readSize = Math.min(fileSize, 262144);
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
        if (obj.type === "user") {
          const text = extractUserText(obj.message?.content);
          if (text) messages.push(text.slice(0, 200));
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
): Promise<{ summary: string; slug: string }> {
  const empty = { summary: "", slug: "" };
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
        max_tokens: 80,
        messages: [
          {
            role: "user",
            content: `セッション情報から2行で出力せよ。

1行目: 40文字以内の日本語要約 (<テーマ>:<直近論点>)
2行目: 2-3語の英語kebab-case slug (例: statusline-session-title, oauth-token-fix)

要約ルール:
- テーマ = セッション全体の主題(短い名詞句)
- 直近論点 = 最近の指示から判断する直近の具体論点
- 進捗や次の行動は推測しない
- 抽象語を避け、機能名や設定名を優先
- 接頭辞・装飾不要
- 情報不足なら「-」とだけ出力

slugルール:
- 英語のkebab-case、2-3語
- セッションの主題を端的に表す
- 例: hook-session-title, changelog-review, statusline-summary

良い要約例: "statusline改善:要約形式の見直し", "OAuth対応:キャッシュTTLの扱い"
悪い要約例: "statusline改善:調整中", "dotfiles改善:いろいろ修正"

最初の指示:
${firstMessage}${recentPart}`,
          },
        ],
      }),
      signal: AbortSignal.timeout(5000),
    });
    const data = await resp.json();
    const text = data?.content?.[0]?.text?.trim() ?? "";
    const lines = text.split("\n").map((l: string) => l.trim()).filter(Boolean);
    // Parse summary (line 1)
    const summaryLine = lines[0] ?? "";
    if (!summaryLine || summaryLine === "-" || summaryLine.includes("理由") || summaryLine.includes("判断できません") || summaryLine.length > 60 || (!summaryLine.includes(":") && !summaryLine.includes("："))) return empty;
    const summary = summaryLine.replace(/：/g, ":").slice(0, 50);
    // Parse slug (line 2)
    const rawSlug = (lines[1] ?? "").toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 30);
    const slug = rawSlug || "";
    return { summary, slug };
  } catch {
    return empty;
  }
}

const SUMMARY_IDLE_MS = 600_000; // 10min: stop refreshing after idle

async function getSessionSummary(
  sessionId: string,
  transcriptPath: string,
): Promise<string> {
  const cacheFile = `${SUMMARY_CACHE_DIR}/${sessionId}.json`;
  try {
    await Deno.mkdir(SUMMARY_CACHE_DIR, { recursive: true });
  } catch { /* ignore */ }

  // Check if session is idle (transcript not updated for 10min)
  let idle = false;
  try {
    const stat = await Deno.stat(transcriptPath);
    if (stat.mtime && Date.now() - stat.mtime.getTime() > SUMMARY_IDLE_MS) {
      idle = true;
    }
  } catch { /* ignore */ }

  // Check cache with TTL
  try {
    const cached: SummaryCache = JSON.parse(
      await Deno.readTextFile(cacheFile),
    );
    if (cached.summary && (idle || Date.now() - cached.updated_at < SUMMARY_CACHE_TTL_MS)) {
      return cached.summary;
    }
    if (idle) return cached.summary || "";
    // Stale — try refresh, fall back to stale
    const fresh = await refreshSummary(transcriptPath, cacheFile);
    return fresh || cached.summary || "";
  } catch { /* no cache */ }

  if (idle) return "";
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

  const result = await summarizeWithHaiku(firstMsg, recentMsgs, token);
  if (result.summary) {
    const cache: SummaryCache = { summary: result.summary, slug: result.slug, updated_at: Date.now() };
    try {
      await Deno.writeTextFile(cacheFile, JSON.stringify(cache));
    } catch { /* ignore */ }
  }
  return result.summary;
}

function formatResetTime(epochSec: number): string {
  if (!epochSec) return "";
  try {
    const d = new Date(epochSec * 1000);
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

  const [gitBranch, sessionSummary] = await Promise.all([
    input.worktree?.branch
      ? Promise.resolve(input.worktree.branch)
      : getGitBranch(input.workspace?.current_dir),
    input.session_id && input.transcript_path
      ? getSessionSummary(input.session_id, input.transcript_path)
      : Promise.resolve(""),
  ]);
  const rateLimits = input.rate_limits;

  const sep = `${GRAY} │ ${RESET}`;

  // Line 1: Session summary with session_name as fallback
  if (sessionSummary) {
    console.log(`${YELLOW}📋 ${sessionSummary}${RESET}`);
  } else if (input.session_name) {
    console.log(`${YELLOW}📋 ${input.session_name}${RESET}`);
  }

  // Line 2: model | dir | lines | branch | context bar | duration
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
  infoParts.push(buildBar(pct));
  infoParts.push(`󰥔 ${formatDuration(duration)}`);
  const infoStr = infoParts.join(sep);

  let cols = 80;
  try {
    cols = Deno.consoleSize().columns;
  } catch {
    cols = parseInt(Deno.env.get("COLUMNS") ?? "80", 10) || 80;
  }

  if (visibleLength(infoStr) <= cols) {
    console.log(infoStr);
  } else {
    // Fallback: split into two lines if too wide
    const line2a = infoParts.slice(0, -2).join(sep);
    const line2b = `${buildBar(pct)}${sep}󰥔 ${formatDuration(duration)}`;
    console.log(line2a);
    console.log(line2b);
  }

  // 200k warning (only when context > 80%)
  if (exceeds200k && pct >= 80) {
    console.log(`${RED}⚠ 200k+ context — consider compacting${RESET}`);
  }

  // Line 4: Rate limit (compressed to 1 line)
  if (rateLimits?.five_hour || rateLimits?.seven_day) {
    const fivePct = Math.round(rateLimits.five_hour?.used_percentage ?? 0);
    const sevenPct = Math.round(rateLimits.seven_day?.used_percentage ?? 0);
    const fiveColor = colorForPct(fivePct);
    const sevenColor = colorForPct(sevenPct);
    const fiveBar = buildBar(fivePct);
    const sevenBar = buildBar(sevenPct);
    // Show reset time for whichever is higher utilization
    const showReset = fivePct >= sevenPct
      ? rateLimits.five_hour : rateLimits.seven_day;
    const resetStr = showReset?.resets_at ? formatResetTime(showReset.resets_at) : "";
    console.log(
      `${fiveColor}⏱ 5h${RESET} ${fiveBar}${sep}${sevenColor}📅 7d${RESET} ${sevenBar}${resetStr ? `  ${GRAY}Resets ${resetStr}${RESET}` : ""}`,
    );
  }

  // Write session health for Stop/PostCompact hooks to consume
  if (input.session_id) {
    try {
      const healthDir = "/tmp/claude-session-health";
      await Deno.mkdir(healthDir, { recursive: true });
      const healthFile = `${healthDir}/${input.session_id}.json`;
      const health = {
        session_id: input.session_id,
        context_pct: pct,
        exceeds_200k: exceeds200k,
        duration_ms: duration,
        updated_at: new Date().toISOString(),
      };
      await Deno.writeTextFile(healthFile, JSON.stringify(health));
    } catch {
      // ignore — statusline should never fail
    }
  }
}

if (import.meta.main) {
  main().catch(() => Deno.exit(1));
}
