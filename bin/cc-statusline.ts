#!/usr/bin/env -S deno run --allow-read --allow-run --allow-env

import { readAll } from "jsr:@std/io@0.224/read-all";

async function getGitBranch(): Promise<string> {
  try {
    const isGitRepo = new Deno.Command("git", {
      args: ["rev-parse"],
      stdout: "null",
      stderr: "null",
    });
    const { success } = await isGitRepo.output();

    if (!success) return "";

    const branchCmd = new Deno.Command("git", {
      args: ["branch", "--show-current"],
      stdout: "piped",
      stderr: "null",
    });
    const { stdout } = await branchCmd.output();
    const branch = new TextDecoder().decode(stdout).trim();

    if (branch) {
      return branch;
    }

    const hashCmd = new Deno.Command("git", {
      args: ["rev-parse", "--short", "HEAD"],
      stdout: "piped",
      stderr: "null",
    });
    const hashResult = await hashCmd.output();
    const commitHash = new TextDecoder().decode(hashResult.stdout).trim();

    if (commitHash) {
      return `HEAD (${commitHash})`;
    }
  } catch {
    // ignore
  }

  return "";
}

interface StatusLineInput {
  model?: { display_name?: string };
  workspace?: { current_dir?: string };
  context_window?: {
    used_percentage?: number;
    remaining_percentage?: number;
  };
}

function formatContextUsage(input: StatusLineInput): string {
  const contextWindow = input.context_window;

  if (!contextWindow || contextWindow.used_percentage === undefined) {
    return "_ (%)";
  }

  const usedPct = Math.round(contextWindow.used_percentage);

  let color: string;
  if (usedPct >= 90) {
    color = "\x1b[31m"; // red
  } else if (usedPct >= 70) {
    color = "\x1b[33m"; // yellow
  } else {
    color = "\x1b[32m"; // green
  }

  return `${color}${usedPct}%\x1b[0m`;
}

async function main() {
  const stdin = await readAll(Deno.stdin);
  const input: StatusLineInput = JSON.parse(new TextDecoder().decode(stdin));

  const modelDisplay = input.model?.display_name || "Unknown";
  const currentDir = input.workspace?.current_dir || ".";

  const dirName = currentDir.split("/").pop() || currentDir;

  const gitBranch = await getGitBranch();
  const contextUsage = formatContextUsage(input);

  const parts = [`󰚩  ${modelDisplay}`, `  ${dirName}`];
  if (gitBranch) {
    parts.push(`󰘬  ${gitBranch}`);
  }
  parts.push(`  ${contextUsage}`);

  console.log(parts.join(" | "));
}

if (import.meta.main) {
  main().catch((error) => {
    console.error("Error:", error);
    Deno.exit(1);
  });
}
