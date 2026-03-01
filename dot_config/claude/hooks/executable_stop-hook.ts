#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env

import Anthropic from "npm:@anthropic-ai/sdk";
import { readAll } from "jsr:@std/io@0.224/read-all";

interface StopHookInput {
  stop_hook_active?: boolean;
  last_assistant_message?: string;
}

interface StopDecisionInput {
  should_stop: boolean;
  reason: string;
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

Rules:
- APPROVE stop if: last_assistant_message asks user a question, reports completion, or awaits input; all TODOs done
- BLOCK stop (continue) only if: last_assistant_message shows mid-task work with clear next steps AND incomplete TODOs that AI can finish without user input
- Default: approve stop

Call stop_decision with your judgment.`;

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

    const response = await client.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 256,
      system: SYSTEM_PROMPT,
      tools: [STOP_DECISION_TOOL],
      tool_choice: { type: "tool", name: "stop_decision" },
      messages: [
        {
          role: "user",
          content: `Evaluate this last assistant message:\n\n${lastMessage}`,
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
