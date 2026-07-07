#!/usr/bin/env -S deno run --allow-read --allow-run --allow-env --allow-write

/**
 * SessionStart Hook (TS版)
 *
 * compact matcher: compact_resume.json + findings → 機械組み立てコンテキスト注入
 * startup|resume matcher: git状態 + 軽量コンテキスト注入
 */

import { readAll } from "jsr:@std/io@0.224/read-all";
import { getGitBranch, getGitShortHead } from "./lib/session-context.ts";

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

async function buildResumeContext(projectDir: string, sessionId: string): Promise<string> {
  try {
    const resumePath = `${projectDir}/ai/state/${sessionId}/compact_resume.json`;
    const content = await readTextFileSafe(resumePath);
    if (!content) return "";
    const resume = JSON.parse(content);

    const parts: string[] = ["", "## Compact Resume"];

    if (resume.resume) {
      // Haiku structured output
      const r = resume.resume;
      if (r.objective) parts.push(`目的: ${r.objective}`);
      if (r.current_subtask) parts.push(`現在のサブタスク: ${r.current_subtask}`);
      if (r.done_criteria?.length > 0) {
        parts.push("Done 条件:");
        for (const c of r.done_criteria.slice(0, 5)) parts.push(`- ${c}`);
      }
      if (r.decisions?.length > 0) {
        parts.push("決定事項:");
        for (const d of r.decisions.slice(0, 3)) parts.push(`- ${d.what}（理由: ${d.why}）`);
      }
      if (r.failed_attempts?.length > 0) {
        parts.push("失敗した試行（同じアプローチを繰り返さないこと）:");
        for (const f of r.failed_attempts.slice(0, 3)) {
          parts.push(`- ${f.attempt}（失敗理由: ${f.why_failed}）`);
        }
      }
      if (r.open_loops?.length > 0) {
        parts.push("未完了:");
        for (const l of r.open_loops.slice(0, 3)) parts.push(`- ${l}`);
      }
      if (r.next_actions?.length > 0) {
        parts.push("次のアクション:");
        for (const a of r.next_actions.slice(0, 3)) parts.push(`- ${a}`);
      }
    } else if (resume.resume_text) {
      // Haiku text fallback
      parts.push(resume.resume_text.slice(0, 1000));
    } else if (resume.compact_summary_excerpt) {
      // Mechanical extraction
      parts.push("(compact summary excerpt)");
      parts.push(String(resume.compact_summary_excerpt).slice(0, 500));
    }

    return parts.join("\n");
  } catch {
    return "";
  }
}

const FINDINGS_TTL_HOURS = 12;

async function buildFindingsContext(projectDir: string, sessionId?: string): Promise<string> {
  try {
    // Primary: workflow-gate.json, Fallback: findings-checkpoint.json
    let gateContent = await readTextFileSafe(`${projectDir}/ai/state/workflow-gate.json`);
    if (!gateContent && sessionId) {
      gateContent = await readTextFileSafe(
        `${projectDir}/ai/state/${sessionId}/findings-checkpoint.json`,
      );
    }
    if (!gateContent) return "";
    const gate = JSON.parse(gateContent);
    const activeFindings = gate.evaluator?.active_findings;
    if (!activeFindings || activeFindings.length === 0) return "";

    // TTL チェック: updated_at が 12 時間以内かどうか
    if (gate.updated_at) {
      const updatedAt = new Date(gate.updated_at).getTime();
      if (isNaN(updatedAt) || Date.now() - updatedAt > FINDINGS_TTL_HOURS * 3600_000) {
        return ""; // stale findings — skip injection
      }
    }

    const lines: string[] = [
      "",
      "## 要検証チェックリスト (evaluator findings)",
      `前回評価: ${gate.evaluator.status} — ${gate.evaluator.summary}`,
      "",
      "以下を修正・検証してから完了すること:",
    ];
    // PERSIST を優先表示（スタック検知対象）
    const sorted = [...activeFindings].sort(
      (a: { persist_count: number }, b: { persist_count: number }) =>
        (b.persist_count ?? 1) - (a.persist_count ?? 1),
    );
    for (const f of sorted.slice(0, 5)) {
      const persist = f.persist_count > 1 ? ` ⚠ persist x${f.persist_count}` : "";
      lines.push(`- [ ] [${f.key}] ${f.path}:${f.line} — ${f.summary}${persist}`);
    }
    if (activeFindings.length > 5) {
      lines.push(`- ... 他 ${activeFindings.length - 5} 件`);
    }
    return lines.join("\n");
  } catch {
    return "";
  }
}

function outputHookResult(context: string): void {
  const result = {
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: context,
      // skill 編集を再起動なしで同セッションへ反映（Claude Code v2.1.152+）
      reloadSkills: true,
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
    "## Compact Recovery (compact_summary unavailable)",
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

async function handleCompact(
  sessionId: string,
  projectDir: string,
): Promise<void> {
  const stateDir = `${projectDir}/ai/state/${sessionId}`;
  const assets = await readJsonFile<AssetsJson>(`${stateDir}/assets.json`);
  const compactSummary = await readTextFileSafe(
    `${stateDir}/compact_summary.md`,
  );

  const fallbackCtx =
    !compactSummary && assets && !isExpired(assets.created_at, assets.ttl_hours)
      ? buildFallbackMarkdown(assets)
      : "";
  const findingsCtx = await buildFindingsContext(projectDir, sessionId);
  const resumeCtx = await buildResumeContext(projectDir, sessionId);

  if (fallbackCtx || findingsCtx || resumeCtx) {
    outputHookResult(fallbackCtx + findingsCtx + resumeCtx);
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

  // Task contract (scope drift prevention)
  try {
    const contractPath = `${projectDir}/ai/state/task_contract.json`;
    const contractContent = await readTextFileSafe(contractPath);
    if (contractContent) {
      const contract = JSON.parse(contractContent);
      if (contract.objective) {
        parts.push("", "## Task Contract (スコープ確認)");
        parts.push(`目的: ${contract.objective}`);
        if (contract.current_step) parts.push(`現在: ${contract.current_step}`);
        if (contract.done_criteria?.length > 0) {
          parts.push("Done 条件:");
          for (const c of contract.done_criteria.slice(0, 5)) {
            parts.push(`- [ ] ${c}`);
          }
        }
        if (contract.out_of_scope?.length > 0) {
          parts.push(`スコープ外: ${contract.out_of_scope.join(", ")}`);
        }
      }
    }
  } catch {
    // No task contract
  }

  // Evaluator findings (persist across compaction)
  try {
    const gatePath = `${projectDir}/ai/state/workflow-gate.json`;
    const gateContent = await readTextFileSafe(gatePath);
    if (gateContent) {
      const gate = JSON.parse(gateContent);
      const activeFindings = gate.evaluator?.active_findings;
      if (activeFindings && activeFindings.length > 0) {
        // HEAD 一致チェック
        const currentSha = await getGitShortHead(projectDir);

        if (gate.head_sha === currentSha) {
          // HEAD 一致: active findings を詳細注入
          const findingsCtx = await buildFindingsContext(projectDir);
          if (findingsCtx) parts.push(findingsCtx);
        } else {
          // HEAD 不一致: stale notice のみ
          parts.push(
            "",
            `前回評価 (${gate.head_sha}) は現在の HEAD (${currentSha}) と異なります。再評価推奨。`,
          );
        }
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
