# mise Tasks / mise タスク一覧

> **Diátaxis:** 📖 Reference

このリポジトリでは、よく使うコマンドを [mise](https://mise.jdx.dev/) タスクとして `.mise.toml` に定義しています。長いコマンドを覚える必要がなく、`mise run <task>` で簡単に実行できます。

```bash
# タスク一覧を表示
mise tasks
```

---

## Nix Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run nix:build` | Home Manager 設定をビルド (profile 自動判別) | `nix build .#homeConfigurations.<profile>.activationPackage` |
| `mise run nix:switch` | ビルド＆アクティベート (profile 自動判別) | build + `./result/activate` |

profile は `uname -r` から自動判別される: WSL カーネル (`microsoft` を含む) なら `archie-wsl`、それ以外は `archie`。両マシンでコマンドは同一。
| `mise run nix:check` | Flake チェック実行 | `nix flake check` |
| `mise run nix:update` | Flake inputs を更新 | `nix flake update` |
| `mise run nix:gc` | 古い世代をガベージコレクト | `nix-collect-garbage -d` |

mise タスクではないが、あわせてよく使うNix関連コマンド:

| Command | Description |
|---------|-------------|
| `nix develop` | Nixツール入りの開発シェルに入る（nil, nixpkgs-fmt, nix-tree） |

---

## Docker Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run docker:build` | Docker イメージをビルド | `docker build -t arch .` |
| `mise run docker:run` | コンテナを起動（16GB mem, 4096 CPU shares） | `docker run -itd --cpu-shares=4096 -m 16G --name arch arch:latest` |
| `mise run docker:start` | 停止中のコンテナを起動 | `docker start arch` |
| `mise run docker:stop` | コンテナを停止 | `docker stop arch` |
| `mise run docker:exec` | コンテナ内で bash 実行 | `docker exec -it arch bash` |
| `mise run docker:remove` | コンテナを停止＆削除 | `docker stop arch && docker rm arch` |

---

## Utility Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run backup` | Arch Linux パッケージリストをバックアップ (`.backup/` は gitignore 対象・ローカル用) | `mkdir -p .backup/pacman && sudo pacman -Qne > .backup/pacman/pkglist.txt` |

---

## GPG Tasks

複数端末での署名鍵運用。手順の詳細は [manage-gpg-keys.md](../how-to/manage-gpg-keys.md) を参照。

| Task | Description |
|------|-------------|
| `mise run gpg:status` | 署名鍵の有効期限を表示し、期限が近いと警告 |
| `mise run gpg:export` | 転送バンドル(公開鍵 + 秘密サブキー + ownertrust)を `.backup/gpg/` に生成 |
| `mise run gpg:import` | 新端末でバンドルをimportし、trust設定まで完了 |
| `mise run gpg:extend` | 期限延長(主キー +5y、サブキー +2y)+ バンドル再生成 |

mise タスクではないが、あわせてよく使うコマンド:

| Command | Description |
|---------|-------------|
| `nvim --headless +"call dein#install()" +qall` | Neovim プラグインをインストール |

---

## Usage Examples

```bash
# 設定を更新してアクティベート
mise run nix:switch

# パッケージを最新に更新
mise run nix:update
mise run nix:switch

# ディスク容量を解放
mise run nix:gc
```

```bash
# Dockerで動作確認
mise run docker:build
mise run docker:run
mise run docker:exec
```

---

## 🔗 Related Documentation

- [getting-started.md](../tutorials/getting-started.md) - 初回セットアップ
- [install-and-update-packages.md](../how-to/install-and-update-packages.md) - パッケージの追加・更新・ロールバック
- [nix-modules.md](./nix-modules.md) - Nixモジュール構成
