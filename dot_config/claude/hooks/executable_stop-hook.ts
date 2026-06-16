#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp --allow-net --allow-env --allow-run

import Anthropic from "npm:@anthropic-ai/sdk";
import { readAll } from "jsr:@std/io@0.224/read-all";
import {
  resolveAnthropicAuth,
  isRealUserMessage,
  extractTextFromContent,
} from "./lib/session-context.ts";

interface StopHookInput {
  stop_hook_active?: boolean;
  last_assistant_message?: string;
  transcript_path?: string;
}

interface ContentBlock {
  type: string;
  text?: string;
  name?: string;
  input?: Record<string, unknown>;
  content?: string | Array<{ type: string; text?: string }>;
}

interface TranscriptEntry {
  type: string;
  message?: {
    content: string | ContentBlock[];
  };
}

// ─── Goal 状態管理 ───

interface GoalState {
  condition: string;
  userHash: string;
  setAt: number;
  iterations: number;
  targetTurns: number | null;
  msgHashes: string[];
}

const GOAL_CLEAR_RE = /(?:^|\n)\s*\[?goal\s+(?:clear|off|cancel|reset|stop|none)\]?\s*(?:\n|$)/im;
const GOAL_CLEAR_JA_RE = /(?:^|\n)\s*(?:ゴール(?:解除|クリア|オフ|キャンセル|リセット))\s*(?:\n|$)/;

export function detectGoalClear(text: string): boolean {
  if (!text) return false;
  return GOAL_CLEAR_RE.test(text) || GOAL_CLEAR_JA_RE.test(text);
}

function goalStatePath(transcriptPath: string): string {
  return `/tmp/claude-goal-${djb2(transcriptPath)}.json`;
}

async function readGoalState(path: string): Promise<GoalState | null> {
  try {
    return JSON.parse(await Deno.readTextFile(path));
  } catch {
    return null;
  }
}

async function writeGoalState(path: string, state: GoalState): Promise<void> {
  try {
    await Deno.writeTextFile(path, JSON.stringify(state));
  } catch {
    // best-effort
  }
}

async function clearGoalState(path: string): Promise<void> {
  try {
    await Deno.remove(path);
  } catch {
    // ok
  }
}

// ─── トランスクリプト読み込み（Goal 評価用） ───

const TRANSCRIPT_BUDGET_CHARS = 200_000;

export function readTranscriptForGoal(
  transcriptPath: string,
  maxChars = TRANSCRIPT_BUDGET_CHARS,
): Promise<string> {
  return (async () => {
    try {
      const content = await Deno.readTextFile(transcriptPath);
      const lines = content.trimEnd().split("\n");
      const formatted: string[] = [];

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const entry: TranscriptEntry = JSON.parse(line);
          const text = formatTranscriptEntry(entry);
          if (text) formatted.push(text);
        } catch {
          continue;
        }
      }

      const full = formatted.join("\n\n");
      if (full.length <= maxChars) return full;

      // 末尾を優先して切り詰め
      let total = 0;
      let startIdx = formatted.length;
      for (let i = formatted.length - 1; i >= 0; i--) {
        total += formatted[i].length + 2;
        if (total > maxChars) break;
        startIdx = i;
      }
      const kept = formatted.slice(startIdx);
      const dropped = formatted.length - kept.length;
      return `[Earlier conversation truncated — ${dropped} messages omitted. Evaluate the condition against the recent transcript below; if the required evidence may be in the omitted prefix, return should_stop=false with reason "insufficient evidence in transcript".]\n\n${kept.join("\n\n")}`;
    } catch {
      return "";
    }
  })();
}

function formatTranscriptEntry(entry: TranscriptEntry): string | null {
  if (!entry.message?.content) return null;
  const content = entry.message.content;

  if (entry.type === "user") {
    const parts: string[] = [];
    if (Array.isArray(content)) {
      for (const block of content) {
        if (block.type === "text" && block.text?.trim()) {
          parts.push(block.text.trim());
        } else if (block.type === "tool_result") {
          const resultText = typeof block.content === "string"
            ? block.content
            : Array.isArray(block.content)
              ? block.content
                  .filter((b) => b.type === "text" && b.text)
                  .map((b) => b.text!)
                  .join("\n")
              : "";
          if (resultText.trim()) {
            parts.push(`[Tool Result]: ${truncateHeadTail(resultText, 500)}`);
          }
        }
      }
    } else if (typeof content === "string" && content.trim()) {
      parts.push(content.trim());
    }
    if (!parts.length) return null;
    const hasUserText = parts.some((p) => !p.startsWith("[Tool Result]:"));
    const label = hasUserText ? "[User]:" : "[Tool Output]:";
    return `${label} ${parts.join("\n")}`;
  }

  if (entry.type === "assistant") {
    const parts: string[] = [];
    if (Array.isArray(content)) {
      for (const block of content) {
        if (block.type === "text" && block.text?.trim()) {
          parts.push(block.text.trim());
        } else if (block.type === "tool_use" && block.name) {
          const input = block.input ?? {};
          const cmd = input.command as string | undefined;
          if (block.name === "Bash" && cmd) {
            parts.push(`[Tool: ${block.name}] ${cmd.slice(0, 200)}`);
          } else {
            parts.push(`[Tool: ${block.name}]`);
          }
        }
      }
    } else if (typeof content === "string" && content.trim()) {
      parts.push(content.trim());
    }
    return parts.length ? `[Assistant]: ${parts.join("\n")}` : null;
  }

  return null;
}

/**
 * ユーザーの直近リクエストに「明示的な反復/ループ指示」があるか判定する。
 * 検出結果は stop 評価器への「ヒント」として使い、goal_condition 抽出を促す。
 */
const LOOP_PATTERNS: RegExp[] = [
  /繰り返(して|す(?:$|[。、\s])|せ)/, // 命令形/節末のみ。名詞「繰り返しの/処理」は除外
  /(なくなる|無くなる|出なくなる|ゼロになる|0になる|消える|通る|直る|収束(する)?|終わる|パスする|グリーンになる|green になる)まで(?![のに])/, // 「までの/までに」(説明文)は除外
  /ループ(して|で回|させ|を回)/,
  /\b(repeat|loop)\s+until\b/i,
  /\bkeep\s+(going|iterating|repeating|running|trying|fixing)\b/i,
  // until + (60字以内の)成功語: "until tests pass" 等を拾う
  /\buntil\b[\s\S]{0,60}?\b(pass(?:es|ing)?|succeed|success|clean|resolved|done|green|gone|zero|no\s+(?:findings|errors|issues|failures))\b/i,
];

export function detectLoopDirective(text: string): boolean {
  return !!text && LOOP_PATTERNS.some((re) => re.test(text));
}

/** マッチした反復ディレクティブ周辺を抜き出す(userContext が 500字で切られても終了条件を haiku に渡すため) */
export function loopDirectiveSnippet(text: string): string {
  for (const re of LOOP_PATTERNS) {
    const m = text.match(re);
    if (m && m.index !== undefined) {
      const s = Math.max(0, m.index - 40);
      return text.slice(s, m.index + m[0].length + 40).trim();
    }
  }
  return "";
}

/** ユーザー発話から目標ターン数を抽出する（例: "20ターン", "10回繰り返して"） */
const TURN_COUNT_RE: RegExp[] = [
  /(\d+)\s*(?:ターン|回|ラウンド|周)/,
  /(\d+)\s*(?:turns?|rounds?|iterations?|cycles?|times?)\b/i,
];

export function extractTargetTurns(text: string): number | null {
  if (!text) return null;
  for (const re of TURN_COUNT_RE) {
    const m = text.match(re);
    if (m) {
      const n = parseInt(m[1], 10);
      if (n >= 2 && n <= 100) return n;
    }
  }
  return null;
}

function truncateHeadTail(text: string, budget: number): string {
  if (text.length <= budget) return text;
  const headSize = Math.floor(budget * 0.6);
  const tailSize = budget - headSize - 20;
  return `${text.slice(0, headSize)}\n…[truncated]…\n${text.slice(-tailSize)}`;
}

function djb2(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.charCodeAt(i)) & 0xffffffff;
  }
  return (h >>> 0).toString(36);
}

export function detectSpin(hashes: string[]): boolean {
  if (hashes.length < 3) return false;
  const last3 = hashes.slice(-3);
  return last3[0] === last3[1] && last3[1] === last3[2];
}

export function countConsecutiveIdentical(hashes: string[]): number {
  if (hashes.length === 0) return 0;
  const last = hashes[hashes.length - 1];
  let count = 0;
  for (let i = hashes.length - 1; i >= 0; i--) {
    if (hashes[i] === last) count++;
    else break;
  }
  return count;
}

interface StopDecision {
  should_stop: boolean;
  reason: string;
  done_summary?: string;
  goal_condition?: string;
  impossible?: boolean;
}

const STOP_DECISION_TOOL: Anthropic.Tool = {
  name: "stop_decision",
  description: "Decide whether Claude should stop or continue working.",
  input_schema: {
    type: "object" as const,
    properties: {
      should_stop: {
        type: "boolean",
        description:
          "true if Claude should stop, false if Claude should continue",
      },
      reason: {
        type: "string",
        description: "Brief reason for the decision in Japanese",
      },
      done_summary: {
        type: "string",
        description:
          "Only when should_stop=true: a 15-40 character Japanese summary of what Claude actually did (for audio notification). Use noun phrases. Omit when should_stop=false.",
      },
      goal_condition: {
        type: "string",
        description:
          "When should_stop=false AND the task has a clear, verifiable completion condition not yet met, state it concisely. Examples: 'all tests pass', 'lint errors reach zero', 'migration complete'. Omit for questions, trivial tasks, or when should_stop=true.",
      },
      impossible: {
        type: "boolean",
        description:
          "true ONLY when an active goal condition can never be satisfied in this session. Requires should_stop=true.",
      },
    },
    required: ["should_stop", "reason"],
  },
};

const SYSTEM_PROMPT = `You evaluate whether Claude Code should stop or continue.

You will receive:
1. A conversation transcript (recent user/assistant messages)
2. Contextual annotations (verification status, active goal, loop hints, etc.)

Rules:
- APPROVE stop if: task is complete, Claude asks user a question, reports completion, or awaits input
- BLOCK stop (continue) only if: the transcript shows mid-task work with clear next steps AND there are incomplete tasks that AI can finish without user input
- If the user's request was a question and Claude answered it, APPROVE stop
- If "Verification evidence: FAIL", BLOCK — must fix before completing
- If "Verification evidence: PASS", factor it positively
- If "Context health: HIGH USAGE" and work is incomplete, suggest --fork-session
- Default: approve stop

## Active Goal
When an "Active goal" annotation is present, evaluate the condition against transcript evidence ONLY.
- If the condition IS satisfied (explicit evidence such as tool output, test results, or verification data in transcript): should_stop=true
- If the condition is NOT satisfied: should_stop=false (continue working)
- The assistant's own completion claims are NOT sufficient evidence. Look for concrete tool output (e.g., test pass/fail counts, exit codes, lint output) in [Tool Result] blocks
- If the condition can NEVER be satisfied (self-contradictory, unavailable resources, all approaches exhausted): should_stop=true + impossible=true
- The assistant claiming impossibility is evidence, not proof — verify independently
- Do NOT set impossible just because progress is slow

## Auto-Goal Detection
When you BLOCK stop (should_stop=false) and no goal is active, also set goal_condition if the task has a clear, verifiable completion condition not yet met. This activates goal tracking for subsequent turns.
Good conditions: "npm test exits with 0 failures", "all lint errors resolved", "all files migrated to new API"
Do NOT set goal_condition for: questions, simple one-off tasks, tasks without measurable criteria.
If a "Loop hint" annotation is present, you SHOULD set goal_condition.

## Complex Task Detection
When the task is complex (multi-file changes, multi-round reviews, large refactoring) AND goal is not yet active AND no rubric annotation is present, include in reason: "このタスクはゴール定義が有効。ユーザーに完了条件を確認してから開始すべき。" This prompts Claude to ask the user for clarification before diving into a long loop. Indicators of complexity: multiple acceptance criteria mentioned, "全部", "すべて", review/refactor scope > 5 files.
If a "Rubric" annotation IS present, use the rubric content as the goal condition directly.

## done_summary
When should_stop=true, set done_summary: a 15-40 character Japanese noun phrase of what Claude actually DID. Examples: "認証バグ修正と動作確認", "stop hookにgoal機能追加". Omit when should_stop=false.

Call stop_decision with your judgment.`;

/** Read the last user text message from the transcript JSONL */
export async function getLastUserRequest(
  transcriptPath: string,
): Promise<string | null> {
  try {
    const content = await Deno.readTextFile(transcriptPath);
    const lines = content.trimEnd().split("\n");

    // 末尾から走査し **本物のユーザー発話のみ** 返す。Stop hook feedback / [Request interrupted] /
    // コマンド出力等のシステム生成メッセージは isRealUserMessage で除外する。
    // (除外しないと、ループ2周目以降に "Stop hook feedback:" を直近リクエストと誤認し反復検出が落ちる)
    for (let i = lines.length - 1; i >= 0; i--) {
      try {
        const entry: TranscriptEntry = JSON.parse(lines[i]);
        if (entry.type !== "user" || !entry.message?.content) continue;
        if (!isRealUserMessage(entry.message.content)) continue;
        const text = extractTextFromContent(entry.message.content).trim();
        if (text) return text;
      } catch {
        // skip malformed lines
      }
    }
  } catch {
    // transcript read failure is non-fatal
  }
  return null;
}

/** 停止通知（音声 + OSC toast） */
function notifyStop(summary: string): void {
  const home = Deno.env.get("HOME");
  if (!home) return;
  const cwd = Deno.env.get("CLAUDE_PROJECT_DIR") ?? Deno.cwd();
  const proj = cwd.split("/").pop() ?? "";
  const title = proj ? `[Stop] ${proj}` : "[Stop] Claude Code";

  try {
    new Deno.Command(`${home}/.config/claude/hooks/osc-notify.sh`, {
      args: [title, summary],
      stdin: "null",
      stdout: "null",
      stderr: "null",
    }).spawn();
  } catch {
    // best-effort
  }

  if (Deno.env.get("CLAUDE_SAY_MUTE") !== "1") {
    try {
      new Deno.Command(`${home}/.config/claude/bin/say-notify`, {
        args: [summary],
        stdin: "null",
        stdout: "null",
        stderr: "null",
      }).spawn();
    } catch {
      // best-effort
    }
  }
}

async function main(): Promise<void> {
  try {
    const raw = new TextDecoder().decode(await readAll(Deno.stdin));
    const input: StopHookInput = JSON.parse(raw);

    const userRequest = input.transcript_path
      ? await getLastUserRequest(input.transcript_path)
      : null;
    const lastMessage = input.last_assistant_message || "";

    // ─── Goal 状態管理 ───
    const gPath = input.transcript_path ? goalStatePath(input.transcript_path) : null;

    if (gPath && userRequest && detectGoalClear(userRequest)) {
      await clearGoalState(gPath);
    }

    let goalState = gPath ? await readGoalState(gPath) : null;

    // ユーザーが新しい発話をした場合、古いゴールを自動クリア
    if (goalState && userRequest) {
      const currentUserHash = djb2(userRequest);
      if (goalState.userHash !== currentUserHash) {
        await clearGoalState(gPath!);
        goalState = null;
      }
    }

    // stop_hook_active 時の早期 exit（Goal 駆動中は除く）
    if (input.stop_hook_active && !goalState) {
      Deno.exit(0);
    }
    if (!lastMessage) {
      Deno.exit(0);
    }

    // ─── 空転・ターン上限の事前チェック（API 呼び出し前に判定） ───
    if (goalState && gPath) {
      goalState.iterations++;
      const msgHash = djb2(lastMessage.slice(0, 500));
      goalState.msgHashes.push(msgHash);
      if (goalState.msgHashes.length > 10) {
        goalState.msgHashes = goalState.msgHashes.slice(-10);
      }

      if (goalState.targetTurns && goalState.iterations >= goalState.targetTurns) {
        await clearGoalState(gPath);
        console.log(
          JSON.stringify({
            decision: "block",
            reason: `[Goal: ${goalState.condition}] ターン上限 ${goalState.targetTurns} に到達。進捗状況と未達点をユーザーに報告して終了せよ。`,
          }),
        );
        Deno.exit(0);
      }

      const spinDetected = detectSpin(goalState.msgHashes);
      if (spinDetected) {
        const spinCount = countConsecutiveIdentical(goalState.msgHashes);
        if (spinCount >= 5) {
          await clearGoalState(gPath);
          console.log(
            JSON.stringify({
              decision: "block",
              reason: `[Goal: ${goalState.condition}] 空転が ${spinCount} 回連続。ユーザーに状況を報告し、別のアプローチを提案して終了せよ。`,
            }),
          );
          Deno.exit(0);
        }
      }

      await writeGoalState(gPath, goalState);
    }

    const auth = await resolveAnthropicAuth();
    if (!auth) {
      Deno.exit(0);
    }
    const client = new Anthropic({
      authToken: auth.authToken,
      apiKey: null,
      defaultHeaders: { "anthropic-beta": "oauth-2025-04-20" },
    });

    // ─── トランスクリプト読み込み ───
    const transcript = input.transcript_path
      ? await readTranscriptForGoal(input.transcript_path)
      : "";

    // ─── アノテーション構築 ───
    const annotations: string[] = [];

    // ゴール
    if (goalState) {
      const spinDetected = detectSpin(goalState.msgHashes);
      const spinCount = spinDetected ? countConsecutiveIdentical(goalState.msgHashes) : 0;
      let goalNote = `Active goal（${goalState.iterations}ターン目）: ${goalState.condition}`;
      if (spinDetected) {
        goalNote += `\n⚠️ SPIN WARNING: ${spinCount}回連続で同様の出力。アプローチ変更が必要。`;
      }
      annotations.push(goalNote);
    }

    // ループヒント
    if (!goalState && userRequest && detectLoopDirective(userRequest)) {
      const snippet = loopDirectiveSnippet(userRequest);
      const targetTurns = extractTargetTurns(userRequest);
      annotations.push(
        `Loop hint: ユーザーの指示に反復/ループパターンが検出された${
          snippet ? `（該当: "${snippet}"）` : ""
        }。条件がまだ満たされていなければ goal_condition を設定すること。${
          targetTurns ? `ターン上限: ${targetTurns}` : ""
        }`,
      );
    }

    // rubric ファイル（define-goal skill 連携）
    const sessionDir = Deno.env.get("CLAUDE_SESSION_DIR") ?? "";
    if (sessionDir) {
      try {
        const rubricPath = `${sessionDir}/goal-rubric.md`;
        const rubricContent = await Deno.readTextFile(rubricPath);
        if (rubricContent.trim()) {
          const truncated = rubricContent.length > 2000
            ? rubricContent.slice(0, 2000) + "\n…[truncated]"
            : rubricContent;
          annotations.push(`Rubric (from goal-rubric.md):\n${truncated}`);
        }
      } catch {
        // rubric なし — 通常動作
      }
    }

    // 検証状態
    const projectDir = Deno.env.get("CLAUDE_PROJECT_DIR") ?? Deno.cwd();
    try {
      const verifyPath = `${projectDir}/ai/state/verification.json`;
      const verifyContent = await Deno.readTextFile(verifyPath);
      const verify = JSON.parse(verifyContent);
      const currentSha = await (async () => {
        try {
          const { stdout } = await new Deno.Command("git", {
            args: ["rev-parse", "--short", "HEAD"],
            stdout: "piped",
            stderr: "null",
            cwd: projectDir,
          }).output();
          return new TextDecoder().decode(stdout).trim();
        } catch {
          return "";
        }
      })();
      if (verify.head_sha === currentSha && verify.status === "PASS") {
        annotations.push("Verification evidence: PASS (fresh, matching HEAD)");
      } else if (verify.head_sha !== currentSha) {
        annotations.push("Verification evidence: STALE (HEAD changed since verification)");
      } else {
        annotations.push(`Verification evidence: ${verify.status}`);
      }
    } catch {
      annotations.push("Verification evidence: NONE");
    }

    // コンテキスト健全性
    try {
      const sessionHealthDir = "/tmp/claude-session-health";
      let healthFile = "";
      for await (const entry of Deno.readDir(sessionHealthDir)) {
        if (entry.isFile && entry.name.endsWith(".json")) {
          healthFile = `${sessionHealthDir}/${entry.name}`;
        }
      }
      if (healthFile) {
        const healthContent = await Deno.readTextFile(healthFile);
        const health = JSON.parse(healthContent);
        if (health.context_pct >= 85) {
          annotations.push(`Context health: HIGH USAGE (${health.context_pct}%) — consider --fork-session`);
        } else if (health.context_pct >= 70) {
          annotations.push(`Context health: ELEVATED (${health.context_pct}%)`);
        }
      }
    } catch {
      // no health data
    }

    const annotationBlock = annotations.length
      ? `\n\n---\n${annotations.join("\n")}`
      : "";

    // ─── 単一の Haiku 評価 ───
    const response = await client.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 512,
      system: SYSTEM_PROMPT,
      tools: [STOP_DECISION_TOOL],
      tool_choice: { type: "tool", name: "stop_decision" },
      messages: [
        {
          role: "user",
          content: `<transcript>\n${transcript || lastMessage}\n</transcript>${annotationBlock}`,
        },
      ],
    });

    const toolBlock = response.content.find((b) => b.type === "tool_use");
    if (!toolBlock || toolBlock.type !== "tool_use") {
      Deno.exit(0);
    }

    const decision = toolBlock.input as StopDecision;

    if (decision.should_stop) {
      // ゴール達成 or 不可能 or 通常の停止
      if (goalState && gPath) {
        await clearGoalState(gPath);
      }
      if (decision.done_summary) {
        notifyStop(decision.done_summary);
      }
    } else {
      // 継続: ゴール自動抽出
      if (gPath && decision.goal_condition && !goalState) {
        const targetTurns = userRequest ? extractTargetTurns(userRequest) : null;
        await writeGoalState(gPath, {
          condition: decision.goal_condition,
          userHash: djb2(userRequest || ""),
          setAt: Date.now(),
          iterations: 1,
          targetTurns,
          msgHashes: [djb2(lastMessage.slice(0, 500))],
        });
      }

      console.log(
        JSON.stringify({
          decision: "block",
          reason: decision.goal_condition && !goalState
            ? `[Goal set: ${decision.goal_condition}] ${decision.reason}`
            : goalState
              ? `[Goal: ${goalState.condition}] ${decision.reason}`
              : decision.reason || "タスクが未完了",
        }),
      );
    }
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    await Deno.stderr.write(
      new TextEncoder().encode(`Stop hook error (allowing stop): ${msg}\n`),
    );
  }

  Deno.exit(0);
}

// 直接実行時のみ起動(import 時=テスト時は走らせない)
if (import.meta.main) {
  main();
}
