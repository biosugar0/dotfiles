#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env

import Anthropic from "npm:@anthropic-ai/sdk";
import {
  loadCounterexamples,
  STOP_DECISION_TOOL,
  SYSTEM_PROMPT,
} from "./executable_stop-hook.ts";
import { resolveAnthropicAuth } from "./lib/session-context.ts";

interface JudgeEvalFixture {
  name: string;
  description: string;
  transcript: string;
  annotations: string[];
  expected: {
    should_stop: boolean;
  };
  source: string;
}

interface StopDecision {
  should_stop?: boolean;
  reason?: string;
  evidence_source?: string;
  confidence?: string | number;
}

interface CliOptions {
  withCounterexamples: boolean;
  only?: string;
}

interface EvalAuth {
  authToken: string;
}

const FIXTURE_DIR = new URL("./data/judge-eval/", import.meta.url);

function parseArgs(args: string[]): CliOptions {
  const options: CliOptions = { withCounterexamples: false };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--with-counterexamples") {
      options.withCounterexamples = true;
    } else if (arg === "--only") {
      const name = args[++i];
      if (!name) throw new Error("--only requires a fixture name");
      options.only = name;
    } else if (arg.startsWith("--only=")) {
      options.only = arg.slice("--only=".length);
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  return options;
}

async function loadFixtures(only?: string): Promise<JudgeEvalFixture[]> {
  const fixtures: JudgeEvalFixture[] = [];
  for await (const entry of Deno.readDir(FIXTURE_DIR)) {
    if (!entry.isFile || !entry.name.endsWith(".json")) continue;
    const url = new URL(entry.name, FIXTURE_DIR);
    const fixture = JSON.parse(
      await Deno.readTextFile(url),
    ) as JudgeEvalFixture;
    fixtures.push(fixture);
  }
  fixtures.sort((a, b) => a.name.localeCompare(b.name));
  return only ? fixtures.filter((fixture) => fixture.name === only) : fixtures;
}

function buildUserMessage(fixture: JudgeEvalFixture): string {
  const annotationBlock = fixture.annotations.length
    ? `\n\n---\n${fixture.annotations.join("\n")}`
    : "";
  return `<transcript>\n${
    fixture.transcript.replaceAll("</transcript>", "<\\/transcript>")
  }\n</transcript>${annotationBlock}`;
}

function field(value: unknown): string {
  if (value === undefined || value === null || value === "") return "n/a";
  return String(value).replaceAll("\n", "\\n");
}

async function resolveEvalAuth(): Promise<EvalAuth | null> {
  const auth = await resolveAnthropicAuth();
  if (auth) return auth;

  const envToken = Deno.env.get("CLAUDE_CODE_OAUTH_TOKEN") ??
    Deno.env.get("ANTHROPIC_AUTH_TOKEN");
  return envToken ? { authToken: envToken } : null;
}

async function runFixture(
  client: Anthropic,
  system: string,
  fixture: JudgeEvalFixture,
): Promise<StopDecision> {
  const response = await client.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 512,
    system,
    tools: [STOP_DECISION_TOOL],
    tool_choice: { type: "tool", name: "stop_decision" },
    messages: [
      {
        role: "user",
        content: buildUserMessage(fixture),
      },
    ],
  });

  const toolBlock = response.content.find((block) => block.type === "tool_use");
  if (!toolBlock || toolBlock.type !== "tool_use") {
    return { reason: "stop_decision tool_use was not returned" };
  }
  return toolBlock.input as StopDecision;
}

async function main(): Promise<void> {
  let options: CliOptions;
  try {
    options = parseArgs(Deno.args);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(2);
  }

  const auth = await resolveEvalAuth();
  if (!auth) {
    console.error("auth なし");
    Deno.exit(2);
  }

  const fixtures = await loadFixtures(options.only);
  if (options.only && fixtures.length === 0) {
    console.error(`fixture not found: ${options.only}`);
    Deno.exit(2);
  }

  const client = new Anthropic({
    authToken: auth.authToken,
    apiKey: null,
    defaultHeaders: { "anthropic-beta": "oauth-2025-04-20" },
  });
  const system = SYSTEM_PROMPT +
    (options.withCounterexamples ? await loadCounterexamples() : "");

  let passed = 0;
  for (const fixture of fixtures) {
    const actual = await runFixture(client, system, fixture);
    const ok = actual.should_stop === fixture.expected.should_stop;
    if (ok) passed++;
    console.log(
      `${
        ok ? "PASS" : "FAIL"
      } ${fixture.name}: expected=${fixture.expected.should_stop} actual=${
        field(actual.should_stop)
      } evidence_source=${field(actual.evidence_source)} confidence=${
        field(actual.confidence)
      }`,
    );
    if (!ok && actual.reason) {
      console.log(`  reason=${actual.reason}`);
    }
  }

  const accuracy = fixtures.length === 0 ? 0 : (passed / fixtures.length) * 100;
  console.log(
    `Accuracy: ${passed}/${fixtures.length} (${accuracy.toFixed(1)}%)`,
  );

  if (passed !== fixtures.length) Deno.exit(1);
}

if (import.meta.main) {
  await main();
}
