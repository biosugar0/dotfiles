#!/usr/bin/env -S deno run --allow-read --allow-run --allow-env --allow-write

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
  };
  exceeds_200k_tokens?: boolean;
  vim?: { mode?: string };
  agent?: { name?: string };
};

const RESET = "\x1b[0m";
const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";

const CACHE_FILE = "/tmp/cc-statusline-git-cache";
const CACHE_MAX_AGE_MS = 5000;

async function getGitBranch(): Promise<string> {
  try {
    const stat = await Deno.stat(CACHE_FILE).catch(() => null);
    if (stat?.mtime && Date.now() - stat.mtime.getTime() < CACHE_MAX_AGE_MS) {
      return await Deno.readTextFile(CACHE_FILE);
    }
  } catch {
    // cache miss
  }

  const branch = await fetchGitBranch();
  try {
    await Deno.writeTextFile(CACHE_FILE, branch);
  } catch {
    // ignore cache write failure
  }
  return branch;
}

async function fetchGitBranch(): Promise<string> {
  try {
    const { success } = await new Deno.Command("git", {
      args: ["rev-parse"],
      stdout: "null",
      stderr: "null",
    }).output();
    if (!success) return "";

    const { stdout } = await new Deno.Command("git", {
      args: ["branch", "--show-current"],
      stdout: "piped",
      stderr: "null",
    }).output();
    const branch = new TextDecoder().decode(stdout).trim();
    if (branch) return branch;

    const hashResult = await new Deno.Command("git", {
      args: ["rev-parse", "--short", "HEAD"],
      stdout: "piped",
      stderr: "null",
    }).output();
    const hash = new TextDecoder().decode(hashResult.stdout).trim();
    if (hash) return `HEAD (${hash})`;
  } catch {
    // ignore
  }
  return "";
}

function buildContextBar(pct: number): string {
  const width = 10;
  const filled = Math.round((pct * width) / 100);
  const empty = width - filled;
  const color = pct >= 90 ? RED : pct >= 70 ? YELLOW : GREEN;
  return `${color}${"█".repeat(filled)}${"░".repeat(empty)} ${pct}%${RESET}`;
}

function formatDuration(ms: number): string {
  const sec = Math.floor(ms / 1000);
  return `${Math.floor(sec / 60)}m${sec % 60}s`;
}

// ANSI escape codeを除いた可視文字幅を計算
function visibleLength(s: string): number {
  return s.replace(/\x1b\[[0-9;]*m/g, "").length;
}

async function main() {
  const stdin = await readAll(Deno.stdin);
  const input: StatusLineInput = JSON.parse(new TextDecoder().decode(stdin));

  const model = input.model?.display_name ?? "Unknown";
  const dir = input.workspace?.current_dir?.split("/").pop() ?? ".";
  const pct = Math.round(input.context_window?.used_percentage ?? 0);
  const duration = input.cost?.total_duration_ms ?? 0;
  const exceeds200k = input.exceeds_200k_tokens ?? false;
  const gitBranch = await getGitBranch();

  const infoParts = [`${CYAN}󰛩  ${model}${RESET}`, `  ${dir}`];
  if (gitBranch) infoParts.push(`󰘬  ${gitBranch}`);
  const infoStr = infoParts.join(" | ");

  const warn = exceeds200k ? ` ${RED}⚠ 200k+${RESET}` : "";
  const contextParts = [
    `${buildContextBar(pct)}${warn}`,
    `󰥔 ${formatDuration(duration)}`,
  ];
  const contextStr = contextParts.join(" | ");

  let cols = 80;
  try {
    cols = Deno.consoleSize().columns;
  } catch {
    cols = parseInt(Deno.env.get("COLUMNS") ?? "80", 10) || 80;
  }
  const singleLine = `${infoStr} | ${contextStr}`;

  if (visibleLength(singleLine) <= cols) {
    console.log(singleLine);
  } else {
    console.log(infoStr);
    console.log(contextStr);
  }
}

if (import.meta.main) {
  main().catch(() => Deno.exit(1));
}
