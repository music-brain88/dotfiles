# CI/CD Pipeline / CI/CDパイプライン仕様

> **Diátaxis:** 📖 Reference

このドキュメントでは、dotfilesリポジトリの現在のCI/CDパイプライン構成を説明します。なぜこの構成になったのか（課題・変遷・教訓）は [cicd-evolution.md](../explanation/cicd-evolution.md) を参照してください。

---

## 📚 Table of Contents

- [Pipeline Details](#pipeline-details)
- [Caching Strategy](#caching-strategy)

---

## 🔄 Pipeline Details

### Workflow Structure

CI のワークフローは、次の表の 2 つのファイルに分かれている。

| File | Purpose |
|------|---------|
| `nix.yml` | メインパイプライン |
| `build-docker-image.yml` | Docker イメージビルド（`workflow_call`で呼び出し） |

### Pipeline Stages

次の図は、`nix.yml` のジョブ依存グラフ（`needs:`）を示す。図の後の表は、各ジョブの依存先と役割を並べたものである。

```
changes ─┬─→ build-image ─┬─→ verify-docker
         └─→ check ───────┘
```

| Job | `needs` | Purpose |
|-----|---------|---------|
| **changes** | — | 変更ファイルを判定し、下流ジョブの実行要否を `code` 出力で返す。`*.md` / `docs/` / `llm/` / `LICENSE` / `.gitignore` 以外に変更があれば `code=true`。base SHA が取れない場合（force push・ブランチ新規作成等）は安全側に倒して `code=true` |
| **build-image** | `changes` | Docker イメージをビルドしてGHCRにプッシュ（レイヤーキャッシュ。`build-docker-image.yml` を `workflow_call` で呼び出し） |
| **check** | `changes` | 軽量チェック（shellcheck、`nix flake check --no-build`、フォーマット検証） |
| **verify-docker** | `changes`, `build-image`, `check` | Arch Linux コンテナ内でビルド＆アクティベーション実行 |

- `build-image` と `check` はどちらも `needs: changes` のみなので**並列実行**される。`verify-docker` は両方の完了を待つ。
- `changes` 以外の3ジョブは `if: needs.changes.outputs.code == 'true'` を持ち、docs 等のみの変更では skip される。skip されたジョブは required status checks 上は成功扱いになる。
- トリガーに `paths-ignore` を使わずこの構成にしているのは、トリガー段階で workflow を止めるとチェックが一切報告されず、PR が「Expected — waiting for status」のままマージ不能になるためである（[#312](https://github.com/music-brain88/dotfiles/issues/312)）。

### Container Configuration

コンテナは `archie` ユーザーで実行され、Home Manager設定との整合性を保つ。

```dockerfile
USER archie
WORKDIR /home/archie
```

CI はビルド後に `./result/activate` を実行し、アクティベーションもテストする。

**Note**: CI は `container:` セクションではなく、手動で `docker run` を使う。
理由は、`container:` がステップ実行前にイメージをプルするため、先にディスククリーンアップができないことである。

### Disk Space Management

両方のビルドジョブは、次のコマンドでディスククリーンアップを実行する。

```bash
sudo rm -rf /usr/share/dotnet      # ~6GB
sudo rm -rf /usr/local/lib/android # ~10GB
sudo rm -rf /opt/ghc               # ~5GB
sudo rm -rf /usr/share/swift       # ~1.5GB
sudo rm -rf /usr/local/share/boost # ~1.5GB
```

### Overlays for CI

CI でテストが失敗するパッケージは、`flake.nix` の overlay で修正している。

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

この overlay は、CI環境特有の問題（サンドボックス、ネットワーク制限）を回避するためのものである。

---

## 💾 Caching Strategy

### Double Cache Approach

次の表は、CI のキャッシュを層ごとに分け、使うツールと用途を並べたものである。

| Layer | Tool | Purpose |
|-------|------|---------|
| Docker | `type=gha` layer cache | Nix installation, base setup |
| Nix (check) | `magic-nix-cache` | 軽量チェック用 |
| Nix (verify) | `cache-nix-action` | Docker内ビルド用（`/nix` をマウント） |

### Why Different Cache Tools?

`magic-nix-cache` はホストのNix daemonイベントを購読するため、Dockerコンテナ内では動作しない。
そのため verify-docker では `nix-community/cache-nix-action` を使用する。

詳細は [Evolution History - Phase 3](../explanation/cicd-evolution.md#phase-3-magic-nix-cache-の限界-216) に書いてある。

### Cache Update Strategy (purge → save)

`cache-nix-action` は、primary-key が HIT すると保存自体をスキップする仕様である。
そのため、何もしないと「一度保存された不完全なキャッシュ」が key が変わるまで凍結する。
`verify-docker` では `purge: true` + `purge-primary-key: always` を指定している。
これにより、Post Restore フェーズ（全ステップ完了後）で同じ key の古いキャッシュを毎回削除させてから保存させ、
実行のたびに最新の `/nix` store 内容で更新されるようにしている。
purge の実行には `actions: write` 権限が必要で、ジョブの `permissions` で付与している。

詳細と rustup 再ビルドの調査は [Evolution History - Phase 6](../explanation/cicd-evolution.md#phase-6-キャッシュ凍結問題-368) に書いてある。

---

## 🔗 Related Documentation

- [cicd-evolution.md](../explanation/cicd-evolution.md) - CI/CDの課題・変遷・教訓
- [architecture.md](../explanation/architecture.md) - 全体設計思想
- [install-and-update-packages.md](../how-to/install-and-update-packages.md) - Nix/Home Manager 使い方ガイド
