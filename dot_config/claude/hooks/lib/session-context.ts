/**
 * Shared utilities for Claude Code hooks.
 * Extracted from bin/cc-statusline.ts for reuse in PreCompact/SessionStart hooks.
 */

export interface ContentBlock {
  type: string;
  text?: string;
  name?: string;
  input?: Record<string, unknown>;
}

export interface TranscriptEntry {
  type: string;
  message?: {
    content: string | ContentBlock[];
    usage?: Record<string, number>;
  };
}

/** Prefixes that indicate system-generated messages, not real user input */
/** Prefixes that indicate system-generated or non-conversational messages */
const SYSTEM_MSG_PREFIXES = [
  "<local-command-",
  "<command-name>",
  "<local-command-stdout>",
  "<local-command-caveat>",
  "<system-reminder>",
  "[Request interrupted",
  "This session is being continued from a previous conversation",
  "Implement the following plan:",
  "Stop hook feedback:",
  "  Diagnostics\n",
];

export function extractTextFromContent(
  content: string | Array<{ type: string; text?: string }>,
): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((b) => b.type === "text" && b.text)
    .map((b) => b.text!)
    .join("\n");
}

/** Check if content represents a real user message (not tool_result or system-generated) */
export function isRealUserMessage(
  content: string | Array<{ type: string; text?: string }>,
): boolean {
  if (typeof content === "string") {
    const trimmed = content.trim();
    if (!trimmed) return false;
    return !SYSTEM_MSG_PREFIXES.some((p) => trimmed.startsWith(p));
  }
  if (!Array.isArray(content)) return false;
  // Skip entries that only contain tool_result blocks
  const hasText = content.some((b) => b.type === "text" && b.text?.trim());
  if (!hasText) return false;
  // Check if the text content is system-generated
  const text = content
    .filter((b) => b.type === "text" && b.text)
    .map((b) => b.text!)
    .join("\n")
    .trim();
  if (!text) return false;
  return !SYSTEM_MSG_PREFIXES.some((p) => text.startsWith(p));
}

export async function getGitBranch(cwd?: string): Promise<string> {
  try {
    const opts = cwd ? { cwd } : undefined;
    const { success } = await new Deno.Command("git", {
      args: ["rev-parse"],
      stdout: "null",
      stderr: "null",
      ...opts,
    }).output();
    if (!success) return "";

    const { stdout } = await new Deno.Command("git", {
      args: ["branch", "--show-current"],
      stdout: "piped",
      stderr: "null",
      ...opts,
    }).output();
    const branch = new TextDecoder().decode(stdout).trim();
    if (branch) return branch;

    const hashResult = await new Deno.Command("git", {
      args: ["rev-parse", "--short", "HEAD"],
      stdout: "piped",
      stderr: "null",
      ...opts,
    }).output();
    return new TextDecoder().decode(hashResult.stdout).trim() || "";
  } catch {
    return "";
  }
}

export async function getGitHeadSha(cwd?: string): Promise<string> {
  try {
    const opts = cwd ? { cwd } : undefined;
    const { stdout } = await new Deno.Command("git", {
      args: ["rev-parse", "HEAD"],
      stdout: "piped",
      stderr: "null",
      ...opts,
    }).output();
    return new TextDecoder().decode(stdout).trim();
  } catch {
    return "";
  }
}

export async function getGitDirtyCount(cwd?: string): Promise<number> {
  try {
    const opts = cwd ? { cwd } : undefined;
    const { stdout } = await new Deno.Command("git", {
      args: ["status", "--porcelain"],
      stdout: "piped",
      stderr: "null",
      ...opts,
    }).output();
    const text = new TextDecoder().decode(stdout).trim();
    if (!text) return 0;
    return text.split("\n").length;
  } catch {
    return 0;
  }
}

export async function findKeychainServices(): Promise<string[]> {
  try {
    const output = await new Deno.Command("security", {
      args: ["dump-keychain"],
      stdout: "piped",
      stderr: "null",
    }).output();
    const text = new TextDecoder().decode(output.stdout);
    const services: string[] = [];
    for (const m of text.matchAll(
      /"svce"<blob>="(Claude Code-credentials[^"]*)"/g,
    )) {
      if (!services.includes(m[1])) services.push(m[1]);
    }
    return services;
  } catch {
    return [];
  }
}

export async function getTokenFromKeychain(): Promise<string | null> {
  try {
    for (const svc of await findKeychainServices()) {
      try {
        const output = await new Deno.Command("security", {
          args: ["find-generic-password", "-s", svc, "-w"],
          stdout: "piped",
          stderr: "null",
        }).output();
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
    return null;
  } catch {
    return null;
  }
}

export async function getRecentUserMessages(
  transcriptPath: string,
  maxMessages = 5,
  maxLen = 200,
): Promise<string[]> {
  try {
    const stat = await Deno.stat(transcriptPath);
    const fileSize = stat.size ?? 0;
    const readSize = Math.min(fileSize, 262144);
    const file = await Deno.open(transcriptPath, { read: true });
    await file.seek(-readSize, Deno.SeekMode.End);
    const buf = new Uint8Array(readSize);
    await file.read(buf);
    file.close();
    const text = new TextDecoder().decode(buf);
    const messages: string[] = [];
    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      try {
        const obj: TranscriptEntry = JSON.parse(line);
        if (obj.type === "user" && obj.message?.content && isRealUserMessage(obj.message.content)) {
          messages.push(
            extractTextFromContent(obj.message.content).slice(0, maxLen),
          );
        }
      } catch {
        continue;
      }
    }
    return messages.slice(-maxMessages);
  } catch {
    return [];
  }
}

export function countTranscriptEntries(transcriptPath: string): Promise<number> {
  return (async () => {
    try {
      const content = await Deno.readTextFile(transcriptPath);
      return content.trimEnd().split("\n").filter((l) => l.trim()).length;
    } catch {
      return 0;
    }
  })();
}

/** Extract unique file paths from Read/Edit/Write/MultiEdit tool_use calls */
export async function getFilesTouched(
  transcriptPath: string,
  maxFiles = 30,
): Promise<string[]> {
  const paths = new Set<string>();
  try {
    const content = await Deno.readTextFile(transcriptPath);
    for (const line of content.split("\n")) {
      if (!line.trim()) continue;
      try {
        const obj: TranscriptEntry = JSON.parse(line);
        if (obj.type !== "assistant" || !obj.message?.content) continue;
        if (!Array.isArray(obj.message.content)) continue;
        for (const block of obj.message.content) {
          if (block.type !== "tool_use" || !block.input) continue;
          const name = block.name ?? "";
          if (/^(Read|Edit|Write|MultiEdit)$/.test(name)) {
            const fp = block.input.file_path as string | undefined;
            if (fp) paths.add(fp);
          }
        }
      } catch {
        continue;
      }
      if (paths.size >= maxFiles) break;
    }
  } catch {
    // ignore
  }
  return [...paths];
}

/** Extract the last substantive assistant text (non-empty, non-tool-only) */
export async function getLastAssistantText(
  transcriptPath: string,
  maxLen = 500,
): Promise<string> {
  try {
    const stat = await Deno.stat(transcriptPath);
    const fileSize = stat.size ?? 0;
    const readSize = Math.min(fileSize, 262144);
    const file = await Deno.open(transcriptPath, { read: true });
    await file.seek(-readSize, Deno.SeekMode.End);
    const buf = new Uint8Array(readSize);
    await file.read(buf);
    file.close();
    const lines = new TextDecoder().decode(buf).split("\n");
    // Scan backwards for last assistant with meaningful text
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (!line) continue;
      try {
        const obj: TranscriptEntry = JSON.parse(line);
        if (obj.type !== "assistant" || !obj.message?.content) continue;
        if (!Array.isArray(obj.message.content)) continue;
        const text = obj.message.content
          .filter((b: ContentBlock) => b.type === "text" && b.text?.trim())
          .map((b: ContentBlock) => b.text!)
          .join("\n")
          .trim();
        if (text.length > 10) return text.slice(0, maxLen);
      } catch {
        continue;
      }
    }
    return "";
  } catch {
    return "";
  }
}
