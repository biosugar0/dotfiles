#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env

import { readAll } from "jsr:@std/io@0.224.0/read-all";
import { existsSync } from "jsr:@std/fs@1.0.8/exists";

interface ToolOutput {
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

    const fileInfo = Deno.statSync(filePath);
    if (fileInfo.isSymlink) {
      return false;
    }

    const content = await Deno.readFile(filePath);

    if (content.length === 0) {
      return false;
    }

    const lastByte = content[content.length - 1];
    if (lastByte !== 0x0a) {
      const newContent = new Uint8Array(content.length + 1);
      newContent.set(content);
      newContent[content.length] = 0x0a;

      await Deno.writeFile(filePath, newContent);

      await Deno.stderr.write(
        new TextEncoder().encode(`Added EOL to ${filePath}\n`)
      );
      return true;
    }

    return false;
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
      await ensureEOL(filePath);
    }
  } catch {
    Deno.exit(0);
  }
}

main();
