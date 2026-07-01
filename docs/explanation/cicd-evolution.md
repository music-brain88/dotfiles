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

---

## 📝 Lessons Learned

| 教訓 | 詳細 |
|------|------|
| **Dockerレイヤーキャッシュを活かす** | 変更頻度の高いステップ（ソースコピー、ビルド）はDockerfileから分離 |
| **キャッシュツールの仕組みを理解する** | magic-nix-cacheはデーモンイベント購読、cache-nix-actionはディレクトリベース |
| **GCは慎重に** | Nix storeのGCはキャッシュ破損のリスクあり。サイズ制限より完全性を優先 |
| **ステップ順序が重要** | キャッシュ復元は依存するツールのインストール前に行う |
| **ユーザー一致** | コンテナのユーザーとHome Manager設定のユーザーを一致させる |

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

---

## 🔗 Related Documentation

- [ci-cd-pipeline.md](../reference/ci-cd-pipeline.md) - 現在のパイプライン構成、キャッシュ戦略
- [architecture.md](./architecture.md) - 全体設計思想
- [install-and-update-packages.md](../how-to/install-and-update-packages.md) - Nix/Home Manager 使い方ガイド
