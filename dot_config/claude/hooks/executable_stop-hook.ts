#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env --allow-run

import Anthropic from "npm:@anthropic-ai/sdk";
import { readAll } from "jsr:@std/io@0.224/read-all";

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
async function getLastUserRequest(
  transcriptPath: string,
): Promise<string | null> {
  try {
    const content = await Deno.readTextFile(transcriptPath);
    const lines = content.trimEnd().split("\n");

    // Scan from the end to find the last user message with actual text
    for (let i = lines.length - 1; i >= 0; i--) {
      try {
        const entry: TranscriptEntry = JSON.parse(lines[i]);
        if (entry.type !== "user" || !entry.message?.content) continue;

        const msgContent = entry.message.content;
        if (typeof msgContent === "string") {
          const text = msgContent.trim();
          if (text && !text.startsWith("[Request interrupted")) return text;
          continue;
        }

        if (Array.isArray(msgContent)) {
          // Extract text blocks, skip tool_result
          const texts = msgContent
            .filter(
              (b) =>
                b.type === "text" &&
                b.text &&
                !b.text.startsWith("[Request interrupted"),
            )
            .map((b) => b.text!.trim())
            .filter((t) => t.length > 0);
          if (texts.length > 0) return texts.join("\n");
        }
      } catch {
        // skip malformed lines
      }
    }
  } catch {
    // transcript read failure is non-fatal
  }
  return null;
}

async function getTokenFromKeychain(): Promise<string | null> {
  try {
    const dumpCmd = new Deno.Command("security", {
      args: ["dump-keychain"],
      stdout: "piped",
      stderr: "null",
    });
    const dumpOutput = await dumpCmd.output();
    const text = new TextDecoder().decode(dumpOutput.stdout);
    const services: string[] = [];
    for (const m of text.matchAll(/"svce"<blob>="(Claude Code-credentials[^"]*)"/g)) {
      if (!services.includes(m[1])) services.push(m[1]);
    }
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
        if (oauth.expiresAt && oauth.expiresAt < Date.now()) continue;
        return oauth.accessToken;
      } catch {
        continue;
      }
    }
  } catch {
    // ignore
  }
  return null;
}

async function main(): Promise<void> {
  try {
    const raw = new TextDecoder().decode(await readAll(Deno.stdin));
    const input: StopHookInput = JSON.parse(raw);

    if (input.stop_hook_active) {
      Deno.exit(0);
    }

    const lastMessage = input.last_assistant_message || "";
    if (!lastMessage) {
      Deno.exit(0);
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    const sessionToken = Deno.env.get("CLAUDE_CODE_OAUTH_TOKEN");
    const keychainToken = (!apiKey && !sessionToken) ? await getTokenFromKeychain() : null;
    if (!apiKey && !sessionToken && !keychainToken) {
      Deno.exit(0);
    }
    const client = apiKey
      ? new Anthropic({ apiKey })
      : new Anthropic({
          authToken: sessionToken || keychainToken,
          apiKey: null,
          defaultHeaders: { "anthropic-beta": "oauth-2025-04-20" },
        });

    // Extract user's recent request from transcript
    let userContext = "";
    if (input.transcript_path) {
      const userRequest = await getLastUserRequest(input.transcript_path);
      if (userRequest) {
        // Truncate to keep token usage reasonable
        const truncated =
          userRequest.length > 500
            ? userRequest.slice(0, 500) + "..."
            : userRequest;
        userContext = `User's recent request:\n${truncated}\n\n`;
      }
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

    const response = await client.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 256,
      system: SYSTEM_PROMPT,
      tools: [STOP_DECISION_TOOL],
      tool_choice: { type: "tool", name: "stop_decision" },
      messages: [
        {
          role: "user",
          content: `${userContext}Claude's last assistant message:\n\n${lastMessage}${verificationNote}${healthNote}`,
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
    } else if (
      decision.done_summary &&
      Deno.env.get("CLAUDE_SAY_MUTE") !== "1"
    ) {
      // Fire-and-forget audio notification of what was done this turn.
      // say-notify escapes the cage sandbox via launchctl asuser.
      try {
        const home = Deno.env.get("HOME");
        if (home) {
          new Deno.Command(`${home}/.config/claude/bin/say-notify`, {
            args: [decision.done_summary],
            stdin: "null",
            stdout: "null",
            stderr: "null",
          }).spawn();
        }
      } catch {
        // speech is best-effort; never block stop
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

main();
