# biosugar0's dotfiles

Modern macOS dotfiles with chezmoi, AI-first development, and Japanese input support.

## Highlights

- **Dotfile Management** – chezmoi with templates for macOS-specific setup
- **Terminal Stack** – WezTerm + tmux + Neovim with seamless integration
- **AI-First Tooling** – Claude Code with Serena MCP, editprompt, git-wt
- **Japanese Support** – SKKeleton for Neovim, IME-friendly keybindings
- **Modern CLI** – bat, eza, fd, ripgrep, fzf, delta, starship

## Requirements

- macOS 13+ (Sonoma/Ventura)
- [Homebrew](https://brew.sh)
- Node.js (for editprompt)

## Quick Start

```bash
git clone https://github.com/biosugar0/dotfiles.git ~/ghq/github.com/biosugar0/dotfiles
cd ~/ghq/github.com/biosugar0/dotfiles
./install.sh
```

The installer handles:
- Homebrew packages (Brewfile)
- chezmoi dotfile application
- tmux plugin manager (tpm)
- git-wt
- editprompt

## Shell & Terminal

| Tool | Config |
|------|--------|
| zsh | zplug, fast-syntax-highlighting, async autosuggestions |
| WezTerm | Monaspace Neon, iceberg-dark, 85% opacity, WebGPU |
| Starship | Git status, AWS SSO, language indicators, battery |

## Editor (Neovim)

- **Plugin Manager**: lazy.nvim
- **LSP**: vtsls (TypeScript), denols (Deno), mason for installation
- **Completion**: nvim-cmp with LSP, buffer, path sources
- **Git**: vim-gin
- **Japanese**: SKKeleton

## Tmux

- **Prefix**: `Ctrl+B`
- **Smart Navigation**: `Ctrl+W` + hjkl (Vim/Claude Code aware)
- **editprompt**: `M-q` to open, `<Space>x` to send
- **Session Persistence**: resurrect + continuum
- **Status**: CPU, battery, pane path

## Herdr

Coding-agent-native multiplexer ([herdr.dev](https://herdr.dev/)). tmux と共存させつつ、
エージェント並列稼働時のメイン環境として移行中。

- **Config**: `dot_config/herdr/config.toml`（chezmoi 管理。runtime state は非管理）
- **Prefix**: `Ctrl+B`（tmux と同じ）+ tmux 時代の Alt 直バインドを移植
- **Agent 状態検知**: `herdr integration install claude` の hook（installer 管理、
  settings.json 側の登録は `settings.json.tmpl` に同一定義あり）
- **Claude ⇄ Herdr**: 公式 agent skill（`HERDR_ENV=1` の pane 内でのみ発動）。
  upstream が AGPL のため repo には同梱せず、install.sh が
  `~/.config/claude/skills/herdr/SKILL.md` へダウンロードする
- **tmux から置き換わるもの**: claude-count/pane-picker → サイドバー + `alt+p`、
  resurrect/continuum → server session + `resume_agents_on_restore`、
  fzf session 切替 → workspace picker
- **未移行（tmux 継続）**: editprompt（`M-q`）
- **並列タスクフロー**: `prefix+t` → branch 名入力 → `herdr-wt` が
  git wt（wt.copy/wt.hook 適用）で worktree を作成 → Herdr workspace 化
  （repo 配下にグルーピング）→ root pane で claude 起動。
  goal は UserPromptSubmit hook が `pane report-metadata` でサイドバーに反映、
  通知は Notification hook が `herdr notification show` で配送
  （`HERDR_ENV=1` のときのみ。tmux 経路は従来通り）
- **herdr-watch**: `herdr-watch --label e2e -- npm run test:e2e` で長時間ジョブを
  サイドバーの agent として表示（成功→done、失敗→blocked＝attention queue+音）。
  ビルド/テスト/deploy の失敗がエージェントの応答待ちと同じ受信箱に入る
- **worktree-setup plugin**: `dot_config/herdr/plugins/worktree-setup/`。
  Herdr ネイティブの worktree 作成（`prefix+S-g`）でも `worktree.created`
  イベントで wt.copy / wt.hook を適用（wt.copyignored のフル semantics が
  必要な場合は herdr-wt を使う）
- **herdr-pm skill**: PM 役の Claude が worker を `agent list` / `wait
  agent-status` / `pane read` / `pane run` で監督する並列開発の指揮手順

## AI Tooling

| Tool | Purpose |
|------|---------|
| Claude Code | AI coding assistant with custom hooks |
| Serena MCP | Codebase exploration |
| Context7 MCP | Library documentation |
| editprompt | Prompt engineering in editor |
| git-wt | Parallel branch development |
| cage | Sandboxing with smart presets |

## Key Bindings

### Tmux
| Key | Action |
|-----|--------|
| `M-v` / `M-s` | Split vertical / horizontal |
| `M-c` | New window |
| `M-l` / `M-h` | Next / prev window |
| `M-q` | editprompt |
| `C-e` (copy-mode) | Collect quote |

### Herdr
| Key | Action |
|-----|--------|
| `M-v` / `M-s` | Split panes |
| `M-Enter` | New tab |
| `M-]` / `M-[` | Next / prev tab |
| `M-a` | Workspace picker |
| `M-p` / `M-S-p` | Next / prev agent |
| `prefix+S-f` | Open ghq repo as workspace |
| `prefix+S-g` | New git worktree workspace (Herdr native) |
| `prefix+t` | New parallel task (git wt → workspace → claude) |

### Neovim (editprompt mode)
| Key | Action |
|-----|--------|
| `<Space>x` | Send buffer |
| `<Space>d` | Dump quotes |

## Packages

See [Brewfile](./Brewfile) for the complete list. Key packages:

**CLI**: bat, eza, fd, fzf, ripgrep, jq, delta, starship, tmux

**Languages**: go, deno, node, uv, poetry

**Dev Tools**: neovim, gh, ghq, aqua, codex

**Apps**: wezterm, docker-desktop, 1password-cli, obsidian

## License

MIT

## Author

[biosugar0](https://github.com/biosugar0)
