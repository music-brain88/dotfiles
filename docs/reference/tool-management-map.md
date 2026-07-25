# Tool Management Map / ツール管轄マップ

> **Diátaxis:** 📖 Reference

どのツールをどの層(Nix / OS / mise / native installer)が管理するかの一覧です。導入・掃除の実際の手順は [install-unmanaged-tools.md](../how-to/install-unmanaged-tools.md) を、Nix と symlink の分担の設計思想は [architecture.md](../explanation/architecture.md) を参照してください。

---

## レイヤー一覧 / Layers

| Layer              | Manager                 | 定義場所                                                             | 更新方法                                   |
| ------------------ | ----------------------- | -------------------------------------------------------------------- | ------------------------------------------ |
| Nix (Home Manager) | flake.nix + nix/modules | `home.nix`, `nix/modules/*.nix`                                      | `mise run nix:update` → `mise run nix:switch` |
| OS (Arch)          | pacman / paru           | 宣言なし(`mise run backup` でリスト退避)                             | `sudo pacman -Syu` / `paru -Syu`           |
| mise               | mise                    | `.config/mise/config.toml`(グローバル) / 各リポジトリの `.mise.toml` | 宣言変更 → `mise install`                  |
| Native installer   | ツール自身              | なし(`~/.local/bin` + `~/.local/share/<tool>`)                       | 自動更新                                   |
| 手動               | なし                    | なし                                                                 | 手動(整理・宣言化の候補)                   |

---

## ツール別管轄 / Tool Assignments

| Tool                                                               | Layer                | 定義場所・実体                                                             |
| ------------------------------------------------------------------ | -------------------- | -------------------------------------------------------------------------- |
| git / gh / fish / nvim / docker / gpg / rustup ほか CLI 開発ツール | Nix                  | `nix/modules/*.nix`                                                        |
| herdr / copilot-cli                                                | Nix (overlay)        | `flake.nix`                                                                |
| mise 本体                                                          | Nix                  | `nix/modules/dev-tools.nix`(`programs.mise`)                               |
| Hyprland / Waybar / WezTerm / Alacritty / Obsidian                 | OS (pacman)          | 設定のみ Nix が symlink                                                    |
| paru                                                               | OS (pacman)          | AUR ヘルパー                                                               |
| tailscale                                                          | OS (pacman) **暫定** | PoC 中。dotfiles 統合の設計が固まるまで OS 層                              |
| node(グローバル)                                                   | mise                 | `.config/mise/config.toml`(claude 以外の npm ツール用に維持 — 経緯は #486) |
| node / poetry / uv(プロジェクト)                                   | mise                 | 各リポジトリの `.mise.toml`                                                |
| claude (Claude Code)                                               | Native installer     | `~/.local/bin/claude` → `~/.local/share/claude/versions/`                  |
| copilot-quorum                                                     | 手動                 | 自作ツール。ローカルリポジトリからビルドして `~/.local/bin` に配置         |

> **Note:** `mise ls` に上表にない宣言なしのツールが出る場合、過去の手動インストールの残りです。宣言化するか削除してください([install-unmanaged-tools.md のトラブルシューティング](../how-to/install-unmanaged-tools.md#トラブルシューティング--troubleshooting) 参照)。

---

## 各層の理由 / Why This Layering

- **Nix が基本**: 再現性のため、CLI ツールは原則 Nix で宣言する([architecture.md](../explanation/architecture.md) の設計思想)
- **更新の速い AI CLI は Nix に入れない**: Claude Code のようにほぼ毎日更新されるツールを Nix 管理にすると、自己更新が効かず nixpkgs / overlay の bump 追随が常時必要になる。実際に nixpkgs bump で copilot-cli overlay が壊れた事故(#380)があり、native installer の自動更新に任せる方が総コストが低い(#486)
- **WM / GUI 層は OS**: Wayland compositor やグラフィックドライバはシステム統合が必要で、ユーザー空間の Home Manager に閉じない。バイナリは pacman、設定は Nix が symlink するという分担
- **言語ランタイムは mise**: プロジェクトごとのバージョン固定は mise の担当([architecture.md の言語ランタイムのバージョン方針](../explanation/architecture.md) 参照)

---

## 判断基準 / Decision Guide

新しいツールを導入するとき、どの層に置くかは次の基準で決めます。

0. **そもそも宣言に載せるか(前段ゲート)**: PoC 中のツールや、状態・認証(鍵・トークン)が本体のツールは、層を割り当てる前に「まだ宣言に載せない」と判断する。宣言化は決定の凍結 — PoC → 統合の確度が固まってから層を決める(例: tailscale は統合設計が固まるまで暫定で OS 層)
1. **更新頻度と主導権**: ほぼ毎日更新されるツールは Nix 管理に向かない。mise / native installer に任せる。ただし見るべきは頻度そのものより**リリースの主導権が誰にあるか** — 自作ツール(herdr 等)は更新が速くても bump 追従が自分の作業の一部なので Nix (overlay) でよい。逆に gcc / make / rustup のようなビルドツールチェーン(一番の土台)は再現性が最優先なので Nix
2. **システム統合の必要性**: Wayland compositor やグラフィックドライバ等、ユーザ空間に閉じないツールは OS 層に置く
3. **プロジェクト依存性**: 基本的に Nix 管理で行うが、そのプロジェクトを再現する最低限の必要なツールは mise に置く。mise はランタイムのバージョン管理とする
4. **宣言化のコスト**: 1と似た理由ではあるが、再現性のために Nix 管理にする場合、Nixpkgs / overlay の bump 追従が必要となる。端末ごとに確実に構築する場合は Nix

---

## 🔗 Related Documentation

- [install-unmanaged-tools.md](../how-to/install-unmanaged-tools.md) — Nix 管理外ツールの導入・掃除の手順
- [architecture.md](../explanation/architecture.md) — Nix + Symlink ハイブリッドの設計思想
- [nix-modules.md](./nix-modules.md) — Nix モジュール構成
- [mise-tasks.md](./mise-tasks.md) — mise タスク一覧
