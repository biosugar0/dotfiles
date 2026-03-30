#!/usr/bin/env -S deno run --allow-read --allow-run --allow-env --allow-write --allow-net

/**
 * SessionStart Hook (TS版)
 *
 * compact matcher: assets.json + compact_summary.md → Haiku(tool_use) → 構造化情報注入
 * startup|resume matcher: git状態 + 軽量コンテキスト注入
 */

import Anthropic from "npm:@anthropic-ai/sdk";
import { readAll } from "jsr:@std/io@0.224/read-all";
import {
  getGitBranch,
  getTokenFromKeychain,
} from "./lib/session-context.ts";

interface SessionStartInput {
  source?: string;
  session_id?: string;
  transcript_path?: string;
}

interface AssetsJson {
  schema_version: number;
  session_id: string;
  created_at: string;
  project_dir: string;
  trigger: string;
  custom_instructions: string | null;
  ttl_hours: number;
  git: {
    branch: string;
    head_sha: string;
    dirty_files: number;
  };
  recent_user_messages: string[];
  files_touched: string[];
  last_assistant_text: string;
  transcript_stats: {
    total_entries: number;
  };
}

interface CompactSupplementInput {
  next_steps: string[];
  decisions: Array<{ decision: string; reason: string }>;
  open_questions: string[];
  resume_context: string;
}

const COMPACT_SUPPLEMENT_TOOL: Anthropic.Tool = {
  name: "compact_supplement",
  description:
    "Generate structured supplement info that is missing from compact_summary.",
  input_schema: {
    type: "object" as const,
    properties: {
      next_steps: {
        type: "array",
        items: { type: "string" },
        description: "具体的な次のステップ（compact_summaryにないもの）",
      },
      decisions: {
        type: "array",
        items: {
          type: "object",
          properties: {
            decision: { type: "string", description: "決定事項" },
            reason: { type: "string", description: "理由" },
          },
          required: ["decision", "reason"],
        },
        description: "決定事項（compact_summaryにないもの）",
      },
      open_questions: {
        type: "array",
        items: { type: "string" },
        description: "未確定点・未解決の質問",
      },
      resume_context: {
        type: "string",
        description: "compact_summaryを補完する5-10行のコンテキスト",
      },
    },
    required: ["next_steps", "decisions", "open_questions", "resume_context"],
  },
};

const SYSTEM_PROMPT = `You analyze a pre-compaction session snapshot (assets.json) and the post-compaction compact_summary.
Your job: identify structured information present in the session snapshot but MISSING from compact_summary.

Rules:
- Only output information that adds value beyond what compact_summary already contains
- Be specific and actionable (file paths, function names, concrete decisions)
- If compact_summary already covers everything, return minimal/empty arrays
- Keep resume_context to 5-10 lines
- Output in Japanese

Call compact_supplement with your analysis.`;

function outputHookResult(context: string): void {
  const result = {
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: context,
    },
  };
  console.log(JSON.stringify(result));
}

async function readJsonFile<T>(path: string): Promise<T | null> {
  try {
    return JSON.parse(await Deno.readTextFile(path));
  } catch {
    return null;
  }
}

async function readTextFileSafe(path: string): Promise<string> {
  try {
    return await Deno.readTextFile(path);
  } catch {
    return "";
  }
}

function isExpired(createdAt: string, ttlHours: number): boolean {
  const created = new Date(createdAt).getTime();
  if (isNaN(created)) return true;
  return Date.now() - created > ttlHours * 3600_000;
}

function buildFallbackMarkdown(assets: AssetsJson, maxLines = 15): string {
  const lines: string[] = [
    "## Compact Recovery (Haiku unavailable)",
    "",
    `- Branch: ${assets.git.branch || "unknown"}`,
    `- HEAD: ${assets.git.head_sha.slice(0, 8) || "unknown"}`,
    `- Dirty files: ${assets.git.dirty_files}`,
  ];

  if (assets.recent_user_messages.length > 0) {
    lines.push("", "### Recent Messages");
    for (const msg of assets.recent_user_messages.slice(0, 3)) {
      lines.push(`- ${msg.slice(0, 100)}`);
    }
  }

  return lines.slice(0, maxLines).join("\n");
}

function formatSupplement(data: CompactSupplementInput): string {
  const parts: string[] = [];
  const nextSteps = data.next_steps ?? [];
  const decisions = data.decisions ?? [];
  const openQuestions = data.open_questions ?? [];

  if (data.resume_context) {
    parts.push("## Compact Supplement", "", data.resume_context);
  }

  if (nextSteps.length > 0) {
    parts.push("", "### Next Steps");
    for (const step of nextSteps) {
      parts.push(`- ${step}`);
    }
  }

  if (decisions.length > 0) {
    parts.push("", "### Decisions");
    for (const d of decisions) {
      parts.push(`- ${d.decision}（理由: ${d.reason}）`);
    }
  }

  if (openQuestions.length > 0) {
    parts.push("", "### Open Questions");
    for (const q of openQuestions) {
      parts.push(`- ${q}`);
    }
  }

  return parts.join("\n");
}

async function getApiClient(): Promise<Anthropic | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  const sessionToken = Deno.env.get("CLAUDE_CODE_SESSION_ACCESS_TOKEN");
  const keychainToken =
    !apiKey && !sessionToken ? await getTokenFromKeychain() : null;

  if (!apiKey && !sessionToken && !keychainToken) return null;

  return apiKey
    ? new Anthropic({ apiKey })
    : new Anthropic({
        authToken: sessionToken || keychainToken,
        apiKey: null,
        defaultHeaders: { "anthropic-beta": "oauth-2025-04-20" },
      });
}

async function handleCompact(
  sessionId: string,
  projectDir: string,
): Promise<void> {
  const stateDir = `${projectDir}/ai/state/${sessionId}`;
  const assets = await readJsonFile<AssetsJson>(`${stateDir}/assets.json`);

  if (!assets || isExpired(assets.created_at, assets.ttl_hours)) {
    // No assets or expired — skip supplement injection
    return;
  }

  const compactSummary = await readTextFileSafe(
    `${stateDir}/compact_summary.md`,
  );

  // Try Haiku call
  try {
    const client = await getApiClient();
    if (!client) {
      await Deno.stderr.write(
        new TextEncoder().encode(
          "SessionStart(compact): No API credentials found (no ANTHROPIC_API_KEY, no session token, no keychain token)\n",
        ),
      );
      if (compactSummary) return; // compact_summary exists, no supplement needed
      outputHookResult(buildFallbackMarkdown(assets));
      return;
    }

    const userContent = [
      "## assets.json (pre-compaction snapshot)",
      "```json",
      JSON.stringify(assets, null, 2),
      "```",
      "",
      "## compact_summary (post-compaction)",
      compactSummary || "(compact_summary not available)",
    ].join("\n");

    const response = await client.messages.create(
      {
        model: "claude-haiku-4-5-20251001",
        max_tokens: 512,
        system: SYSTEM_PROMPT,
        tools: [COMPACT_SUPPLEMENT_TOOL],
        tool_choice: { type: "tool", name: "compact_supplement" },
        messages: [{ role: "user", content: userContent }],
      },
      { signal: AbortSignal.timeout(10000) },
    );

    const toolBlock = response.content.find((b) => b.type === "tool_use");
    if (toolBlock && toolBlock.type === "tool_use") {
      const supplement = toolBlock.input as CompactSupplementInput;
      const formatted = formatSupplement(supplement);
      if (formatted.trim()) {
        outputHookResult(formatted);
      }
    } else {
      await Deno.stderr.write(
        new TextEncoder().encode(
          `SessionStart(compact): No tool_use block in response. stop_reason=${response.stop_reason}\n`,
        ),
      );
    }
  } catch (e) {
    const errName = e instanceof Error ? e.constructor.name : "Unknown";
    const errMsg = e instanceof Error ? e.message : String(e);
    await Deno.stderr.write(
      new TextEncoder().encode(
        `SessionStart(compact) Haiku error [${errName}]: ${errMsg}\n`,
      ),
    );
    outputHookResult(buildFallbackMarkdown(assets));
  }
}

async function handleStartupResume(projectDir: string): Promise<void> {
  const parts: string[] = [];

  parts.push("## Session Context");
  parts.push(`Working directory: ${Deno.cwd()}`);

  // Git info
  try {
    const branch = await getGitBranch(projectDir);
    if (branch) {
      parts.push(`Branch: ${branch}`);
    }

    const { stdout: logOut } = await new Deno.Command("git", {
      args: ["log", "--oneline", "-5"],
      stdout: "piped",
      stderr: "null",
      cwd: projectDir,
    }).output();
    const logText = new TextDecoder().decode(logOut).trim();
    if (logText) {
      parts.push("", "### Recent commits:", "```", logText, "```");
    }

    const { stdout: statusOut } = await new Deno.Command("git", {
      args: ["status", "--porcelain"],
      stdout: "piped",
      stderr: "null",
      cwd: projectDir,
    }).output();
    const statusText = new TextDecoder().decode(statusOut).trim();
    if (statusText) {
      const count = statusText.split("\n").length;
      parts.push(``, `Uncommitted changes: ${count} files`);
    }
  } catch {
    // Not a git repo, skip
  }

  // Check recent session log
  try {
    const sessDir = `${projectDir}/ai/log/sessions`;
    const entries: Deno.DirEntry[] = [];
    for await (const e of Deno.readDir(sessDir)) {
      if (e.isFile && e.name.endsWith(".md")) entries.push(e);
    }
    entries.sort((a, b) => b.name.localeCompare(a.name));
    if (entries.length > 0) {
      const latest = `${sessDir}/${entries[0].name}`;
      const content = await readTextFileSafe(latest);
      // Extract Conversation Analysis section only
      const match = content.match(
        /## (?:Conversation Analysis|First User Request)[\s\S]*?(?=\n---|\n## |$)/,
      );
      if (match) {
        parts.push(
          "",
          "## Previous Session",
          `File: ${entries[0].name}`,
          match[0].slice(0, 500),
        );
      }
    }
  } catch {
    // No session logs
  }

  // Feature list
  try {
    const featureList = await readTextFileSafe(
      `${projectDir}/feature_list.json`,
    );
    if (featureList) {
      const data = JSON.parse(featureList);
      const incomplete = data.features?.filter(
        (f: { passes: boolean }) => !f.passes,
      );
      if (incomplete?.length > 0) {
        incomplete.sort(
          (a: { priority: number }, b: { priority: number }) =>
            (a.priority ?? 999) - (b.priority ?? 999),
        );
        parts.push(
          "",
          "## Feature Status",
          `Incomplete features: ${incomplete.length}`,
          "Next priority:",
          "```json",
          JSON.stringify(incomplete[0], null, 2),
          "```",
        );
      }
    }
  } catch {
    // No feature list
  }

  // Evaluator findings (persist across compaction)
  try {
    const gatePath = `${projectDir}/ai/state/workflow-gate.json`;
    const gateContent = await readTextFileSafe(gatePath);
    if (gateContent) {
      const gate = JSON.parse(gateContent);
      const findings = gate.evaluator?.findings;
      if (findings && (findings.new > 0 || findings.persist > 0)) {
        parts.push(
          "",
          "## Evaluator Findings (前回)",
          `Status: ${gate.evaluator.status} — ${gate.evaluator.summary}`,
          `NEW: ${findings.new}, PERSIST: ${findings.persist}, RESOLVED: ${findings.resolved}`,
        );
      }
    }
  } catch {
    // No workflow-gate.json
  }

  // Context Reset handoff
  try {
    const handoffPath = `${projectDir}/ai/state/handoff.json`;
    const handoffContent = await readTextFileSafe(handoffPath);
    if (handoffContent) {
      const handoff = JSON.parse(handoffContent);
      const created = new Date(handoff.created_at);
      const now = new Date();
      // 24時間以内のものだけ注入
      if (now.getTime() - created.getTime() < 24 * 60 * 60 * 1000) {
        parts.push("", "## Context Reset Handoff");
        parts.push(`前セッションからの引き継ぎ:`);
        if (handoff.progress?.completed?.length > 0) {
          parts.push(`- 完了: ${handoff.progress.completed.join(", ")}`);
        }
        if (handoff.progress?.remaining?.length > 0) {
          parts.push(`- 残り: ${handoff.progress.remaining.join(", ")}`);
        }
        if (handoff.context?.next_steps?.length > 0) {
          parts.push(
            `- 次のアクション: ${handoff.context.next_steps.join(", ")}`,
          );
        }
        if (handoff.decisions?.length > 0) {
          parts.push(
            `- 重要な決定: ${handoff.decisions.map((d: { what: string }) => d.what).join("; ")}`,
          );
        }
        if (handoff.context?.gotchas?.length > 0) {
          parts.push(
            `- 注意点: ${handoff.context.gotchas.join("; ")}`,
          );
        }
      }
    }
  } catch {
    // handoff.json がなければスキップ
  }

  outputHookResult(parts.join("\n"));
}

async function main(): Promise<void> {
  const raw = new TextDecoder().decode(await readAll(Deno.stdin));
  const input: SessionStartInput = JSON.parse(raw);
  const source = input.source ?? "unknown";
  const sessionId = input.session_id ?? "";
  const projectDir = Deno.env.get("CLAUDE_PROJECT_DIR") ?? Deno.cwd();

  if (source === "compact" && sessionId) {
    await handleCompact(sessionId, projectDir);
  } else {
    await handleStartupResume(projectDir);
  }
}

main().catch((e) => {
  Deno.stderr.writeSync(
    new TextEncoder().encode(`SessionStart hook error: ${e}\n`),
  );
  Deno.exit(0);
});
