import {
  assert,
  assertEquals,
  assertNotEquals,
  assertStringIncludes,
} from "jsr:@std/assert";

import {
  classifyVerifiableGoal,
  countConsecutiveIdentical,
  decideLeakRecovery,
  detectGoalClear,
  detectLoopDirective,
  detectReactorGoal,
  detectSpin,
  detectToolcallLeakInText,
  extractErrorFingerprint,
  extractTargetTurns,
  GOAL_STATE_SCHEMA_VERSION,
  GOAL_STATE_TTL_MS,
  goalStatePathForInput,
  isExecDenied,
  isGoalStateExpired,
  isWaitingForBackground,
  legacyGoalStatePath,
  loadCounterexamples,
  loopDirectiveSnippet,
  normalizeGoalState,
  readTranscriptForGoal,
} from "./executable_stop-hook.ts";

Deno.test("detectGoalClear detects explicit goal clear directives", () => {
  assert(detectGoalClear("[goal clear]"));
  assert(detectGoalClear("goal reset"));
  assert(detectGoalClear("ゴール解除"));
  assert(detectGoalClear("ゴールクリア"));

  assertEquals(detectGoalClear("タスク完了"), false);
  assertEquals(detectGoalClear("done"), false);
  assertEquals(detectGoalClear("This is complete"), false);
  assertEquals(detectGoalClear("まだ作業中です"), false);
});

Deno.test("normalizeGoalState accepts legacy state without schema_version", () => {
  const state = normalizeGoalState({
    condition: "all tests pass",
    userHash: "abc123",
    setAt: 1000,
    iterations: 2,
    targetTurns: null,
    msgHashes: ["m1"],
    errorHashes: ["e1"],
  });

  assert(state);
  assertEquals(state.schema_version, GOAL_STATE_SCHEMA_VERSION);
  assertEquals(state.condition, "all tests pass");
  assertEquals(state.errorHashes, ["e1"]);
});

Deno.test("isGoalStateExpired treats states older than 24h as stale", () => {
  const now = 1_000_000_000;
  const fresh = normalizeGoalState({
    schema_version: GOAL_STATE_SCHEMA_VERSION,
    condition: "all tests pass",
    userHash: "abc123",
    setAt: now - GOAL_STATE_TTL_MS,
    iterations: 1,
    targetTurns: null,
    msgHashes: [],
    errorHashes: [],
  });
  const stale = normalizeGoalState({
    schema_version: GOAL_STATE_SCHEMA_VERSION,
    condition: "all tests pass",
    userHash: "abc123",
    setAt: now - GOAL_STATE_TTL_MS - 1,
    iterations: 1,
    targetTurns: null,
    msgHashes: [],
    errorHashes: [],
  });

  assert(fresh);
  assert(stale);
  assertEquals(isGoalStateExpired(fresh, now), false);
  assertEquals(isGoalStateExpired(stale, now), true);
});

Deno.test("goalStatePathForInput prefers session_id and falls back to transcript hash", () => {
  const transcriptPath = "/tmp/session/transcript.jsonl";

  assertEquals(goalStatePathForInput({}), null);
  assertEquals(goalStatePathForInput({ transcript_path: transcriptPath }), {
    current: legacyGoalStatePath(transcriptPath),
    legacy: null,
  });
  assertEquals(
    goalStatePathForInput({
      session_id: "session-123",
      transcript_path: transcriptPath,
    }),
    {
      current: "/tmp/claude-goal-s-session-123.json",
      legacy: legacyGoalStatePath(transcriptPath),
    },
  );
});

Deno.test("detectLoopDirective detects retry-until-success requests without matching implementation nouns", () => {
  assert(detectLoopDirective("テストが通るまで繰り返して"));
  assert(detectLoopDirective("repeat until green"));
  assert(detectLoopDirective("keep trying"));

  assertEquals(detectLoopDirective("keep retrying"), false);
  assertEquals(detectLoopDirective("繰り返しの処理を実装"), false);
});

Deno.test("loopDirectiveSnippet extracts nearby directive text and extractTargetTurns enforces bounds", () => {
  const text = "前提を確認してから、10回繰り返して、結果を報告してください。";
  assertStringIncludes(loopDirectiveSnippet(text), "10回繰り返して");

  assertEquals(extractTargetTurns(text), 10);
  assertEquals(extractTargetTurns("1回繰り返して"), null);
  assertEquals(extractTargetTurns("101回繰り返して"), null);
});

Deno.test("goal classification separates local verifiable goals and reactor goals", () => {
  assert(classifyVerifiableGoal("all tests pass"));
  assert(classifyVerifiableGoal("テストが通る"));

  assert(detectReactorGoal("CI passes"));
  assert(detectReactorGoal("デプロイ完了"));

  assert(classifyVerifiableGoal("production build"));
  assertEquals(detectReactorGoal("production build"), false);
});

Deno.test("isWaitingForBackground detects waiting states", () => {
  assert(isWaitingForBackground("waiting for the background result"));
  assert(isWaitingForBackground("完了を待機しています"));

  assertEquals(
    isWaitingForBackground("background color を調整しました"),
    false,
  );
  assertEquals(isWaitingForBackground("結果をまとめました"), false);
});

Deno.test("extractErrorFingerprint hashes failures and ignores successful exit status", () => {
  assertNotEquals(extractErrorFingerprint("FAIL tests/foo_test.ts\n"), "");
  assertEquals(extractErrorFingerprint("all checks passed"), "");
  assertEquals(extractErrorFingerprint("exit code: 0"), "");
  assertNotEquals(extractErrorFingerprint("exit code: 1"), "");
});

Deno.test("detectSpin and countConsecutiveIdentical inspect only consecutive tail entries", () => {
  assert(detectSpin(["a", "b", "c", "x", "x", "x"]));
  assertEquals(countConsecutiveIdentical(["a", "b", "x", "x", "x"]), 3);

  assertEquals(detectSpin(["x", "y", "x"]), false);
  assertEquals(countConsecutiveIdentical(["x", "y", "x"]), 1);
});

Deno.test("detectToolcallLeakInText detects only stranded trailing invoke XML", () => {
  // 漏洩 XML の見本をソースに直書きしない(将来このファイルを読む LLM セッションへの
  // 自己汚染防止)ため、タグは全て文字列連結で組み立てる
  const openInvoke = "<" + 'invoke name="Bash">';
  const openParam = "<" + 'parameter name="command">';
  const closeParam = "<" + "/parameter>";
  const closeInvoke = "<" + "/invoke>";
  const bashLeak = openInvoke + "\n" +
    openParam + "deno test" + closeParam + "\n" +
    closeInvoke;

  const leak = detectToolcallLeakInText(bashLeak);
  assert(leak);
  assertEquals(leak.tool, "Bash");
  assertEquals(leak.command, "deno test");

  assertEquals(
    detectToolcallLeakInText(`${bashLeak}\nこれは議論用の説明文です。`),
    null,
  );
  assertEquals(
    detectToolcallLeakInText(openInvoke + closeInvoke),
    null,
  );
});

Deno.test("decideLeakRecovery retries twice, gives up on the third identical leak, and flags chains", () => {
  const first = decideLeakRecovery("sig-a", null);
  assertEquals(first.action, "retry");
  assertEquals(first.state.count, 1);
  assertEquals(first.chained, false);

  const second = decideLeakRecovery("sig-a", first.state);
  assertEquals(second.action, "retry");
  assertEquals(second.state.count, 2);

  const third = decideLeakRecovery("sig-a", second.state);
  assertEquals(third.action, "giveup");
  assertEquals(third.state.count, 3);
  assertEquals(third.chained, true);

  const chainedDifferentSig = decideLeakRecovery("sig-b", second.state);
  assertEquals(chainedDifferentSig.action, "retry");
  assertEquals(chainedDifferentSig.state.count, 1);
  assertEquals(chainedDifferentSig.chained, true);
});

Deno.test("isExecDenied blocks dangerous commands and allows harmless listing", () => {
  assert(isExecDenied("sudo rm -rf /"));
  assertEquals(isExecDenied("ls -la"), false);
});

Deno.test("readTranscriptForGoal formats transcript fixtures", async () => {
  const path = await Deno.makeTempFile({ suffix: ".jsonl" });
  try {
    const entries = [
      {
        type: "user",
        message: { content: [{ type: "text", text: "修正してください" }] },
      },
      {
        type: "assistant",
        message: {
          content: [
            { type: "text", text: "確認します" },
            { type: "tool_use", name: "Bash", input: { command: "deno test" } },
          ],
        },
      },
      {
        type: "user",
        message: {
          content: [
            {
              type: "tool_result",
              content: "FAIL tests/foo_test.ts\nexit code: 1",
            },
          ],
        },
      },
      "{ malformed json",
    ];
    await Deno.writeTextFile(
      path,
      entries.map((entry) =>
        typeof entry === "string" ? entry : JSON.stringify(entry)
      ).join("\n"),
    );

    const transcript = await readTranscriptForGoal(path);
    assertStringIncludes(transcript, "[User]: 修正してください");
    assertStringIncludes(transcript, "[Assistant]: 確認します");
    assertStringIncludes(transcript, "[Tool: Bash] deno test");
    assertStringIncludes(transcript, "[Tool Output]: [Tool Result]: FAIL");
  } finally {
    await Deno.remove(path);
  }
});

Deno.test("loadCounterexamples injects only dated bullet entries and caps at 30", async () => {
  const path = await Deno.makeTempFile({ suffix: ".md" });
  try {
    const entries = Array.from(
      { length: 35 },
      (_, i) => `- [2026-01-${String(i + 1).padStart(2, "0")}] case ${i + 1}`,
    );
    await Deno.writeTextFile(
      path,
      [
        "# Operational notes",
        "This line must not be injected.",
        "- not a dated entry",
        ...entries,
      ].join("\n"),
    );

    const counterexamples = await loadCounterexamples(path);
    assertStringIncludes(counterexamples, "## Known Misjudgments");
    assertEquals(counterexamples.includes("Operational notes"), false);
    assertEquals(counterexamples.includes("- not a dated entry"), false);
    assertEquals(counterexamples.includes("case 5"), false);
    assertStringIncludes(counterexamples, "case 6");
    assertStringIncludes(counterexamples, "case 35");
    assertEquals(counterexamples.split("\n- [").length - 1, 30);
  } finally {
    await Deno.remove(path);
  }
});
