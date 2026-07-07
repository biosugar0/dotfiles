/**
 * hooks 共有ロガー (TS 版): decision イベントを JSONL に追記する。
 * harness-audit の実測データ源。transcript には hook の block 決定が記録されないため、
 * hook 自身が発火実績を残す。best-effort — ログ失敗で hook 本体を絶対に失敗させない。
 *
 * 出力先: $HOME/.local/state/claude/harness-events.jsonl
 *   意図的に XDG_STATE_HOME を見ない固定パス。stop-hook の shebang (env -S) は
 *   ${HOME} しか展開できないため allow-write と出力先を確実に一致させるには
 *   固定パスが必要。bash 版 logger / cc-harness-metrics も同じパスに揃えている。
 * 集計:   cc-harness-metrics
 */

export async function harnessLog(
  hook: string,
  event: string,
  detail = "",
  session = "",
  data?: Record<string, unknown>,
): Promise<void> {
  try {
    const dir = `${Deno.env.get("HOME")}/.local/state/claude`;
    await Deno.mkdir(dir, { recursive: true });
    const record: Record<string, unknown> = {
      ts: new Date().toISOString(),
      hook,
      event,
      detail,
      session,
      cwd: Deno.cwd(),
    };
    if (data !== undefined) {
      record.data = data;
    }
    const line = JSON.stringify(record) + "\n";
    await Deno.writeTextFile(`${dir}/harness-events.jsonl`, line, {
      append: true,
    });
  } catch {
    // best-effort
  }
}
