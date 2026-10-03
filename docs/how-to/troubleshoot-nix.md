# Troubleshoot Nix / Nixのトラブルシューティング

> **Diátaxis:** 🔧 How-to

Nix/Home Managerのセットアップでよく遭遇する問題と解決方法です。

---

## Common Issues

### 1. Flakes not enabled

**Error**: `error: experimental Nix feature 'flakes' is disabled`

**Solution**:

```bash
# Add to ~/.config/nix/nix.conf
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 2. Build fails due to unfree packages

**Error**: `Package 'xxx' has an unfree license`

**Solution**: Already enabled in `flake.nix` via:

```nix
nixpkgs.config.allowUnfree = true;
```

### 3. Home Manager activation fails (既存ファイルの競合)

**Error**: `Existing file 'xxx' would be clobbered`

```
Existing file '/home/archie/.config/starship.toml' would be clobbered
Existing file '/home/archie/.config/fish/config.fish' would be clobbered
```

このエラーは、Home Manager が管理したいファイルが既に存在するときに出ます。Home Manager は既存ファイルを上書きしてよいかわからないので、そこで処理を止めます。

**Solution**: `-b backup` オプションを付けて実行すると、Home Manager が既存ファイルを自動でバックアップします。

```bash
nix run home-manager/master -- switch --flake .#archie -b backup
```

これで既存ファイルは `.backup` 拡張子付きでリネームされます（例: `starship.toml.backup`）。

**リストア方法**: バックアップから戻すときは、ファイルを手動で戻すか、Home Manager の世代でロールバックします。

```bash
# バックアップから手動で戻す
mv ~/.config/starship.toml.backup ~/.config/starship.toml

# または Home Manager の世代でロールバック
home-manager generations
/nix/store/xxxxx-home-manager-generation/activate
```

> 既存の `.config/` ディレクトリ内の設定ファイルは、`home.nix` でシンボリックリンクされています。これにより、既存のカスタマイズを維持しながら、パッケージ管理をNixに移行できます。

### 4. Package not found

**Error**: `attribute 'xxx' missing`

**Solution**: Search for the package:

```bash
# Search in nixpkgs
nix search nixpkgs xxx

# Or use online search
# https://search.nixos.org/packages
```

---

## Debug Tools

### nix-tree

`nix-tree` は依存関係ツリーを可視化します。`nix develop` で開発シェルに入ってから実行します。

```bash
# Enter dev shell
nix develop

# View dependency tree
nix-tree
```

### nix repl

`nix repl` は、Nix expressionを対話的に評価します。

```bash
nix repl
> :l <nixpkgs>
> pkgs.hello
```

### Verbose output

詳細なビルドログを表示するときは、`--show-trace --verbose` を付けてビルドします。

```bash
nix build --show-trace --verbose .#homeConfigurations.archie.activationPackage
```

---

## 🔗 Related Documentation

- [getting-started.md](../tutorials/getting-started.md) - 初回セットアップ
- [install-and-update-packages.md](./install-and-update-packages.md) - パッケージの追加・更新・ロールバック
- [mise-tasks.md](../reference/mise-tasks.md) - タスクコマンド一覧
