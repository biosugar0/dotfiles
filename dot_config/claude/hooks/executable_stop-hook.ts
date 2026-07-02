#!/usr/bin/env -S deno run --allow-read --allow-write=/tmp,${HOME}/.local/state --allow-net --allow-env --allow-run

import Anthropic from "npm:@anthropic-ai/sdk";
import { readAll } from "jsr:@std/io@0.224/read-all";
import {
  extractTextFromContent,
  getGitDirtyCount,
  getGitShortHead,
  isRealUserMessage,
  resolveAnthropicAuth,
} from "./lib/session-context.ts";
import { harnessLog } from "./lib/harness-log.ts";

interface StopHookInput {
  stop_hook_active?: boolean;
  last_assistant_message?: string;
  transcript_path?: string;
  session_id?: string;
}

interface ContentBlock {
  type: string;
  text?: string;
  name?: string;
  id?: string;
  input?: Record<string, unknown>;
  content?: string | Array<{ type: string; text?: string }>;
  tool_use_id?: string;
}

interface TranscriptEntry {
  type: string;
  message?: {
    content: string | ContentBlock[];
    stop_reason?: string;
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
  errorHashes: string[];
}

const GOAL_CLEAR_RE =
  /(?:^|\n)\s*\[?goal\s+(?:clear|off|cancel|reset|stop|none)\]?\s*(?:\n|$)/im;
const GOAL_CLEAR_JA_RE =
  /(?:^|\n)\s*(?:ゴール(?:解除|クリア|オフ|キャンセル|リセット))\s*(?:\n|$)/;

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

const RECENT_DETAIL_COUNT = 20;

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

      if (formatted.length <= RECENT_DETAIL_COUNT) {
        const full = formatted.join("\n\n");
        if (full.length <= maxChars) return full;
      }

      // 直近 RECENT_DETAIL_COUNT は詳細、それ以前は圧縮
      const recentStart = Math.max(0, formatted.length - RECENT_DETAIL_COUNT);
      const older = formatted.slice(0, recentStart);
      const recent = formatted.slice(recentStart);

      const compressed = older.map((msg) => {
        // tool_result は省略し、user/assistant のテキストだけ残す（各100文字まで）
        if (msg.startsWith("[Tool Output]:")) return null;
        const firstLine = msg.split("\n")[0];
        return firstLine.length > 100
          ? firstLine.slice(0, 100) + "…"
          : firstLine;
      }).filter(Boolean);

      const parts: string[] = [];
      if (compressed.length > 0) {
        parts.push(
          `[Earlier context — ${compressed.length} messages summarized]\n${
            compressed.join("\n")
          }`,
        );
      }
      parts.push(...recent);

      const full = parts.join("\n\n");
      if (full.length <= maxChars) return full;

      // それでも超える場合は末尾優先で切り詰め
      let total = 0;
      let startIdx = parts.length;
      for (let i = parts.length - 1; i >= 0; i--) {
        total += parts[i].length + 2;
        if (total > maxChars) break;
        startIdx = i;
      }
      const kept = parts.slice(startIdx);
      const dropped = parts.length - kept.length;
      return `[Transcript truncated — ${dropped} sections omitted. Evaluate against recent transcript; if evidence may be in omitted prefix, return should_stop=false.]\n\n${
        kept.join("\n\n")
      }`;
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

// ─── ゴール分類（actor / reactor）───

/**
 * ゴール条件が「Claude 自身がローカル検証で達成を確認できる通過系（actor）」か判定する。
 * true の場合、out-of-band の verification.json の fresh PASS を達成の決定的証拠として
 * Haiku 判定を短絡できる（案A）。test/lint/build/type/compile 等のローカル検証名詞で判定。
 */
const VERIFIABLE_GOAL_PATTERNS: RegExp[] = [
  /\b(?:unit\s+)?tests?\b/i,
  /\blint(?:ing)?\b/i,
  /\bbuild\b/i,
  /\b(?:typecheck|type[-\s]?check|tsc|compil(?:es?|ed|ing|ation))\b/i,
  /\bcoverage\b/i,
  /(?:テスト|型(?:チェック|検査)?|ビルド|リント|コンパイル)/,
];

export function classifyVerifiableGoal(condition: string): boolean {
  if (!condition) return false;
  return VERIFIABLE_GOAL_PATTERNS.some((re) => re.test(condition));
}

/**
 * ゴール条件が「外部システムが駆動する完了条件（reactor）」か判定する。
 * true の場合、stop-gate での busy-loop ではなく Monitor ツールでの監視に委ねるべき（案B）。
 * CI/デプロイ/パイプライン/ジョブ/PRマージ/リリース等。reactor は actor より優先する。
 */
// 注: bare な環境名詞(production/staging/canary)は actor goal や git の staging area と
// 衝突するため含めない。CI は「CI run/job/pass 等」の完了文脈に限定する。最終的な actor/reactor
// 優先は呼び出し側で classifyVerifiableGoal を優先させて解決する(verifiable が勝つ)。
const REACTOR_GOAL_PATTERNS: RegExp[] = [
  /\bci\s+(?:run|builds?|jobs?|pipelines?|checks?|passes?|green|completes?|succeed(?:s|ed)?)\b/i,
  /\b(?:wait(?:ing)?\s+(?:for|on)|until|once|after)\s+ci\b/i,
  /\b(?:deploy(?:ment|s|ed|ing)?|rollout|releas(?:e|ed|es|ing))\b/i,
  /\b(?:pipeline|workflow\s+run|gh\s+actions?|github\s+actions?)\b/i,
  /\b(?:pr|pull\s+request)\b[\s\S]{0,30}\b(?:merg|review|approv|check)/i,
  /\b(?:merg(?:e|ed|ing)|approv(?:al|ed|e))\b/i,
  /(?:デプロイ|リリース|本番|ステージング|パイプライン|ロールアウト|カナリア)/,
  /(?:CI|ジョブ|ワークフロー|アクション)\s*(?:が|の|を)?\s*(?:完了|終了|green|グリーン|通(?:る|過)|成功|パス|済)/i,
  /(?:マージ|レビュー|承認)\s*(?:が|を|の)?\s*(?:完了|され|待|済|通)/,
];

export function detectReactorGoal(condition: string): boolean {
  if (!condition) return false;
  return REACTOR_GOAL_PATTERNS.some((re) => re.test(condition));
}

// ─── バックグラウンドタスク待機検出 ───

const WAITING_PATTERNS: RegExp[] = [
  /\b(?:waiting|wait)\s+(?:for|on)\s+(?:the\s+)?(?:background|notification|completion|result)/i,
  /\brunning\s+in\s+(?:the\s+)?background\b/i,
  /\bwill\s+be\s+(?:automatically\s+)?notified\s+when\b/i,
  /\btask.notification\b/i,
  /(?:完了|結果|通知)(?:を|の)(?:待[つちっ]|待機)/,
  /バックグラウンド(?:で|に|の|タスク|処理|実行)/,
  /(?:ワークフロー|workflow|エージェント|agent|タスク).*(?:実行中|進行中|処理中)/i,
  /(?:完了|終了)(?:したら|次第|を待)/,
  /通知(?:が届|を待|待ち)/,
];

export function isWaitingForBackground(text: string): boolean {
  return !!text && WAITING_PATTERNS.some((re) => re.test(text));
}

const BACKGROUND_TOOL_NAMES = new Set(["Agent", "Workflow", "Monitor"]);

/**
 * 直近のassistantメッセージにバックグラウンドツール呼び出しが含まれ、
 * かつその後にreal userメッセージ(stop-hook feedbackでない)が来ていなければ true。
 * Background toolはtool_resultが即座に返るためID照合では検出できない。
 */
export async function hasRecentBackgroundToolCalls(
  transcriptPath: string,
): Promise<boolean> {
  try {
    const content = await Deno.readTextFile(transcriptPath);
    const lines = content.trimEnd().split("\n");

    let foundRealUserAfterAssistant = false;

    for (let i = lines.length - 1; i >= 0; i--) {
      try {
        const entry: TranscriptEntry = JSON.parse(lines[i]);
        if (!entry.message?.content || !Array.isArray(entry.message.content)) {
          continue;
        }

        if (entry.type === "user") {
          if (isRealUserMessage(entry.message.content)) {
            foundRealUserAfterAssistant = true;
            break;
          }
        } else if (entry.type === "assistant") {
          if (foundRealUserAfterAssistant) break;
          for (const block of entry.message.content) {
            if (
              block.type === "tool_use" &&
              BACKGROUND_TOOL_NAMES.has(block.name ?? "")
            ) {
              if (
                block.name === "Agent" &&
                !block.input?.run_in_background
              ) {
                continue;
              }
              return true;
            }
          }
          break;
        }
      } catch {
        continue;
      }
    }
    return false;
  } catch {
    return false;
  }
}

function truncateHeadTail(text: string, budget: number): string {
  if (text.length <= budget) return text;
  const headSize = Math.floor(budget * 0.6);
  const tailSize = budget - headSize - 20;
  return `${text.slice(0, headSize)}\n…[truncated]…\n${text.slice(-tailSize)}`;
}

const ERROR_PATTERNS: RegExp[] = [
  /(?:FAIL|FAILED|ERROR|Error)\s+(.+?)(?:\n|$)/i,
  /error\[([A-Z0-9_-]+)\]/,
  /(\d+)\s+(?:failing|failed|errors?)\b/i,
  /exit\s+(?:code|status)[:\s]+(\d+)/i,
];

export function extractErrorFingerprint(text: string): string {
  const matches: string[] = [];
  for (const re of ERROR_PATTERNS) {
    const m = text.match(re);
    if (m) {
      if (m[1] === "0") continue;
      matches.push(m[0].slice(0, 80));
    }
  }
  return matches.length ? djb2(matches.sort().join("|")) : "";
}

function djb2(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.charCodeAt(i)) & 0xffffffff;
  }
  return (h >>> 0).toString(36);
}

// ─── tool-call タグ破損（Opus 4.8）検知 ───
// Opus 4.8/4.7 は長大な tool 呼び出しを構造化 tool_use にできず、assistant text チャネルに
// 素の XML(先頭 court 化・antml 名前空間欠落の <invoke name="...">…</invoke>)として漏らす。
// harness は sr=tool_use で漏れたものはターン内で auto-retry するが、モデルが漏洩 XML を最終
// テキストとして吐き end_turn で正常停止したケース（sr=end_turn）は retry されず user に戻る。
// この stranded ケースこそ復旧対象。未実行の漏れは「メッセージ末尾が </invoke> で終わる」形に
// なる（tool 呼び出しが末尾に来て停止）。バグを prose で論じる文は </invoke> の後に説明が続き
// 末尾一致しないため、tail-anchor で誤検知を切り分ける（stop_reason には依存しない）。
export interface ToolcallLeak {
  tool: string;
  command: string | null;
  sig: string;
}

export function detectToolcallLeakInText(text: string): ToolcallLeak | null {
  if (!text) return null;
  // tail-anchor: 末尾（trailing 空白を除く）が </invoke> で終わることを要求。
  // これが未実行の tool-call 漏洩と、単なる言及/議論テキストとを分ける決定的な差。
  if (!text.replace(/\s+$/, "").endsWith("</invoke>")) return null;
  const m = text.match(/<invoke\s+name="([^"]+)"\s*>/);
  if (!m) return null;
  if (!/<parameter\s+name=/.test(text)) return null;
  const tool = m[1];
  const cmdM = text.match(/<parameter\s+name="command">([\s\S]*?)<\/parameter>/);
  const command = cmdM ? cmdM[1].trim() : null;
  const anchor = m.index ?? 0;
  const sig = djb2(`${tool}:${command ?? text.slice(anchor, anchor + 120)}`);
  return { tool, command, sig };
}

/**
 * transcript 末尾の最後の assistant エントリを読み、未実行の tool-call 破損を検出する。
 * tool_use ブロックが1つでもあれば「実行済み(=harness の auto-retry で復旧済み or 正常)」と
 * みなし null。stop_reason!=="tool_use"（＝tool 呼び出しを試みていない通常の text 応答）も null。
 */
export async function detectUnrecoveredLeak(
  transcriptPath: string,
): Promise<ToolcallLeak | null> {
  try {
    const content = await Deno.readTextFile(transcriptPath);
    const lines = content.trimEnd().split("\n");
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (!line) continue;
      let entry: TranscriptEntry;
      try {
        entry = JSON.parse(line);
      } catch {
        continue;
      }
      if (entry.type !== "assistant" || !entry.message?.content) continue;
      const msgContent = entry.message.content;
      if (!Array.isArray(msgContent)) return null;
      // tool_use が成立していれば破損ではない（実行された）
      if (msgContent.some((b) => b.type === "tool_use")) return null;
      // 誤検知の切り分けは detectToolcallLeakInText の tail-anchor に委ねる
      // （stop_reason は stranded=end_turn / auto-retried=tool_use の両方を取りうるため見ない）
      const text = msgContent
        .filter((b) => b.type === "text" && b.text)
        .map((b) => b.text!)
        .join("\n");
      return detectToolcallLeakInText(text);
    }
  } catch {
    // read failure は非致命
  }
  return null;
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
- If "Verification evidence: STALE" or "NONE" and the task involved code changes: assistant's completion claim alone is insufficient. Look for recent [Tool Result] showing test/lint/build pass. If no fresh evidence exists, suggest verification but do not hard-block (docs/config changes may not need it)
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
When you BLOCK stop (should_stop=false) and no goal is active, set goal_condition when the task has a clear deliverable or end state that can be verified. This includes:
- Implementation/fix/refactoring: "all tests pass", "lint clean", "build success"
- Investigation/research: "root cause identified and reported", "vulnerability list delivered", "research report complete"
- Migration/review: "all files migrated", "review report delivered" (use "findings at zero" only if user explicitly asked to fix until clean)
Do NOT set goal_condition for: conversational exchanges (opinions, "どう思う？", "AとBどっちがいい？"), simple one-shot Q&A, design discussions where user judgment is needed at each step.
If a "Loop hint" annotation is present, you SHOULD set goal_condition.

Constraints on goal_condition:
- ONLY include conditions Claude can autonomously verify (test output, lint result, build exit code). Never include human actions (PR merge, deploy approval, manual review).
- Prefer the NEXT verifiable milestone, not the final outcome. "PR created" not "PR merged and deployed".
- If the assistant is waiting for a background task (Workflow, Agent, Monitor) to complete, APPROVE stop — the notification mechanism will re-invoke Claude automatically. Do NOT set a goal for waiting.
- REACTOR conditions: if the completion condition is driven by an EXTERNAL system Claude does not control — CI result, deploy/rollout/release completion, pipeline or job finishing, PR merge/review/approval, production rollout — do NOT set goal_condition. Set should_stop=true and in reason recommend arming a Monitor (e.g. a \`gh pr checks <n>\` poll that emits on terminal state and then exits) so its notification re-invokes Claude. Polling such conditions through the stop-gate busy-loops and wastes turns. (Local test/lint/build/typecheck are NOT reactor — those are actor goals Claude drives itself.)

## Complex Task Detection
When the task is complex (multi-file changes, multi-round reviews, large refactoring) AND goal is not yet active AND no rubric annotation is present: set should_stop=false and include in reason: "このタスクはゴール定義が有効。ユーザーに完了条件を確認してから開始すべき。" Do NOT set should_stop=true in this case — the clarification prompt must reach Claude.
If a "Rubric" annotation IS present, use the rubric content as the goal condition directly.

## Human Intervention Points
When an active goal is running and the transcript shows any of these, set should_stop=true with reason explaining the blocker:
- Destructive operations ahead: force push, production deploy, database migration, secret rotation
- User judgment required: design choice between alternatives, scope decision, priority call
- Same test/lint failure pattern appearing 3+ times with no new approach
- Scope drift: work is diverging from the original goal condition

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

// ─── 検証 receipt（verification.json）の鮮度付き読取 ───

type VerifyStatus = "PASS" | "FAIL" | "STALE" | "NONE";

interface VerifyResult {
  status: VerifyStatus;
  rawStatus: string | null; // receipt.status を生で保持（annotation の status 区別用）
  verifiedAtMs: number | null; // Date.parse(verified_at)。goal との時間相関判定に使う
}

/**
 * ai/state/verification.json を読み、現在 HEAD と head_sha を照合して鮮度判定する。
 * - PASS: status=PASS（大小無視で正規化）かつ head_sha が現在 HEAD と一致（鮮度確認済）
 * - FAIL: head_sha 一致だが status!=PASS（rawStatus に生の値を残す）
 * - STALE: head_sha 不一致、または sha 取得不能（空文字 collision を防ぐ）
 * - NONE: receipt なし／読取不可
 * rawStatus / verifiedAtMs は短絡判定(verified_at>=setAt)と annotation の status 区別に使う。
 */
async function getVerificationStatus(projectDir: string): Promise<VerifyResult> {
  try {
    const verifyContent = await Deno.readTextFile(
      `${projectDir}/ai/state/verification.json`,
    );
    const verify = JSON.parse(verifyContent);
    const rawStatus = typeof verify.status === "string" ? verify.status : null;
    const parsed = typeof verify.verified_at === "string"
      ? Date.parse(verify.verified_at)
      : NaN;
    const verifiedAtMs = Number.isNaN(parsed) ? null : parsed;
    const sha = await getGitShortHead(projectDir);
    // sha 取得不能(空)や head_sha 空は鮮度を確立できない → STALE（決定的短絡をさせない）
    if (!sha || !verify.head_sha || verify.head_sha !== sha) {
      return { status: "STALE", rawStatus, verifiedAtMs };
    }
    const pass = (rawStatus ?? "").trim().toUpperCase() === "PASS";
    return { status: pass ? "PASS" : "FAIL", rawStatus, verifiedAtMs };
  } catch {
    return { status: "NONE", rawStatus: null, verifiedAtMs: null };
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
    const projectDir = Deno.env.get("CLAUDE_PROJECT_DIR") ?? Deno.cwd();
    const hlog = (event: string, detail = "") =>
      harnessLog("stop-hook", event, detail, input.session_id ?? "");

    // ─── tool-call タグ破損（Opus 4.8）の事後自動復旧 ───
    // harness の auto-retry で復旧せずターン終端に破損が残った場合、block-to-continue で
    // 「前置きゼロで出し直せ」+抽出コマンドを注入して自動復旧させる。verbatim 再送は再破損
    // するため no-preamble 指示が要。復旧できず同一破損を繰り返す場合は2回で give-up して
    // Sonnet 切替を促す(無限ループ防止)。goal/stop_hook_active 判定より前に置き、常に検査する。
    if (input.transcript_path) {
      const recPath = `/tmp/claude-toolcall-recovery-${
        djb2(input.transcript_path)
      }.json`;
      // last_assistant_message は harness が同期的に渡す値でファイル読み直しのレースが無い。
      // transcript ファイルの再読込は、同一応答の thinking/text ブロックが別 JSONL 行に分割
      // 書き込みされる際、最新の text 行がまだ flush されておらず検知漏れするレースが実際に
      // 観測された(honeybadger セッションで goal 通知が先に出て復旧が不発になった実例)。
      // まず lastMessage を優先チェックし、非マッチ時のみファイルベースにフォールバックする。
      const leak = detectToolcallLeakInText(lastMessage) ??
        await detectUnrecoveredLeak(input.transcript_path);
      if (leak) {
        let prev: { sig: string; count: number } | null = null;
        try {
          prev = JSON.parse(await Deno.readTextFile(recPath));
        } catch {
          // 初回
        }
        const count = prev && prev.sig === leak.sig ? prev.count + 1 : 1;
        if (count <= 2) {
          try {
            await Deno.writeTextFile(
              recPath,
              JSON.stringify({ sig: leak.sig, count }),
            );
          } catch {
            // best-effort
          }
          const cmdBlock = leak.command
            ? `\n\n再実行すべき内容:\n\`\`\`\n${leak.command.slice(0, 1500)}\n\`\`\``
            : "";
          // Bash 限定: sonnet-bash-runner(model:sonnet固定subagent)への委譲を提案する。
          // 直接 Bash を出し直す(=同じ破損しやすい経路のリトライ)より、Sonnet実行に切り替える方が
          // 確実(このセッション実績でSonnetのleakは0件)。Write/Edit/Agent等は委譲先が無いため対象外。
          await hlog("block:toolcall_leak", leak.tool);
          const delegateHint = leak.tool === "Bash"
            ? " 可能なら直接出し直さず、sonnet-bash-runner subagent(Agent tool)にこのコマンドの実行を委譲することを検討せよ(Sonnet 5固定でこの破損が起きない)。"
            : "";
          console.log(
            JSON.stringify({
              decision: "block",
              reason:
                `⚠️ tool-call タグ破損を検知（${leak.tool} が未実行のまま text に漏洩）。` +
                `次の応答は**前置きテキストを一切書かず、先頭トークンから ${leak.tool} tool call を出し直す**こと` +
                `（このバグは前置きゼロで回避できる。verbatim 再送・インライン heredoc は再破損するので、` +
                `重いコマンドは bin/ ヘルパーかスクリプトファイル経由にする）。${delegateHint}${cmdBlock}`,
            }),
          );
          Deno.exit(0);
        }
        // give-up: 復旧失敗。state をクリア・通知して通常フローへ委ねる
        try {
          await Deno.remove(recPath);
        } catch {
          // ok
        }
        notifyStop("tool-call破損の自動復旧に失敗。/model sonnet 切替を推奨");
      } else {
        // 破損なし → 復旧カウンタをクリア
        try {
          await Deno.remove(recPath);
        } catch {
          // ok
        }
      }
    }

    // verification receipt は最大1回だけ読む（短絡判定と annotation で共有）。
    // 早期 exit パス(background待機/stop_hook_active)では呼ばれず git コストを払わない。
    let _verify: VerifyResult | null = null;
    const getVerify = async (): Promise<VerifyResult> =>
      _verify ??= await getVerificationStatus(projectDir);

    // ─── Goal 状態管理 ───
    const gPath = input.transcript_path
      ? goalStatePath(input.transcript_path)
      : null;

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

    // ─── バックグラウンドタスク待機検出 ───
    // task-notification 機構が完了時に Claude を再起動するため、待機中は stop を許可。
    // Goal state は保持し、再起動後に評価を再開する。
    const waitingByText = isWaitingForBackground(lastMessage);
    const waitingByTranscript = input.transcript_path
      ? await hasRecentBackgroundToolCalls(input.transcript_path)
      : false;

    if (waitingByText || waitingByTranscript) {
      if (goalState && gPath) {
        await writeGoalState(gPath, goalState);
      }
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

      // エラーフィンガープリント追跡（同一エラーパターン3回で stuck 判定）
      if (!goalState.errorHashes) goalState.errorHashes = [];
      const errorFp = extractErrorFingerprint(lastMessage);
      if (errorFp) {
        goalState.errorHashes.push(errorFp);
        if (goalState.errorHashes.length > 10) {
          goalState.errorHashes = goalState.errorHashes.slice(-10);
        }
      } else {
        goalState.errorHashes = [];
      }

      if (
        goalState.targetTurns && goalState.iterations > goalState.targetTurns
      ) {
        notifyStop("ゴール中断: ターン上限到達");
        await hlog("block:goal_turn_limit");
        await clearGoalState(gPath);
        console.log(
          JSON.stringify({
            decision: "block",
            reason:
              `[Goal: ${goalState.condition}] ターン上限 ${goalState.targetTurns} に到達。進捗状況と未達点をユーザーに報告して終了せよ。`,
          }),
        );
        Deno.exit(0);
      }

      // 同一出力の空転（5回）
      const spinDetected = detectSpin(goalState.msgHashes);
      if (spinDetected) {
        const spinCount = countConsecutiveIdentical(goalState.msgHashes);
        if (spinCount >= 5) {
          notifyStop("ゴール中断: 空転検知");
          await hlog("block:goal_spin");
          await clearGoalState(gPath);
          console.log(
            JSON.stringify({
              decision: "block",
              reason:
                `[Goal: ${goalState.condition}] 空転が ${spinCount} 回連続。ユーザーに状況を報告し、別のアプローチを提案して終了せよ。`,
            }),
          );
          Deno.exit(0);
        }
      }

      // 同一エラーパターンの stuck（3回連続）
      if (
        detectSpin(goalState.errorHashes.slice(-3)) &&
        goalState.errorHashes.length >= 3
      ) {
        const errCount = countConsecutiveIdentical(goalState.errorHashes);
        if (errCount >= 3) {
          notifyStop("ゴール中断: 同一エラー反復");
          await hlog("block:goal_error_stuck");
          await clearGoalState(gPath);
          console.log(
            JSON.stringify({
              decision: "block",
              reason:
                `[Goal: ${goalState.condition}] 同一エラーパターンが ${errCount} 回連続。別のアプローチを試すか、ユーザーに相談して終了せよ。`,
            }),
          );
          Deno.exit(0);
        }
      }

      // ─── 案A: actor ゴールは verification receipt の fresh PASS で決定的に短絡 ───
      // Haiku のトランスクリプト推測判定を排し、out-of-band の verify receipt で決定的に停止する。
      // 偽停止を防ぐため次を全て要求する:
      //  - status PASS（head_sha が現在 HEAD と一致＝鮮度確認済）
      //  - receipt がこのゴール設定後に生成された（verified_at >= setAt; 旧タスクの receipt 流用を排除）
      //  - working tree clean（receipt 後の未コミット編集で壊れていない; ai/ は gitignore 済で dirty 計上外）
      // 1つでも欠ければ短絡せず Haiku 判定にフォールバックする。reactor 条件は対象外。
      if (
        classifyVerifiableGoal(goalState.condition) &&
        !detectReactorGoal(goalState.condition)
      ) {
        const v = await getVerify();
        const freshForGoal = v.verifiedAtMs !== null &&
          v.verifiedAtMs >= goalState.setAt;
        if (v.status === "PASS" && freshForGoal) {
          const dirty = await getGitDirtyCount(projectDir);
          if (dirty === 0) {
            notifyStop(`検証通過: ${goalState.condition}`);
            await hlog("allow:goal_verified");
            await clearGoalState(gPath);
            Deno.exit(0); // stop を許可（決定的にゴール達成）
          }
        }
      }

      // Exponential backoff: メッセージ内容が安定している間は Haiku 評価頻度を下げる
      // 出力が変化したら即座に評価（進捗があった可能性）
      if (goalState.iterations > 2) {
        const hashes = goalState.msgHashes;
        const msgChanged = hashes.length >= 2 &&
          hashes[hashes.length - 1] !== hashes[hashes.length - 2];

        if (!msgChanged) {
          const backoffExp = Math.min(
            Math.floor(Math.log2(goalState.iterations)),
            5,
          ); // cap: 2^5=32
          const interval = 2 ** backoffExp;
          if (goalState.iterations % interval !== 0) {
            await hlog("block:goal_backoff");
            await writeGoalState(gPath, goalState);
            console.log(
              JSON.stringify({
                decision: "block",
                reason:
                  `[Goal: ${goalState.condition}] 進行中（eval backoff: ${interval}ターン毎）`,
              }),
            );
            Deno.exit(0);
          }
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
      const spinCount = spinDetected
        ? countConsecutiveIdentical(goalState.msgHashes)
        : 0;
      let goalNote =
        `Active goal（${goalState.iterations}ターン目）: ${goalState.condition}`;
      if (spinDetected) {
        goalNote +=
          `\n⚠️ SPIN WARNING: ${spinCount}回連続で同様の出力。アプローチ変更が必要。`;
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

    // evaluator PASS → distill-memory 促し
    try {
      const gatePath = `${projectDir}/ai/state/workflow-gate.json`;
      const gateContent = await Deno.readTextFile(gatePath);
      const gate = JSON.parse(gateContent);
      if (gate.evaluator?.status === "PASS") {
        const memDir = `${projectDir}/ai/memory`;
        let hasRecentMemory = false;
        try {
          for await (const entry of Deno.readDir(memDir)) {
            if (entry.isFile && entry.name.endsWith(".md")) {
              const stat = await Deno.stat(`${memDir}/${entry.name}`);
              if (stat.mtime && Date.now() - stat.mtime.getTime() < 3600_000) {
                hasRecentMemory = true;
                break;
              }
            }
          }
        } catch {
          // memory dir doesn't exist yet
        }
        if (!hasRecentMemory) {
          annotations.push(
            "Evaluator PASS: distill-memory skill を発動して教訓を記録してから終了すること。記録すべき教訓がなければスキップ可。",
          );
        }
      }
    } catch {
      // workflow-gate なし — 通常動作
    }

    // 検証状態（getVerify に集約。短絡判定と同一 receipt を共有。FAIL は生 status を保持）
    const vres = await getVerify();
    annotations.push(
      vres.status === "PASS"
        ? "Verification evidence: PASS (fresh, matching HEAD)"
        : vres.status === "STALE"
        ? "Verification evidence: STALE (HEAD changed since verification)"
        : vres.status === "FAIL"
        ? `Verification evidence: ${vres.rawStatus ?? "FAIL"}`
        : "Verification evidence: NONE",
    );

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
          annotations.push(
            `Context health: HIGH USAGE (${health.context_pct}%) — consider --fork-session`,
          );
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
          content: `<transcript>\n${
            transcript || lastMessage
          }\n</transcript>${annotationBlock}`,
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
      await hlog("allow:stop");
      if (goalState && gPath) {
        await clearGoalState(gPath);
      }
      if (decision.done_summary) {
        notifyStop(decision.done_summary);
      }
    } else {
      // 継続: ゴール自動抽出
      if (gPath && decision.goal_condition && !goalState) {
        // 案B: 外部駆動条件は busy-loop gate 化せず Monitor へ誘導（Haiku が見落とした場合の保険）。
        // actor(ローカル検証可能)を優先: "production build"/"release build" 等の混在語は
        // reactor 誤判定させず actor として goal 追跡する。
        if (
          detectReactorGoal(decision.goal_condition) &&
          !classifyVerifiableGoal(decision.goal_condition)
        ) {
          await hlog("block:goal_reactor_monitor");
          console.log(
            JSON.stringify({
              decision: "block",
              reason:
                `[外部駆動: ${decision.goal_condition}] この完了条件は外部システム（CI/デプロイ/ジョブ等）が駆動する。stop-gate でのポーリングはターンを浪費する。Monitor ツールで監視スクリプト（例: 'gh pr checks <n>' を terminal state で emit して exit）を arm し、event 到来で対応せよ。監視を arm したら停止してよい。`,
            }),
          );
          Deno.exit(0);
        }
        const targetTurns = userRequest
          ? extractTargetTurns(userRequest)
          : null;
        const initErrorFp = extractErrorFingerprint(lastMessage);
        await writeGoalState(gPath, {
          condition: decision.goal_condition,
          userHash: djb2(userRequest || ""),
          setAt: Date.now(),
          iterations: 1,
          targetTurns,
          msgHashes: [djb2(lastMessage.slice(0, 500))],
          errorHashes: initErrorFp ? [initErrorFp] : [],
        });
      }

      await hlog("block:stop_gate", (decision.reason ?? "").slice(0, 120));
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
