# CI/CD Pipeline / CI/CDパイプライン仕様

> **Diátaxis:** 📖 Reference

このドキュメントでは、dotfilesリポジトリの現在のCI/CDパイプライン構成を説明します。なぜこの構成になったのか（課題・変遷・教訓）は [cicd-evolution.md](../explanation/cicd-evolution.md) を参照してください。

---

## 📚 Table of Contents

- [Pipeline Details](#-pipeline-details)
- [Caching Strategy](#-caching-strategy)

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
| **check** | `changes` | 軽量チェック（Nix を入れた後に shellcheck、`nix flake check --no-build`、フォーマット検証） |
| **verify-docker** | `changes`, `build-image`, `check` | Arch Linux コンテナ内でビルド＆アクティベーション実行。ビルドが要る flake の `checks`(`herdr-claude-hook-entries` と `herdr-ctx`)もここで実行する |

- `build-image` と `check` はどちらも `needs: changes` のみなので**並列実行**される。`verify-docker` は両方の完了を待つ。
- `changes` 以外の3ジョブは `if: needs.changes.outputs.code == 'true'` を持ち、docs 等のみの変更では skip される。skip されたジョブは required status checks 上は成功扱いになる。
- トリガーに `paths-ignore` を使わずこの構成にしているのは、トリガー段階で workflow を止めるとチェックが一切報告されず、PR が「Expected — waiting for status」のままマージ不能になるためである（[#312](https://github.com/music-brain88/dotfiles/issues/312)）。
- `check` ジョブの `nix flake check --no-build` は、flake の `checks` 出力を評価するだけで、ビルドも実行もしない。そのため、herdr の Claude Code 用フックのエントリの検査 `checks.herdr-claude-hook-entries` は、`verify-docker` ジョブがコンテナの中で `nix build .#checks.x86_64-linux.herdr-claude-hook-entries` として実行する。フックは直前の `archie` のビルドで出来ているので、この検査で増える依存は jq だけである。同じ理由で、`tools/herdr-ctx` のビルドと `doCheck` のテストを実行する `checks.herdr-ctx` も、`verify-docker` ジョブが `nix build .#checks.x86_64-linux.herdr-ctx` として実行する。`herdr-ctx` は直前の `archie` のビルドで出来ているので、この行で時間はほぼ増えない（[#807](https://github.com/music-brain88/dotfiles/issues/807)）。docs だけの変更では `verify-docker` が skip されるので、検査も走らない。`flake.lock` の更新 PR は docs だけの変更ではないので、検査が走る（[nix-modules.md の「Claude Code の pane の復元」](./nix-modules.md#claude-code-の-pane-の復元)、[#755](https://github.com/music-brain88/dotfiles/issues/755)）。
- `check` ジョブの shellcheck は、runner にプリインストールされた版ではなく、`flake.lock` が固定する nixpkgs の版で走る。ジョブは flake の app を `nix run .#shellcheck` で呼び、app は版を表示してから `git ls-files '*.sh' | xargs --no-run-if-empty shellcheck` を実行する。手元では `mise run lint:shellcheck` が同じ app を呼ぶので、手元と CI で版と対象が一致する。mise が無い環境では `nix run .#shellcheck` を直接実行すればよい（[#665](https://github.com/music-brain88/dotfiles/issues/665)）。

### Container Configuration

コンテナは `archie` ユーザーで実行され、Home Manager設定との整合性を保つ。

コンテナの中で走る `bash -c` のスクリプトは、先頭で `set -euo pipefail` を宣言する。`run:` の既定の `bash -e` は、`docker run` で起こした `bash -c` の中には届かない。スクリプトの側で宣言しないと、途中の行が失敗しても次の行に進み、最後の `echo` が 0 を返してジョブが成功になる。`set -euo pipefail` により、ビルド、flake の `checks`、activation のどの行が失敗しても、`verify-docker` ジョブが失敗する（[#817](https://github.com/music-brain88/dotfiles/issues/817)）。

```dockerfile
USER archie
WORKDIR /home/archie
```

CI は、ビルドした `activationPackage` の `/tmp/result/activate` を実行し、Home Manager の activation が最後まで通ることを確かめる。最後の `=== Home Manager activation completed successfully ===` は、activation が成功したときにだけ出る。次の表は、CI の環境に合わせて変えている点と、その理由を並べたものである。

| 点 | やり方 | 理由 |
|----|--------|------|
| `result` の出力先 | `nix build … -o /tmp/result` | `/workspace` は runner のユーザーが持ち主の checkout なので、コンテナの `archie` は `result` の symlink を作れない。mount と所有者は、後の step（キャッシュの保存、checkout の後始末）に響くので変えない |
| WSL のプロファイル | `nix build … --no-link` でビルドだけ | activation には実物の WSL が要る。出力は後の行が読まないので、symlink を作らない |
| `USER` | `USER="$(id -un)"` を export する | `docker run` はログインを通らないので、コンテナに `USER` が無い。activate は `set -u` の下で `$USER` を読むので、無いと止まる |
| 既存のファイルとの衝突 | activate にだけ `HOME_MANAGER_BACKUP_EXT=ci-backup` を渡す | イメージの `/etc/skel` から来た `.bashrc`・`.bash_profile` と、step が作る `.gitconfig` は、HM が管理するファイルと衝突する。HM の衝突の検査が守るのは HM の外で作られたファイルで、使い捨てのコンテナにはイメージと step が置いたファイルしか無いので、HM 公式の退避（`home-manager switch -b` と同じ）で脇に移す。退避したファイルは、activate の後にログに一覧を出す |
| `safe.directory` | `git config --global --add safe.directory /workspace` | `/workspace` の持ち主は `archie` ではないので、Nix が flake の git ツリーを開くのに要る。Nix は libgit2 で開き、libgit2 は `GIT_CONFIG_COUNT` などの環境変数を読まないので、`~/.gitconfig` に書く。activate がこのファイルを退避するので、activate より後に git や nix で `/workspace` を読む行を足さない |

退避を使うので、CI は既存のファイルとの衝突では落ちない。CI が検出し続けるのは、activate そのものの失敗（HM の組み込みの手順や `home.activation` のスクリプトの失敗）と、それより前のビルドと `checks` の失敗である。HM の設定の誤り（同じファイルを 2 つのモジュールが管理するなど）は、activate の衝突の検査ではなく、その前の評価やビルドで落ちる。

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
