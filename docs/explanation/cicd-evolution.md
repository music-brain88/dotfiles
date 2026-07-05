# CI/CD Evolution / CI/CDの変遷と教訓

> **Diátaxis:** 💡 Explanation

このドキュメントでは、dotfilesリポジトリのCI/CDパイプラインが抱えていた課題と、なぜ今の形になったのかを説明します。現在のパイプライン構成そのものは [ci-cd-pipeline.md](../reference/ci-cd-pipeline.md) を参照してください。

---

## 📚 Table of Contents

- [Problem Statement](#problem-statement)
- [Solution: Hybrid Docker + Nix Pipeline](#solution-hybrid-docker--nix-pipeline)
- [Evolution History](#evolution-history)
- [Lessons Learned](#lessons-learned)
- [Future Improvements](#future-improvements)

---

## ⚠️ Problem Statement

GitHub Actionsランナーのディスク容量は限られている（ubuntu-latestで約14GB）。
Nixのフルビルドは10GB以上を消費する可能性がある。

---

## 🔧 Solution: Hybrid Docker + Nix Pipeline

Nix がプリインストールされた Docker コンテナを使用してディスク容量問題を回避。

```
┌─────────────────────────────────────────────────────┐
│  GitHub Actions (nix.yml)                           │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────┐     ┌─────────────┐               │
│  │ build-image │     │    check    │               │
│  │             │     │             │               │
│  │ Docker image│     │ flake check │  ← 並列実行   │
│  │ build/push  │     │ format check│               │
│  └──────┬──────┘     └──────┬──────┘               │
│         │                   │                       │
│         └─────────┬─────────┘                       │
│                   ▼                                 │
│         ┌─────────────────┐                        │
│         │  verify-docker  │                        │
│         │                 │                        │
│         │ Build & activate│                        │
│         │ in Arch Linux   │                        │
│         │ container       │                        │
│         └─────────────────┘                        │
└─────────────────────────────────────────────────────┘
```

### Why Docker?

**Dockerを採用している主な理由：複数環境でのテストを視野に入れている**

| Target | Status | Purpose |
|--------|--------|---------|
| Arch Linux | ✅ Primary | メイン開発環境 |
| Ubuntu | 🔜 Planned | サーバー環境、WSL |
| Other distros | 🔜 Planned | 汎用性の確認 |

**Dockerにより：**
- 異なるディストリビューションでの動作確認が可能
- Nix環境のベースイメージを共有できる
- GitHub Actionsのキャッシュ機能と組み合わせて高速化

---

## 📜 Evolution History

このCI/CDパイプラインは多くの試行錯誤を経て現在の形になった。以下は遭遇した問題と解決策の記録。

### Phase 1: 初期セットアップの課題 (#191, #200)

**問題**: Nix CI/CDパイプラインの初期構築で、Dockerコンテナが `root` ユーザーで実行されていたため、`archie` ユーザー向けのHome Manager設定でactivationが失敗。

**解決**: Dockerfileに `archie` ユーザーを作成し、そのユーザーとしてビルド・アクティベーションを実行。

### Phase 2: ビルド時間の問題 (#204, #206)

**問題**: Dockerイメージのビルドに **52分** かかっていた。原因は Dockerfile 内で `nix build` を実行していたこと。ソース変更のたびにDockerレイヤーキャッシュが無効化され、毎回フルビルドが走っていた。

**解決**: `nix build` をDockerfileから削除し、CIランタイムで実行するように変更。Dockerイメージは「ベース環境（Arch Linux + Nix）」のみを提供する形に。

### Phase 3: magic-nix-cache の限界 (#216)

**問題**: `magic-nix-cache-action` がDockerコンテナ内のビルドをキャッシュしていなかった。毎回 **136個のパッケージ** がフルビルドされ、約43分かかっていた。

**根本原因**: `magic-nix-cache` はホスト側のNixデーモンのビルドイベントを購読する仕組み。Dockerコンテナ内で実行された `nix build` のイベントはホスト側のデーモンに届かない。

```
ホスト: magic-nix-cache デーモン
          ↓ 購読
        Nix デーモン（ホスト側）

Docker: nix build 実行
          ↓ ビルドイベント
        ❌ ホストのデーモンには届かない
```

**解決**: `nix-community/cache-nix-action` に移行。これはディレクトリベース（`/nix` を tar で保存）なので、Docker経由でホストの `/nix` に書き込まれた成果物もキャッシュ可能。

### Phase 4: キャッシュGCによる破損 (#228)

**問題**: `cache-nix-action` の `gc-max-store-size-linux: 6GB` 設定により、キャッシュ保存時にNix GCが実行され、Nix storeの構造が破損。

```
/usr/bin/tar: Cannot mkdir: No such file or directory
/usr/bin/tar: Exiting with failure status due to previous errors
```

**根本原因**: Nix storeはパッケージ間の依存関係が複雑。GCが「不要」と判断したパッケージを削除すると、残ったパッケージの依存ディレクトリ構造が中途半端になり、次回の tar 展開で失敗。

**解決**: `gc-max-store-size-linux` 設定を削除。フルのNix store（約14GB）でも圧縮後はGitHubの10GBキャッシュ制限内に収まる。

### Phase 5: ステップ順序の問題 (#233)

**問題**: キャッシュ復元が失敗し、毎回フルビルド（約44分）が発生。

```
現在の順序:
1. Install Nix → /nix を作成
2. Restore cache → 既存の /nix と競合して失敗
```

**解決**: ステップ順序を入れ替え。

```
正しい順序:
1. Prepare /nix directory
2. Restore cache（キャッシュがあれば復元）
3. Install Nix（キャッシュがなければインストール）
```

### Phase 6: キャッシュ凍結問題 (#368)

**問題**: 21分のジョブのうち16分が毎回のソースビルド（skim / rustup / github-copilot-cli / neovimラッパー）。primary-key は HIT しているのに、ビルド成果物が一向にキャッシュに反映されない。

**根本原因1 — 保存スキップの凍結**: `cache-nix-action` は primary-key が HIT すると post (保存) フェーズで保存自体をスキップする仕様。key は `hashFiles('**/*.nix', 'flake.lock')` から生成されるため、*.nix / flake.lock を触らない限り同じ key が使われ続け、一度不完全な状態で保存されたキャッシュが未来永劫更新されない状態になっていた。

**解決1**: `purge: true` + `purge-primary-key: always` を追加。Post Restore フェーズ（全ステップ完了後）で同じ key の古いキャッシュを毎回削除させ、直後の save 判定を「primary-key に一致するキャッシュなし」にして必ず保存し直させる（purge → save の順序はツール内部の仕様どおり）。purge には `actions: write` 権限が要るため、`verify-docker` ジョブに `permissions` を明示。

**根本原因2 — rustup 等が (見かけ上) 再ビルドされ続ける件**: 2件のヒント。
1. `flake.nix` のオーバーレイが `rustup`（`doCheck = false`）や `github-copilot-cli`（カスタム `src`）を本家 nixpkgs の派生物と異なるハッシュに変えている。これらは cache.nixos.org 上の「stock」な rustup 等とは別物なので、原理的にバイナリキャッシュから取得できず、初回ビルドは避けられない（`skim` の Hydra カバレッジ欠如は既知の別問題 #369）。
2. それとは別に、`Dockerfile` はコンテナ内 Nix を `--init none`（デーモンなし）でインストールしている。コンテナの `nix build` はホストの nix-daemon を経由せず `/nix` を直接叩くローカルストアとして使う一方、ホスト側では `nix-installer-action` が起動した nix-daemon が同じ `db.sqlite` をジョブの間ずっと開いたままにしている。SQLite の WAL は「最後の接続が閉じたとき」に自動 checkpoint される仕様のため、コンテナ側プロセスの終了は「最後の接続」にならず、ビルドで新規登録された valid path が `db.sqlite-wal` に取り残ったまま `nix: false` の cache-nix-action（DBマージ処理をしない設定）でキャッシュされてしまう可能性がある。

**対応2（仮説ベース）**: ビルド後・保存前に `sqlite3 /nix/var/nix/db/db.sqlite 'PRAGMA wal_checkpoint(TRUNCATE);'` を明示実行し、WAL の内容を本体ファイルへ確実に反映させてから保存させるステップを追加。ただし nix-installer 側のソース調査（`ProvisionNix` / `MoveUnpackedNix`）では DB を明示的に破棄する処理は見当たらず、この checkpoint 忘れ説は状況証拠からの仮説にとどまる。マージ後のダミーPRでの2回目計測で「26 derivations will be built」の内訳が縮むかどうかを見て検証する（詳細は #368 の PR 本文）。

---

## 📝 Lessons Learned

| 教訓 | 詳細 |
|------|------|
| **Dockerレイヤーキャッシュを活かす** | 変更頻度の高いステップ（ソースコピー、ビルド）はDockerfileから分離 |
| **キャッシュツールの仕組みを理解する** | magic-nix-cacheはデーモンイベント購読、cache-nix-actionはディレクトリベース |
| **GCは慎重に** | Nix storeのGCはキャッシュ破損のリスクあり。サイズ制限より完全性を優先 |
| **ステップ順序が重要** | キャッシュ復元は依存するツールのインストール前に行う |
| **ユーザー一致** | コンテナのユーザーとHome Manager設定のユーザーを一致させる |
| **同一keyでも凍結に注意** | primary-key HIT時は保存がスキップされる。設計上「毎回更新」したいなら purge-primary-key: always が要る |
| **オーバーレイはバイナリキャッシュを無効化する** | `overrideAttrs` で派生物を変えると、そのパッケージは本家の binary cache から二度と取得できなくなる |

---

## 🔮 Future Improvements

- [ ] 複数ディストリビューションでのテスト（Ubuntu, etc.）
- [ ] Nix-based CI（Hercules CI等）の検討
- [ ] キャッシュ最適化

---

## 🔗 Related Issues

- [#191](https://github.com/music-brain88/dotfiles/issues/191) - Nix CI/CD pipeline setup
- [#200](https://github.com/music-brain88/dotfiles/issues/200) - archieユーザー作成
- [#204](https://github.com/music-brain88/dotfiles/issues/204) - Nixキャッシュ調査
- [#206](https://github.com/music-brain88/dotfiles/issues/206) - Dockerイメージ軽量化
- [#216](https://github.com/music-brain88/dotfiles/issues/216) - magic-nix-cache問題
- [#228](https://github.com/music-brain88/dotfiles/issues/228) - GCによるキャッシュ破損
- [#233](https://github.com/music-brain88/dotfiles/issues/233) - ステップ順序問題
- [#368](https://github.com/music-brain88/dotfiles/issues/368) - キャッシュ凍結問題・rustup再ビルド調査

---

## 🔗 Related Documentation

- [ci-cd-pipeline.md](../reference/ci-cd-pipeline.md) - 現在のパイプライン構成、キャッシュ戦略
- [architecture.md](./architecture.md) - 全体設計思想
- [install-and-update-packages.md](../how-to/install-and-update-packages.md) - Nix/Home Manager 使い方ガイド
