#!/usr/bin/env -S deno run --allow-read --allow-run --allow-env --allow-write

import { readAll } from "jsr:@std/io@0.224/read-all";
import { harnessLog } from "./lib/harness-log.ts";

type ToolName = "Edit" | "Write" | "MultiEdit" | "Bash" | string;

interface HookInput {
  tool_name?: ToolName;
  tool_input?: {
    file_path?: string;
    command?: string;
    full_command?: string;
    content?: string;
  };
  cwd?: string;
  session_id?: string;
}

interface DenyResult {
  permissionDecisionReason: string;
}

type Guard = (input: HookInput) => Promise<DenyResult | null>;

const encoder = new TextEncoder();

function deny(permissionDecisionReason: string): DenyResult {
  return { permissionDecisionReason };
}

function outputDeny(result: DenyResult): void {
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: result.permissionDecisionReason,
    },
  }));
}

function stderr(line: string): void {
  Deno.stderr.writeSync(encoder.encode(line + "\n"));
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function basename(path: string): string {
  const trimmed = path.replace(/\/+$/, "");
  const i = trimmed.lastIndexOf("/");
  return i >= 0 ? trimmed.slice(i + 1) : trimmed;
}

function dirname(path: string): string {
  const trimmed = path.replace(/\/+$/, "") || "/";
  const i = trimmed.lastIndexOf("/");
  if (i < 0) return ".";
  if (i === 0) return "/";
  return trimmed.slice(0, i);
}

async function isDirectory(path: string): Promise<boolean> {
  try {
    return (await Deno.stat(path)).isDirectory;
  } catch {
    return false;
  }
}

async function isFile(path: string): Promise<boolean> {
  try {
    return (await Deno.stat(path)).isFile;
  } catch {
    return false;
  }
}

async function readJsonFile(
  path: string,
): Promise<Record<string, unknown> | null> {
  try {
    return JSON.parse(await Deno.readTextFile(path));
  } catch {
    return null;
  }
}

async function run(
  command: string,
  args: string[],
  cwd?: string,
): Promise<{ ok: boolean; stdout: string }> {
  try {
    const output = await new Deno.Command(command, {
      args,
      cwd,
      stdout: "piped",
      stderr: "null",
    }).output();
    return {
      ok: output.success,
      stdout: new TextDecoder().decode(output.stdout).trim(),
    };
  } catch {
    return { ok: false, stdout: "" };
  }
}

async function git(
  args: string[],
  cwd?: string,
): Promise<{ ok: boolean; stdout: string }> {
  return await run("git", args, cwd);
}

function parseUintLike(value: unknown, fallback?: number): number | null {
  if (typeof value === "number" && Number.isInteger(value) && value >= 0) {
    return value;
  }
  if (typeof value === "string" && /^\d+$/.test(value)) return Number(value);
  return fallback ?? null;
}

async function absoluteFilePath(
  input: HookInput,
  filePath: string,
): Promise<string> {
  if (filePath.startsWith("/")) return filePath;

  let baseDir = input.cwd || Deno.env.get("CLAUDE_PROJECT_DIR") || Deno.cwd();
  try {
    baseDir = await Deno.realPath(baseDir);
  } catch {
    baseDir = Deno.cwd();
  }
  return `${baseDir}/${filePath}`;
}

async function existingParentDir(filePath: string): Promise<string> {
  let dir = dirname(filePath);
  while (!(await isDirectory(dir)) && dir !== "/") {
    dir = dirname(dir);
  }
  return dir;
}

async function guardBlockMain(input: HookInput): Promise<DenyResult | null> {
  const filePath = input.tool_input?.file_path;
  if (!filePath) return null;

  const abs = await absoluteFilePath(input, filePath);
  const fileDir = await existingParentDir(abs);
  const branch = await git(["-C", fileDir, "branch", "--show-current"]);
  if (!branch.ok) return null;
  if (branch.stdout !== "main" && branch.stdout !== "master") return null;

  const remote = await git(["-C", fileDir, "remote", "get-url", "origin"]);
  const remoteLc = remote.stdout.toLowerCase();
  if (/(^|[:/])biosugar0\/dotfiles(\.git)?$/.test(remoteLc)) return null;

  await harnessLog("block-main", "deny", abs, input.session_id ?? "");
  return deny(
    "mainブランチでの編集はブロックされた。git wt <branch> でworktreeを作成して作業してください。",
  );
}

function isProtectedConfig(base: string): boolean {
  return [
    /^\.eslintrc(?:\..*)?$/,
    /^eslint\.config\..*$/,
    /^biome\.jsonc?$/,
    /^\.prettierrc(?:\..*)?$/,
    /^prettier\.config\..*$/,
    /^tsconfig(?:\..*)?\.json$/,
    /^jest\.config\..*$/,
    /^vitest\.config\..*$/,
    /^\.golangci\.ya?ml$/,
    /^\.swiftlint\.yml$/,
    /^\.pre-commit-config\.yaml$/,
    /^lefthook(?:-local)?\.yml$/,
    /^\.?mypy\.ini$/,
    /^\.ruff\.toml$/,
    /^ruff\.toml$/,
  ].some((pattern) => pattern.test(base));
}

async function guardBlockConfigEdit(
  input: HookInput,
): Promise<DenyResult | null> {
  const filePath = input.tool_input?.file_path;
  if (!filePath) return null;

  const base = basename(filePath);
  if (!isProtectedConfig(base)) return null;

  await harnessLog("block-config-edit", "deny", base, input.session_id ?? "");
  return deny(
    "リンター/フォーマッター設定ファイルの編集はブロックされた。設定を変更するのではなく、コードを修正してください。",
  );
}

async function guardAntiLoop(input: HookInput): Promise<DenyResult | null> {
  const cwd = input.cwd;
  if (!cwd) return null;

  const repo = await git(["-C", cwd, "rev-parse", "--show-toplevel"]);
  const root = repo.ok && repo.stdout ? repo.stdout : cwd;
  const loop = await readJsonFile(`${root}/ai/state/loop.json`);
  if (!loop) return null;

  const cnt = parseUintLike(loop.consecutive_same_failure);
  if (cnt === null) return null;
  const max = parseUintLike(loop.max_attempts, 3) ?? 3;
  const ack = loop.strategy_reset_ack === true ||
    loop.strategy_reset_ack === "true";
  const sig = String(loop.last_failure_signature ?? "");

  if (ack || cnt < max) return null;

  const reason =
    `同一失敗が ${cnt} 回連続(sig=${sig})。パッチを当て直すループの可能性。広い編集を続ける前に、決定的な repro/test/harness を作るか、仮説を ranked で立て直す(weakest_assumption の falsifiable check)。解除: ai-run-check --reset。`;

  if ((Deno.env.get("AI_ANTILOOP_ENFORCE") ?? "0") === "1") {
    await harnessLog(
      "anti-loop",
      "deny",
      `sig=${sig} cnt=${cnt}`,
      input.session_id ?? "",
    );
    return deny(reason);
  }

  await harnessLog(
    "anti-loop",
    "warn",
    `sig=${sig} cnt=${cnt}`,
    input.session_id ?? "",
  );
  stderr(`⚠ anti-loop(warn): ${reason}`);
  return null;
}

async function guardVerificationWrite(
  input: HookInput,
): Promise<DenyResult | null> {
  const tool = input.tool_name ?? "";
  const reason =
    "ai/state/verification.json への直接書き込みはブロックされた。検証 receipt は `ai-run-check --write-receipt -- <検証コマンド>` が実 exit code から機械生成する(verifier-gaming 防止)。手書きでの PASS 記録は不可。";

  if (tool === "Edit" || tool === "Write" || tool === "MultiEdit") {
    const filePath = input.tool_input?.file_path ?? "";
    if (
      filePath === "ai/state/verification.json" ||
      filePath.endsWith("/ai/state/verification.json")
    ) {
      await harnessLog(
        "guard-verification-write",
        "deny",
        tool,
        input.session_id ?? "",
      );
      return deny(reason);
    }
  }

  if (tool === "Bash") {
    const command = input.tool_input?.command ?? "";
    if (
      /(>>?\|?\s*|tee\s+(-a\s+)?)([^\s|;&<>]*\/)?ai\/state\/verification\.json/
        .test(command)
    ) {
      await harnessLog(
        "guard-verification-write",
        "deny",
        tool,
        input.session_id ?? "",
      );
      return deny(reason);
    }
  }

  return null;
}

function unquote(token: string): string {
  if (
    (token.startsWith('"') && token.endsWith('"')) ||
    (token.startsWith("'") && token.endsWith("'"))
  ) {
    return token.slice(1, -1);
  }
  return token;
}

function isTestFile(path: string): boolean {
  return path.includes("/tests/") ||
    path.startsWith("tests/") ||
    path.includes("/__tests__/") ||
    path.startsWith("__tests__/") ||
    /\.(test|spec)\.(js|jsx|ts|tsx|mjs|cjs)$/.test(path) ||
    /_test\.go$/.test(path) ||
    /_test\.py$/.test(path) ||
    /_spec\.rb$/.test(path) ||
    /Test\.java$/.test(path) ||
    /Tests\.cs$/.test(path) ||
    /^test_.*\.py$/.test(basename(path));
}

function isTestDir(path: string): boolean {
  const p = path.replace(/\/+$/, "");
  return p === "tests" || p === "__tests__" || p.endsWith("/tests") ||
    p.endsWith("/__tests__");
}

async function guardTestMutation(input: HookInput): Promise<DenyResult | null> {
  const tool = input.tool_name ?? "";
  const rDelete =
    "テストファイル/ディレクトリの削除はブロックされた。テストは回帰の証拠であり、消すと「通った」状態を捏造できる。テストが本当に不要なら、その判断は人間が別途明示的に行うこと。";
  const rGut =
    "既存テストファイルを空(ほぼ0バイト)に上書き/空化する操作はブロックされた。テストの骨抜きは検証の無効化に等しい。";

  const denyWithLog = async (reason: string): Promise<DenyResult> => {
    await harnessLog(
      "guard-test-mutation",
      "deny",
      tool,
      input.session_id ?? "",
    );
    return deny(reason);
  };

  if (tool === "Bash") {
    const command = input.tool_input?.command ?? "";
    if (!command) return null;

    const segments = command.split(/\|\||&&|;|\|/);
    for (const rawSegment of segments) {
      const segment = rawSegment.trim();
      if (!segment) continue;
      const tokens = segment.split(/\s+/);
      const verb = tokens[0] ?? "";

      let prevRedir = false;
      for (const token of tokens) {
        if (prevRedir) {
          prevRedir = false;
          if (isTestFile(unquote(token))) return await denyWithLog(rGut);
        }
        if (token === ">") {
          prevRedir = true;
        } else if (token.startsWith(">>")) {
          // Append is not gutting.
        } else if (
          token.startsWith(">") && token.length > 1 &&
          isTestFile(unquote(token.slice(1)))
        ) {
          return await denyWithLog(rGut);
        }
      }

      const operands = tokens.slice(1);
      if (verb === "rm") {
        for (const token of operands) {
          if (token.startsWith("-")) continue;
          const t = unquote(token);
          if (isTestFile(t) || isTestDir(t)) return await denyWithLog(rDelete);
        }
      } else if (verb === "git") {
        let foundRm = false;
        for (const token of tokens) {
          if (foundRm) {
            if (token.startsWith("-")) continue;
            const t = unquote(token);
            if (isTestFile(t) || isTestDir(t)) {
              return await denyWithLog(rDelete);
            }
          } else if (token === "rm") {
            foundRm = true;
          }
        }
      } else if (verb === "truncate") {
        for (const token of operands) {
          if (token.startsWith("-")) continue;
          if (isTestFile(unquote(token))) return await denyWithLog(rGut);
        }
      } else if (verb === "cp") {
        if (tokens.includes("/dev/null")) {
          for (const token of tokens) {
            if (isTestFile(unquote(token))) return await denyWithLog(rGut);
          }
        }
      } else if (verb === "find") {
        if (/(^|\s)(-delete|-exec\s+rm)\b/.test(segment)) {
          for (const token of tokens) {
            if (token === "find" || token.startsWith("-")) continue;
            const t = unquote(token);
            if (isTestFile(t) || isTestDir(t)) {
              return await denyWithLog(rDelete);
            }
          }
        }
      }
    }
  } else if (tool === "Write") {
    const filePath = input.tool_input?.file_path ?? "";
    if (!filePath || !isTestFile(filePath)) return null;

    const abs = filePath.startsWith("/")
      ? filePath
      : `${input.cwd || "."}/${filePath}`;
    if (!(await isFile(abs))) return null;

    let currentSize = 0;
    try {
      currentSize = (await Deno.stat(abs)).size;
    } catch {
      return null;
    }
    const content = input.tool_input?.content ?? "";
    if (currentSize > 200 && content.length < 50) {
      return await denyWithLog(rGut);
    }
  }

  return null;
}

async function guardBlockMerge(input: HookInput): Promise<DenyResult | null> {
  const command = input.tool_input?.command ?? "";
  const mergePattern =
    /(^|[;&|(] *)(git( +(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path)([= ]+[^ ]+)?| +(--no-pager|--paginate|--bare|-p|-P))* +merge( |$)|gh( +(-R|--repo)[= ]+[^ ]+)? +pr +merge( |$))/;

  if (!mergePattern.test(command)) return null;

  await harnessLog(
    "block-merge",
    "deny",
    command.slice(0, 120),
    input.session_id ?? "",
  );
  return deny("git merge / gh pr merge はブロックされている。");
}

function tokenizeCommand(command: string): string[] {
  const tokens: string[] = [];
  let quote = "";
  let token = "";

  for (let i = 0; i < command.length; i++) {
    const ch = command[i];
    if (quote) {
      if (ch === quote) {
        quote = "";
      } else if (ch === "\\" && quote === '"' && i + 1 < command.length) {
        i++;
        token += command[i];
      } else {
        token += ch;
      }
      continue;
    }

    if (ch === "'" || ch === '"') {
      quote = ch;
    } else if (ch === "\\") {
      if (i + 1 < command.length) {
        i++;
        token += command[i];
      }
    } else if (ch === " " || ch === "\t" || ch === "\n") {
      if (token) {
        tokens.push(token);
        token = "";
      }
    } else if (
      ch === ";" || ch === "&" || ch === "|" || ch === "(" || ch === ")"
    ) {
      if (token) {
        tokens.push(token);
        token = "";
      }
      tokens.push(ch);
    } else {
      token += ch;
    }
  }
  if (token) tokens.push(token);
  return tokens;
}

function isCommandSeparator(token: string): boolean {
  return token === ";" || token === "&" || token === "|" || token === "(" ||
    token === ")";
}

function normalizeGitArgv(argv: string[]): string[] {
  const result = [...argv];
  while (result.length > 0) {
    const arg = result[0];
    if (
      arg === "-C" ||
      arg === "-c" ||
      arg === "--git-dir" ||
      arg === "--work-tree" ||
      arg === "--namespace" ||
      arg === "--exec-path" ||
      arg === "--super-prefix" ||
      arg === "--config-env"
    ) {
      result.shift();
      if (result.length > 0) result.shift();
    } else if (
      /^-C.+/.test(arg) ||
      /^-c=/.test(arg) ||
      /^--(git-dir|work-tree|namespace|exec-path|super-prefix|config-env)=/
        .test(arg)
    ) {
      result.shift();
    } else if (
      arg === "--no-pager" ||
      arg === "--paginate" ||
      arg === "--bare" ||
      arg === "--literal-pathspecs" ||
      arg === "--glob-pathspecs" ||
      arg === "--noglob-pathspecs" ||
      arg === "--icase-pathspecs" ||
      arg === "-p" ||
      arg === "-P"
    ) {
      result.shift();
    } else if (arg === "--") {
      result.shift();
      break;
    } else {
      break;
    }
  }
  return result;
}

async function guardBlockForbiddenDirs(
  input: HookInput,
): Promise<DenyResult | null> {
  const command = input.tool_input?.command ?? input.tool_input?.full_command ??
    "";
  if (!command) return null;

  const tokens = tokenizeCommand(command);
  let hasGitAddOrCommit = false;
  let hasGitAddAll = false;
  let hasGitCommitAll = false;

  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "git") continue;

    const argv: string[] = [];
    for (let j = i + 1; j < tokens.length; j++) {
      if (isCommandSeparator(tokens[j])) break;
      argv.push(tokens[j]);
    }

    const normalized = normalizeGitArgv(argv);
    const subcmd = normalized[0] ?? "";
    if (subcmd === "add") {
      hasGitAddOrCommit = true;
      for (const token of normalized.slice(1)) {
        if (
          token === "." || token === ":/" || token === "-A" || token === "--all"
        ) {
          hasGitAddAll = true;
        }
      }
    } else if (subcmd === "commit") {
      hasGitAddOrCommit = true;
      const rest = normalized.slice(1);
      for (let k = 0; k < rest.length; k++) {
        const token = rest[k];
        if (token === "--") break;
        if (token.startsWith("--")) continue;
        // -m/-F 等の値取り短オプションの「値」はフラグではない。値がダッシュ始まり
        // (例: -m "- added ..." の箇条書きメッセージ)でも -a と誤検知しないよう
        // 次トークンをスキップする(2026-07-07 に実発生した false positive の再発防止)
        if (/^-[mFcCt]$/.test(token)) {
          k++;
          continue;
        }
        // フラグとして見るのは空白等を含まない短フラグ束のみ(-a / -am / -av 等)
        if (/^-[a-zA-Z]+$/.test(token) && token.includes("a")) {
          hasGitCommitAll = true;
        }
      }
    }
  }

  if (!hasGitAddOrCommit) return null;

  if (/(^|[\s(])(\.?\/|:\/)?ai\//.test(command)) {
    await harnessLog(
      "block-forbidden-dirs",
      "deny",
      "ai-dir",
      input.session_id ?? "",
    );
    return deny(
      "forbidden: 禁止ディレクトリ(ai/)はステージ・コミットできない。",
    );
  }

  if (hasGitAddAll) {
    await harnessLog(
      "block-forbidden-dirs",
      "deny",
      "add-all",
      input.session_id ?? "",
    );
    return deny(
      'forbidden: "git add ." / "git add -A" は禁止。ファイルを個別に指定すること。',
    );
  }

  if (hasGitCommitAll) {
    await harnessLog(
      "block-forbidden-dirs",
      "deny",
      "commit-a",
      input.session_id ?? "",
    );
    return deny(
      'forbidden: "git commit -a" は禁止。git addでファイルを個別にステージすること。',
    );
  }

  return null;
}

function repoMarkerName(repo: string): string {
  const withoutGit = repo.replace(/\.git$/, "");
  const parts = withoutGit.split("/");
  return parts[parts.length - 1] ?? withoutGit;
}

function normalizeGhArgv(argv: string[]): string[] {
  const normalized: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "-R" || arg === "--repo") {
      i++;
    } else if (arg.startsWith("--repo=") || arg.startsWith("-R=")) {
      // skip
    } else {
      normalized.push(arg);
    }
  }
  return normalized;
}

function extractGhRepo(argv: string[]): string {
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "-R" || arg === "--repo") {
      if (i + 1 < argv.length) return repoMarkerName(argv[i + 1]);
    } else if (arg.startsWith("--repo=")) {
      return repoMarkerName(arg.slice("--repo=".length));
    } else if (arg.startsWith("-R=")) {
      return repoMarkerName(arg.slice("-R=".length));
    }
  }
  return "";
}

function extractGhHead(argv: string[]): string {
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--head") {
      if (i + 1 < argv.length) return argv[i + 1].split(":").pop() ?? "";
    } else if (arg.startsWith("--head=")) {
      return arg.slice("--head=".length).split(":").pop() ?? "";
    }
  }
  return "";
}

function markerBranch(branch: string): string {
  return branch.replaceAll("/", "_");
}

async function reviewMarkerExists(
  repo: string,
  branch: string,
  hash: string,
): Promise<boolean> {
  const b = markerBranch(branch);
  return await isFile(`/tmp/.codex-review-done--${repo}--${b}--${hash}`) ||
    await isFile(`/tmp/.code-review-done--${repo}--${b}--${hash}`);
}

async function reviewMarkerGlob(
  repo: string,
  branch: string,
): Promise<boolean> {
  const prefixes = [
    `.codex-review-done--${repo}--${markerBranch(branch)}--`,
    `.code-review-done--${repo}--${markerBranch(branch)}--`,
  ];
  try {
    for await (const entry of Deno.readDir("/tmp")) {
      if (!entry.isFile) continue;
      if (prefixes.some((prefix) => entry.name.startsWith(prefix))) return true;
    }
  } catch {
    return false;
  }
  return false;
}

async function reviewMarkerMatch(
  repo: string,
  branch: string,
  hash: string,
): Promise<boolean> {
  if (!repo || !branch) return false;
  if (hash) return await reviewMarkerExists(repo, branch, hash);
  return await reviewMarkerGlob(repo, branch);
}

async function repoInfo(
  cwd: string,
): Promise<{ repo: string; branch: string; hash: string }> {
  const [remote, branch, hash] = await Promise.all([
    git(["-C", cwd, "remote", "get-url", "origin"]),
    git(["-C", cwd, "branch", "--show-current"]),
    git(["-C", cwd, "rev-parse", "--short", "HEAD"]),
  ]);
  return {
    repo: repoMarkerName(remote.stdout),
    branch: branch.stdout,
    hash: hash.stdout,
  };
}

async function guardBlockPrWithoutReview(
  input: HookInput,
): Promise<DenyResult | null> {
  const command = input.tool_input?.command ?? input.tool_input?.full_command ??
    "";
  const tokens = tokenizeCommand(command);

  let isGhPrCreate = false;
  let cliRepo = "";
  let cliHead = "";

  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "gh") continue;

    const argv: string[] = [];
    for (let j = i + 1; j < tokens.length; j++) {
      if (isCommandSeparator(tokens[j])) break;
      argv.push(tokens[j]);
    }

    const normalized = normalizeGhArgv(argv);
    if ((normalized[0] ?? "") === "pr" && (normalized[1] ?? "") === "create") {
      isGhPrCreate = true;
      cliRepo = extractGhRepo(argv);
      cliHead = extractGhHead(argv);
      break;
    }
  }

  if (!isGhPrCreate) return null;

  const hookCwd = input.cwd || Deno.cwd();
  const sid = input.session_id ?? "";
  let found = false;

  const absolutePaths = [...command.matchAll(/\/[^"'\s;&|)]+/g)]
    .map((match) => match[0])
    .sort();
  for (const path of [...new Set(absolutePaths)]) {
    if (!(await isDirectory(path))) continue;
    const inRepo = await git(["-C", path, "rev-parse", "--git-dir"]);
    if (!inRepo.ok) continue;
    const info = await repoInfo(path);
    if (await reviewMarkerMatch(info.repo, info.branch, info.hash)) {
      found = true;
      break;
    }
  }

  if (!found) {
    const info = await repoInfo(hookCwd);
    const repo = cliRepo || info.repo;
    if (await reviewMarkerMatch(repo, info.branch, info.hash)) {
      found = true;
    }
  }

  if (!found && cliRepo && cliHead) {
    if (await reviewMarkerGlob(cliRepo, cliHead)) {
      found = true;
    }
  }

  if (found) {
    const gateFile = `${hookCwd}/ai/state/workflow-gate.json`;
    if (await isFile(gateFile)) {
      const gate = await readJsonFile(gateFile);
      if (gate) {
        const gateSha = asString(gate.head_sha);
        const evaluator = (gate.evaluator && typeof gate.evaluator === "object")
          ? gate.evaluator as Record<string, unknown>
          : {};
        const gateStatus = asString(evaluator.status);
        const currentSha =
          (await git(["-C", hookCwd, "rev-parse", "--short", "HEAD"])).stdout;

        if (gateSha !== currentSha) {
          await harnessLog(
            "block-pr-without-review",
            "warn:gate_head_changed",
            `gate=${gateSha} current=${currentSha}`,
            sid,
          );
          stderr(
            `evaluator: HEAD が変わっています（gate: ${gateSha}, current: ${currentSha}）`,
          );
        } else if (gateStatus === "FAIL") {
          const gateSummary = asString(evaluator.summary);
          await harnessLog(
            "block-pr-without-review",
            "warn:gate_fail",
            gateSummary,
            sid,
          );
          stderr(`evaluator: FAIL — ${gateSummary}（修正推奨）`);
        }
      }
    } else {
      const diff = await git([
        "-C",
        hookCwd,
        "diff",
        "--name-only",
        "origin/main...HEAD",
      ]);
      const changedCount = diff.stdout
        ? diff.stdout.split("\n").filter(Boolean).length
        : 0;
      if (changedCount >= 5) {
        await harnessLog(
          "block-pr-without-review",
          "warn:gate_missing",
          `changed=${changedCount}`,
          sid,
        );
        stderr(
          `evaluator: 未実施（変更ファイル ${changedCount} 件）。/evaluator で品質評価を推奨。`,
        );
      }
    }
    return null;
  }

  const reason = cliRepo && !cliHead
    ? "PR creation requires review: Codex reviewが未実施、または --head フラグが不足。--head {branch} を付けて再試行すること。"
    : "PR creation requires review: Codex reviewが未実施。先にcodex-tmux skillでレビューを受けてからPRを作成すること。codex が使えない場合は /code-review xhigh でレビューし、.code-review-done--{repo}--{branch}--{hash} マーカーを生成すること（詳細は codex-tmux skill のフォールバック節）。";
  await harnessLog("block-pr-without-review", "deny", "no-review-marker", sid);
  return deny(reason);
}

async function main(): Promise<void> {
  const raw = new TextDecoder().decode(await readAll(Deno.stdin));
  const input: HookInput = raw.trim() ? JSON.parse(raw) : {};
  const tool = input.tool_name ?? "";

  const editGuards: Guard[] = [
    guardBlockMain,
    guardBlockConfigEdit,
    guardAntiLoop,
    guardVerificationWrite,
    guardTestMutation,
  ];
  const bashGuards: Guard[] = [
    guardBlockMerge,
    guardBlockForbiddenDirs,
    guardBlockPrWithoutReview,
    guardVerificationWrite,
    guardTestMutation,
  ];

  const guards = tool === "Bash"
    ? bashGuards
    : tool === "Edit" || tool === "Write" || tool === "MultiEdit"
    ? editGuards
    : [];

  for (const guard of guards) {
    const result = await guard(input);
    if (result) {
      outputDeny(result);
      return;
    }
  }
}

main().catch(() => {
  Deno.exit(0);
});
