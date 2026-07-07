#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env

import { readAll } from "jsr:@std/io@0.224.0/read-all";
import { existsSync } from "jsr:@std/fs@1.0.8/exists";
import { isAbsolute, join } from "jsr:@std/path@1.0.8";

interface ToolOutput {
  cwd?: string;
  tool_name?: string;
  tool_input?: {
    file_path?: string;
    [key: string]: unknown;
  };
  tool_output?: {
    [key: string]: unknown;
  };
}

async function ensureEOL(filePath: string): Promise<boolean> {
  try {
    if (!existsSync(filePath)) {
      return false;
    }

    const fileInfo = await Deno.lstat(filePath);
    if (fileInfo.isSymlink || !fileInfo.isFile || fileInfo.size === 0) {
      return false;
    }

    const file = await Deno.open(filePath, { read: true });
    const lastByte = new Uint8Array(1);
    try {
      await file.seek(-1, Deno.SeekMode.End);
      const bytesRead = await file.read(lastByte);
      if (bytesRead !== 1 || lastByte[0] === 0x0a) {
        return false;
      }
    } finally {
      file.close();
    }

    const appendFile = await Deno.open(filePath, { append: true, write: true });
    try {
      await appendFile.write(new Uint8Array([0x0a]));
    } finally {
      appendFile.close();
    }

    await Deno.stderr.write(
      new TextEncoder().encode(`Added EOL to ${filePath}\n`)
    );
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.PermissionDenied) {
      return false;
    }

    await Deno.stderr.write(
      new TextEncoder().encode(
        `Warning: Could not check EOL for ${filePath}: ${error}\n`
      )
    );
    return false;
  }
}

async function main(): Promise<void> {
  try {
    const decoder = new TextDecoder();
    const input = decoder.decode(await readAll(Deno.stdin));
    const outputData: ToolOutput = JSON.parse(input);

    const toolName = outputData.tool_name ?? "";
    const toolInput = outputData.tool_input ?? {};

    if (!["Edit", "MultiEdit", "Write"].includes(toolName)) {
      Deno.exit(0);
    }

    const filePath = toolInput.file_path;
    if (typeof filePath === "string" && filePath.length > 0) {
      const cwd = typeof outputData.cwd === "string" && outputData.cwd.length > 0
        ? outputData.cwd
        : Deno.cwd();
      const absolutePath = isAbsolute(filePath) ? filePath : join(cwd, filePath);
      await ensureEOL(absolutePath);
    }
  } catch {
    Deno.exit(0);
  }
}

main();
