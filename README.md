# biosugar0's dotfiles

Modern macOS dotfiles with chezmoi, AI-first development, and Japanese input support.

## Highlights

- **Dotfile Management** – chezmoi with templates for macOS-specific setup
- **Terminal Stack** – WezTerm + tmux + Neovim with seamless integration
- **AI-First Tooling** – Claude Code with Serena MCP, editprompt, git-worktree-runner
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
- git-worktree-runner
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

## AI Tooling

| Tool | Purpose |
|------|---------|
| Claude Code | AI coding assistant with custom hooks |
| Serena MCP | Codebase exploration |
| Context7 MCP | Library documentation |
| editprompt | Prompt engineering in editor |
| git-worktree-runner | Parallel branch development |
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
