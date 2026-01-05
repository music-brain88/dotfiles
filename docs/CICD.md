# CI/CD Architecture

このドキュメントでは、dotfilesリポジトリのCI/CDパイプラインについて詳しく説明します。

---

## 📚 Table of Contents

- [Problem Statement](#problem-statement)
- [Solution: Hybrid Docker + Nix Pipeline](#solution-hybrid-docker--nix-pipeline)
- [Pipeline Details](#pipeline-details)
- [Caching Strategy](#caching-strategy)
- [Evolution History](#evolution-history)
- [Lessons Learned](#lessons-learned)

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

## 🔄 Pipeline Details

### Workflow Structure

ワークフローは2つのファイルに分離：

| File | Purpose |
|------|---------|
| `nix.yml` | メインパイプライン |
| `build-docker-image.yml` | Docker イメージビルド（`workflow_call`で呼び出し） |

### Pipeline Stages

1. **build-image**: Docker イメージをビルドしてGHCRにプッシュ（レイヤーキャッシュ）
2. **check**: 軽量チェック（`nix flake check --no-build`、フォーマット検証）
3. **verify-docker**: Arch Linux コンテナ内でビルド＆アクティベーション実行

### Container Configuration

コンテナは `archie` ユーザーで実行され、Home Manager設定と整合性を保つ：

```dockerfile
USER archie
WORKDIR /home/archie
```

ビルド後、`./result/activate` を実行してアクティベーションもテスト。

**Note**: `container:` セクションではなく手動で `docker run` を使用。
理由：`container:` はステップ実行前にイメージをプルするため、先にディスククリーンアップができない。

### Disk Space Management

両方のビルドジョブでディスククリーンアップを実行：

```bash
sudo rm -rf /usr/share/dotnet      # ~6GB
sudo rm -rf /usr/local/lib/android # ~10GB
sudo rm -rf /opt/ghc               # ~5GB
sudo rm -rf /usr/share/swift       # ~1.5GB
sudo rm -rf /usr/local/share/boost # ~1.5GB
```

### Overlays for CI

```nix
# flake.nix
overlays = [
  (final: prev: {
    # CIでテストが失敗するパッケージを修正
    rustup = prev.rustup.overrideAttrs (old: {
      doCheck = false;  # ネットワークテストを無効化
    });
  })
];
```

CI環境特有の問題（サンドボックス、ネットワーク制限）を回避。

---

## 💾 Caching Strategy

### Double Cache Approach

| Layer | Tool | Purpose |
|-------|------|---------|
| Docker | `type=gha` layer cache | Nix installation, base setup |
| Nix (check) | `magic-nix-cache` | 軽量チェック用 |
| Nix (verify) | `cache-nix-action` | Docker内ビルド用（`/nix` をマウント） |

### Why Different Cache Tools?

`magic-nix-cache` はホストのNix daemonイベントを購読するため、Dockerコンテナ内では動作しない。
そのため verify-docker では `nix-community/cache-nix-action` を使用。

詳細は [Evolution History](#phase-3-magic-nix-cache-の限界-216) を参照。

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

- [ARCHITECTURE.md](./ARCHITECTURE.md) - 全体設計思想
- [NIX.md](./NIX.md) - Nix/Home Manager 使い方ガイド
