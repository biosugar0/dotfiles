#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env --allow-run

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

interface StopDecisionInput {
  should_stop: boolean;
  reason: string;
  done_summary?: string;
}

interface TranscriptEntry {
  type: string;
  message?: {
    content: string | Array<{ type: string; text?: string }>;
  };
}

/**
 * ユーザーの直近リクエストに「明示的な反復/ループ指示」があるか高精度に判定する。
 * 検出時は stop-hook が「終了条件が満たされるまで継続を強制」する自動 goal 挙動に入る
 * (手動 /goal なしでループ駆動する。ただし CC の連続 block 上限 8 回で頭打ち=長いループは /goal を使う)。
 * 誤爆(=本当はループでない指示で延々 block)を避けるため、語のホワイトリストで絞る。
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
          "Only when should_stop=true: a 15-40 character Japanese summary of what Claude actually did this turn (for audio notification). Use noun phrases. Omit entirely when should_stop=false.",
      },
    },
    required: ["should_stop", "reason"],
  },
};

const SYSTEM_PROMPT = `You evaluate whether Claude Code should stop or continue.

You will receive:
1. The user's recent request (what they asked Claude to do)
2. Claude's last assistant message (the most recent response)

Rules:
- APPROVE stop if: task is complete, Claude asks user a question, reports completion, or awaits input
- BLOCK stop (continue) only if: Claude's last message shows mid-task work with clear next steps AND there are incomplete tasks that AI can finish without user input
- If the user's request was a question and Claude answered it, APPROVE stop
- If "Verification evidence: NONE" or "STALE" and Claude claims completion of code changes, suggest running verification but do not hard-block (docs-only or config-only changes may not need verification)
- If "Verification evidence: FAIL", BLOCK (continue) — verification failed, must fix before completing
- If "Verification evidence: PASS", factor it positively into stop decision
- If "Context health: HIGH USAGE" and work is incomplete, suggest --fork-session in the reason
- Default: approve stop

When you APPROVE stop (should_stop=true), also set done_summary: a 15-40 character Japanese phrase describing what Claude actually DID this turn (not what it will do next). Use concise noun phrases. Examples: "sayラッパー作成と動作確認", "stop hookに音声要約を追加", "dotfilesのCLAUDE.md修正". Omit done_summary when should_stop=false.

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

async function main(): Promise<void> {
  try {
    const raw = new TextDecoder().decode(await readAll(Deno.stdin));
    const input: StopHookInput = JSON.parse(raw);

    // 反復ディレクティブ検出のため先にユーザー直近リクエストを読む
    const userRequest = input.transcript_path
      ? await getLastUserRequest(input.transcript_path)
      : null;
    const loopActive = userRequest ? detectLoopDirective(userRequest) : false;

    // 通常は stop_hook_active で早期 exit(2連続 block 防止の慣習)。
    // ただし反復ディレクティブが有効な間は継続を駆動するため早期 exit しない
    // (終了条件が満たされるか、CC の連続 block 上限=既定8回に達するまで block し続ける)。
    if (input.stop_hook_active && !loopActive) {
      Deno.exit(0);
    }

    const lastMessage = input.last_assistant_message || "";
    if (!lastMessage) {
      Deno.exit(0);
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

    // userContext は先に取得済みの userRequest から構築
    let userContext = "";
    if (userRequest) {
      // Truncate to keep token usage reasonable
      const truncated =
        userRequest.length > 500
          ? userRequest.slice(0, 500) + "..."
          : userRequest;
      userContext = `User's recent request:\n${truncated}\n\n`;
    }

    // Check for verification evidence
    let verificationNote = "";
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
        verificationNote = "\n\nVerification evidence: PASS (fresh, matching HEAD)";
      } else if (verify.head_sha !== currentSha) {
        verificationNote = "\n\nVerification evidence: STALE (HEAD changed since verification)";
      } else {
        verificationNote = `\n\nVerification evidence: ${verify.status}`;
      }
    } catch {
      verificationNote = "\n\nVerification evidence: NONE (no verification.json found)";
    }

    // Session health check (context anxiety detection)
    let healthNote = "";
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
          healthNote = `\n\nContext health: HIGH USAGE (${health.context_pct}%) — consider recommending --fork-session if work is incomplete`;
        } else if (health.context_pct >= 70) {
          healthNote = `\n\nContext health: ELEVATED (${health.context_pct}%)`;
        }
      }
    } catch {
      // No health data available
    }

    // 反復ディレクティブが有効なら、終了条件の証拠が無い限り継続を強制する指示を足す
    const loopSnippet = loopActive && userRequest
      ? loopDirectiveSnippet(userRequest)
      : "";
    const loopNote = loopActive
      ? `\n\nLOOP DIRECTIVE ACTIVE: ユーザーの直近リクエストに明示的な反復/ループ指示がある${
          loopSnippet ? `（該当: "${loopSnippet}"）` : ""
        }。should_stop は **false(継続)** にすること。例外は、Claude の最終メッセージに「ループの終了条件が満たされた具体的証拠」がある場合のみ — 例: レビュアー/codex が指摘ゼロを報告("指摘なし" / "no findings" / "0 件")、テスト全通過、目標状態に到達した確証。完了っぽい要約だけで証拠が無ければ継続(false)。なお、その指示がこの会話の進行中の反復タスクに実際には対応していない(既に終了/別件)なら stop を承認(true)してよい。`
      : "";

    const response = await client.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 256,
      system: SYSTEM_PROMPT,
      tools: [STOP_DECISION_TOOL],
      tool_choice: { type: "tool", name: "stop_decision" },
      messages: [
        {
          role: "user",
          content: `${userContext}Claude's last assistant message:\n\n${lastMessage}${verificationNote}${healthNote}${loopNote}`,
        },
      ],
    });

    const toolBlock = response.content.find((b) => b.type === "tool_use");
    if (!toolBlock || toolBlock.type !== "tool_use") {
      Deno.exit(0);
    }

    const decision = toolBlock.input as StopDecisionInput;

    if (!decision.should_stop) {
      console.log(
        JSON.stringify({
          decision: "block",
          reason: decision.reason || "タスクが未完了",
        }),
      );
    } else if (decision.done_summary) {
      const home = Deno.env.get("HOME");
      const summary = decision.done_summary;
      const cwd = Deno.env.get("CLAUDE_PROJECT_DIR") ?? Deno.cwd();
      const proj = cwd.split("/").pop() ?? "";
      const title = proj ? `[Stop] ${proj}` : "[Stop] Claude Code";

      if (home) {
        // OSC 777 toast — CLAUDE_SAY_MUTE でも出す (visual only)
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

        // 音声 — CLAUDE_SAY_MUTE=1 ならスキップ
        if (Deno.env.get("CLAUDE_SAY_MUTE") !== "1") {
          try {
            new Deno.Command(`${home}/.config/claude/bin/say-notify`, {
              args: [summary],
              stdin: "null",
              stdout: "null",
              stderr: "null",
            }).spawn();
          } catch {
            // speech is best-effort; never block stop
          }
        }
      }
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
