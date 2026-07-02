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
- **Claude ⇄ Herdr**: `dot_config/claude/skills/herdr/SKILL.md`（公式 skill を vendor。
  `HERDR_ENV=1` の pane 内でのみ発動）
- **tmux から置き換わるもの**: claude-count/pane-picker → サイドバー + `alt+p`、
  resurrect/continuum → server session + `resume_agents_on_restore`、
  fzf session 切替 → workspace picker
- **未移行（tmux 継続）**: editprompt（`M-q`）、codex-tmux skill、OSC 777 通知の
  passthrough（Herdr 側は `[ui.toast] delivery = "terminal"` で代替）

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
| `prefix+S-g` | New git worktree workspace |

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
