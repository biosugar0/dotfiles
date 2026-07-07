/**
 * pre-tool-use-guards.ts の black-box 回帰テスト。
 * ガード本体は export を持たないトップレベル実行型のため、実プロセスとして
 * spawn し stdin fixture → permissionDecision を検証する（実行契約そのものを固定）。
 *
 * 重点: 「改行を含む引用文字列トークン」の取り扱い。旧シェル実装はトークンを
 * 改行区切りストリームで受け渡していたため、複数行 commit メッセージが行単位に
 * 再分割され、`- add ...` 等の箇条書き行を -a フラグと誤検知する実バグがあった
 * （2026-07-07 他セッションで報告）。TS 版は配列受け渡しで免疫だが、回帰させない。
 */
import { assertEquals } from "jsr:@std/assert";

const GUARD = new URL("./executable_pre-tool-use-guards.ts", import.meta.url)
  .pathname;

async function decide(
  input: Record<string, unknown>,
  options: { env?: Record<string, string> } = {},
): Promise<{ decision: string; reason: string }> {
  const child = new Deno.Command("deno", {
    args: [
      "run",
      "--allow-read",
      "--allow-run",
      "--allow-env",
      "--allow-write",
      GUARD,
    ],
    stdin: "piped",
    stdout: "piped",
    stderr: "null",
    env: options.env,
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(JSON.stringify(input)));
  await writer.close();
  const out = await child.output();
  const text = new TextDecoder().decode(out.stdout).trim();
  if (!text) return { decision: "allow", reason: "" };
  const parsed = JSON.parse(text);
  return {
    decision: parsed.hookSpecificOutput?.permissionDecision ?? "allow",
    reason: parsed.hookSpecificOutput?.permissionDecisionReason ?? "",
  };
}

function bash(command: string): Record<string, unknown> {
  return { tool_name: "Bash", tool_input: { command } };
}

function edit(filePath: string, cwd?: string): Record<string, unknown> {
  return {
    tool_name: "Edit",
    tool_input: { file_path: filePath, old_string: "a", new_string: "b" },
    ...(cwd ? { cwd } : {}),
  };
}

function write(
  filePath: string,
  content: string,
  cwd?: string,
): Record<string, unknown> {
  return {
    tool_name: "Write",
    tool_input: { file_path: filePath, content },
    ...(cwd ? { cwd } : {}),
  };
}

async function run(
  command: string,
  args: string[],
  cwd?: string,
): Promise<string> {
  const output = await new Deno.Command(command, {
    args,
    cwd,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr).trim();
    throw new Error(`${command} ${args.join(" ")} failed: ${stderr}`);
  }
  return new TextDecoder().decode(output.stdout).trim();
}

async function makeGitRepo(branch = "topic/guard-test"): Promise<string> {
  const dir = await Deno.makeTempDir({ prefix: "pre-tool-use-guards-" });
  await run("git", ["init", "-b", branch], dir);
  await run("git", ["config", "user.email", "guard-test@example.com"], dir);
  await run("git", ["config", "user.name", "Guard Test"], dir);
  await Deno.writeTextFile(`${dir}/README.md`, "guard test\n");
  await run("git", ["add", "README.md"], dir);
  await run("git", ["commit", "-m", "initial"], dir);
  return dir;
}

async function removeDir(path: string): Promise<void> {
  await Deno.remove(path, { recursive: true }).catch(() => {});
}

Deno.test("複数行 -m コミット(箇条書きに小文字aを含む)は commit -a と誤検知しない", async () => {
  const cmd = 'git commit -m "feat: guard 強化\n\n' +
    "- add -A 検出を強化\n" +
    '- am 判定の改善"';
  const { decision, reason } = await decide(bash(cmd));
  assertEquals(decision, "allow", `false positive: ${reason}`);
});

Deno.test("複数 -m と単一引用符の複数行メッセージも通る", async () => {
  const two = await decide(
    bash('git commit -m "feat: x" -m "- added stuff\n- amend later"'),
  );
  assertEquals(two.decision, "allow", two.reason);
  const single = await decide(
    bash("git commit -m 'fix: y\n\n- added guard\n- amend flow'"),
  );
  assertEquals(single.decision, "allow", single.reason);
});

Deno.test("本物の commit -a / -am は引き続き deny", async () => {
  assertEquals((await decide(bash('git commit -am "x"'))).decision, "deny");
  assertEquals(
    (await decide(bash('git commit -a -m "x"'))).decision,
    "deny",
  );
});

Deno.test("global option 付き add -A は deny、個別 add は allow", async () => {
  assertEquals(
    (await decide(bash("git -C /some/repo add -A"))).decision,
    "deny",
  );
  assertEquals(
    (await decide(bash("git add src/file.ts"))).decision,
    "allow",
  );
});

Deno.test("git merge は deny、空 command は allow", async () => {
  assertEquals((await decide(bash("git merge feature"))).decision, "deny");
  assertEquals(
    (await decide({ tool_name: "Bash", tool_input: {} })).decision,
    "allow",
  );
});

Deno.test("verification-write: Bash/Edit の receipt 直接書き込みは deny、無関係ファイルは allow", async () => {
  const quotedMultiline =
    'printf "%s\n" "- PASS\n- forged" > ai/state/verification.json';
  assertEquals((await decide(bash(quotedMultiline))).decision, "deny");
  assertEquals(
    (await decide(edit("nested/ai/state/verification.json"))).decision,
    "deny",
  );
  assertEquals(
    (await decide(bash("cat ai/state/verification.json > build.log")))
      .decision,
    "allow",
  );
  assertEquals((await decide(edit("src/verification.ts"))).decision, "allow");
});

Deno.test("test-mutation: テスト削除と既存テスト空化は deny、rename と新規作成は allow", async () => {
  assertEquals(
    (await decide(bash("rm tests/example.test.ts"))).decision,
    "deny",
  );
  assertEquals(
    (await decide(bash("git mv tests/example.test.ts tests/renamed.test.ts")))
      .decision,
    "allow",
  );

  const dir = await Deno.makeTempDir({ prefix: "guard-test-mutation-" });
  try {
    await Deno.mkdir(`${dir}/tests`);
    await Deno.writeTextFile(
      `${dir}/tests/example.test.ts`,
      "Deno.test('keeps coverage', () => {\n" + "  assert(true);\n".repeat(30) +
        "});\n",
    );
    assertEquals(
      (await decide(write("tests/example.test.ts", "", dir))).decision,
      "deny",
    );
    assertEquals(
      (await decide(write("tests/new.test.ts", "", dir))).decision,
      "allow",
    );
  } finally {
    await removeDir(dir);
  }
});

Deno.test("block-config-edit: tsconfig.json 編集は deny、通常 ts ファイル編集は allow", async () => {
  assertEquals((await decide(edit("tsconfig.json"))).decision, "deny");
  assertEquals((await decide(edit("src/app.ts"))).decision, "allow");
});

Deno.test("anti-loop: loop.json が上限到達なら enforce で deny、ack と state 無しは allow", async () => {
  const repo = await makeGitRepo();
  try {
    assertEquals(
      (await decide(edit("src/app.ts", repo), {
        env: { AI_ANTILOOP_ENFORCE: "1" },
      })).decision,
      "allow",
    );

    await Deno.mkdir(`${repo}/ai/state`, { recursive: true });
    await Deno.writeTextFile(
      `${repo}/ai/state/loop.json`,
      JSON.stringify({
        consecutive_same_failure: 3,
        max_attempts: 3,
        strategy_reset_ack: false,
        last_failure_signature: "tsc:2322",
      }),
    );
    assertEquals(
      (await decide(edit("src/app.ts", repo), {
        env: { AI_ANTILOOP_ENFORCE: "1" },
      })).decision,
      "deny",
    );

    await Deno.writeTextFile(
      `${repo}/ai/state/loop.json`,
      JSON.stringify({
        consecutive_same_failure: 3,
        max_attempts: 3,
        strategy_reset_ack: true,
        last_failure_signature: "tsc:2322",
      }),
    );
    assertEquals(
      (await decide(edit("src/app.ts", repo), {
        env: { AI_ANTILOOP_ENFORCE: "1" },
      })).decision,
      "allow",
    );
  } finally {
    await removeDir(repo);
  }
});

Deno.test("pr-gate: review marker 無し gh pr create は deny、marker 有りは allow", async () => {
  const repo = await makeGitRepo("feature/guard-pr");
  let marker = "";
  try {
    await run(
      "git",
      [
        "remote",
        "add",
        "origin",
        "https://github.com/biosugar0/pr-marker-target.git",
      ],
      repo,
    );
    const hash = await run("git", ["rev-parse", "--short", "HEAD"], repo);
    marker =
      `/tmp/.codex-review-done--pr-marker-target--feature_guard-pr--${hash}`;
    const command =
      'gh pr create --title "- add guard\n- keep quoted parser" --body "ok"';

    assertEquals(
      (await decide({ ...bash(command), cwd: repo })).decision,
      "deny",
    );

    await Deno.writeTextFile(marker, "reviewed\n");
    assertEquals(
      (await decide({ ...bash(command), cwd: repo })).decision,
      "allow",
    );
  } finally {
    if (marker) await Deno.remove(marker).catch(() => {});
    await removeDir(repo);
  }
});
