---
name: apple-container
description: この Mac でローカルに DB・ミドルウェア（postgres・redis 等）を起動する、Linux 開発環境を用意する、OCI コンテナ/イメージを操作する（pull/build/push・レジストリ認証）、コンテナが起動しない/落ちる/ログを見たい、ディスクを食っている、といった話は必ずまずこの skill を確認する。「docker compose で前はやってた」「docker run 相当のことがしたい」「spin up」「run locally」「testcontainers」のように docker/container という単語が出てくる場合はもちろん、出てこなくても同種の意図なら対象。この Mac の実体は Docker ではなく apple/container（`container` CLI）と container-compose であり、Docker 前提の手順はそのままでは動かないため、代替可否をこの skill で判断してから進める。対象外: ECS・Kubernetes・ECR など本番/クラウド上のコンテナ、CI 上のコンテナ、iOS アプリの App Container、Homebrew 直インストールのサービス、Next.js 等のアプリ開発サーバー起動。
---

# apple-container（`container` CLI）

Apple 製の `container` は、Linux コンテナを **軽量 VM 1 つ = コンテナ 1 個** の方式で Mac 上に起動するランタイム。OCI 互換イメージなので Docker / podman のイメージがそのまま動く。起動は 1 秒未満、Docker Desktop より隔離が強い。リポジトリは [apple/container](https://github.com/apple/container)。

要件: Apple Silicon + macOS 26 推奨（macOS 15 はネットワーク機能がほぼ使えない）。ゲストは `linux/arm64`（ネイティブ）と `linux/amd64`（Rosetta 経由）のみ。

## この Mac のセットアップ状態（2026-07 時点、実測）

- `container` / `container-compose` を Homebrew で導入済み（Brewfile 管理）
- `CONTAINER_DEFAULT_PLATFORM="linux/arm64"` を `~/.config/zsh/.zshenv` で export 済み
- サービスが落ちていたら `container system start`。ログイン時自動起動は `brew services start container`
- Docker Desktop は併存中（testcontainers 等 Docker API 依存の用途向け）。日常のコンテナ操作は container を使う

## 実測済みの罠（先に読む）

- **pull は既定で全アーキテクチャを取得する**。`container image pull postgres:17.6` は s390x / riscv64 含む全 platform で **5.6GB** 消費した（`--platform linux/arm64` なら **1.0GB**）。`CONTAINER_DEFAULT_PLATFORM` で抑止しているが、この env が届かない文脈（launchd 経由、container-compose からの pull 等）では `--platform linux/arm64` を明示するか、事前に platform 指定で pull しておく
- **匿名ボリュームは `--rm` でも消えない**（Docker と違う）。`container volume rm` で明示的に削除
- **メモリ返却が部分的**。長時間動かすと Activity Monitor 上で肥大して見える。メモリ集約型を多数動かしたら定期的にコンテナを再起動
- ディスク使用量の確認は `container system df`。イメージ整理は `container image prune`（既定は dangling のみ削除）／ `container image prune -a`（未使用イメージ全体）／タグ付きで参照中のものは個別に `container image rm`

## Docker から移行して動かないもの

- **Docker API socket（`/var/run/docker.sock`）互換なし** → testcontainers、localstack の docker socket マウント、Docker API 依存ツールは不可。必要なら Docker Desktop を使う
- **`--restart=always` 等の再起動ポリシーなし** → launchd / brew services で代替
- **compose はネイティブ非対応** → 下記の container-compose で代替

## sandbox（Claude Code / cage）内で動かないコマンド（実測）

Claude Code や codex は cage の sandbox-exec 配下で動く。この中では一部の `container system` サブコマンドが正しく動かないので、AI セッションから叩かず**ユーザー自身のシェル**（プロンプトで `! <cmd>`）で実行してもらう:

- `container system logs` → `log: Cannot run while sandboxed`（sandbox 検知で拒否。FS 許可を足しても直らない）
- `container system status` → apiserver が動いていても **`not running and not registered` と誤答**する（sandbox から launchd 登録状態を見られない）。稼働確認は `launchctl print gui/$(id -u)/com.apple.container.apiserver` の `state`、または実際に `container run` してみる方が確実
- `container system start` / `stop` → launchd plist 書き込みで `Operation not permitted`（start は失敗、stop は no-op になる）。常駐化・停止はユーザーのシェルで

**sandbox 内でも問題なく動く**（apiserver へ socket 越しに依頼するため）: `container run` / `build` / `exec` / `cp` / `pull` / `push` / `ls` / `image ls` / `stats` / `system df` / `system version`、および `container-compose up` / `down`。日常操作は困らない。

## compose（container-compose、third-party）

`container-compose up --detach` / `down` / `build`。`-f` でファイル指定。実測での挙動:

- `.env` / 環境変数 / ports / depends_on に対応し、`docker-compose.yml` をそのまま読む。ただし公式に "limited Docker Compose support" と明記されており、healthcheck・restart policy・Docker socket 依存・複雑な compose 機能は期待しない
- compose の named volume は container-compose 側で `~/.containers/Volumes/<project>/<vol>` への symlink に変換されて代替される（`container-compose` 自体の制約。素の `container run -v myvol:/path` は named volume を直接サポートしている）
- `down` はコンテナを stop するだけで rm しない。残骸は `container rm <id>` で消す
- pull が platform 無指定で走る（全 arch 取得の罠を踏む）。大きいイメージは事前に `container image pull --platform linux/arm64 <ref>` してから up する

## クイックリファレンス

| やりたいこと | コマンド |
|:--|:--|
| サービス起動 / 停止 | `container system start` / `container system stop` |
| イメージ取得 | `container image pull <ref>` |
| イメージビルド | `container build -t <name> .` |
| 対話実行 | `container run -it <image> /bin/sh` |
| バックグラウンド実行 | `container run -d --name <name> --rm <image>` |
| ポート公開 | `container run -p 127.0.0.1:8080:80 <image>` |
| ボリュームマウント | `container run -v $HOME/x:/x <image>` |
| SSH 転送 | `container run --ssh <image>` |
| シェルに入る | `container exec -it <id> sh` |
| ログ追従 | `container logs -f <id>` |
| 起動ログ | `container logs --boot <id>` |
| 統計表示 | `container stats <id>` |
| コピー | `container cp <src> <dst>` |
| 停止・削除 | `container stop <id>` / `container rm <id>` |
| イメージ push | `container image push <ref>` |
| レジストリ認証 | `container registry login <host>` |
| ネットワーク作成 | `container network create <name>` |
| DNS ドメイン作成 | `sudo container system dns create <name>` |
| ボリューム作成 | `container volume create <name>` |
| マシン作成 | `container machine create <image> --name <id>` |
| マシンでシェル | `container m run -n <id>`（`m` 単体コマンドはこの Mac では未設定） |
| ディスク使用量 | `container system df` |
| サービスログ | `container system logs -f` |
| バージョン確認 | `container system version` |

## 詳細リファレンス

上記で足りないときだけ `references/cli-reference.md` の該当セクションを読む（冒頭に目次あり）:

- `run` の全オプション（リソース・マウント・capability・init・ネスト仮想化）、`build` とビルダー VM の調整
- ネットワーク・ローカル DNS ドメイン（`host.container.internal` パターン含む）
- ボリュームの ext4 ジャーナルモード、`container machine`（永続 Linux 開発環境）
- `~/.config/container/config.toml` の全セクション、インストール / アップグレード手順、シェル補完

## 出典

本ファイルおよび `references/cli-reference.md` は [voluntas 氏の gist](https://gist.github.com/voluntas/306e75ce54a24379b4b505cf9c4df0cd)（Apache-2.0、2026-06-28 版）を元にした改変版（derivative work）。元ライセンスは [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0) に従う。主な変更点: 冒頭・構成を SKILL.md 用に再編成、この Mac（macOS 26.4 / container 1.0.0_1）での実測知見（2026-07-03）の追加、`m`→`container m` 表記や subnet 表記等の誤りの修正（2026-07-03、codex によるレビュー指摘を反映）。
