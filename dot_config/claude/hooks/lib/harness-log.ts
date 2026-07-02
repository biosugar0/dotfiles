/**
 * hooks 共有ロガー (TS 版): decision イベントを JSONL に追記する。
 * harness-audit の実測データ源。transcript には hook の block 決定が記録されないため、
 * hook 自身が発火実績を残す。best-effort — ログ失敗で hook 本体を絶対に失敗させない。
 *
 * 出力先: ${XDG_STATE_HOME:-~/.local/state}/claude/harness-events.jsonl
 * 集計:   cc-harness-metrics
 */

export async function harnessLog(
  hook: string,
  event: string,
  detail = "",
  session = "",
): Promise<void> {
  try {
    const base = Deno.env.get("XDG_STATE_HOME") ??
      `${Deno.env.get("HOME")}/.local/state`;
    const dir = `${base}/claude`;
    await Deno.mkdir(dir, { recursive: true });
    const line = JSON.stringify({
      ts: new Date().toISOString(),
      hook,
      event,
      detail,
      session,
      cwd: Deno.cwd(),
    }) + "\n";
    await Deno.writeTextFile(`${dir}/harness-events.jsonl`, line, {
      append: true,
    });
  } catch {
    // best-effort
  }
}
