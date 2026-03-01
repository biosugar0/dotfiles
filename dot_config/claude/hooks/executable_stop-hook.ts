#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env

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
- Default: approve stop

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
    const sessionToken = Deno.env.get("CLAUDE_CODE_SESSION_ACCESS_TOKEN");
    if (!apiKey && !sessionToken) {
      Deno.exit(0);
    }
    const client = apiKey
      ? new Anthropic({ apiKey })
      : new Anthropic({
          authToken: sessionToken,
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

    const response = await client.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 256,
      system: SYSTEM_PROMPT,
      tools: [STOP_DECISION_TOOL],
      tool_choice: { type: "tool", name: "stop_decision" },
      messages: [
        {
          role: "user",
          content: `${userContext}Claude's last assistant message:\n\n${lastMessage}`,
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
