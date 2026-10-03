# Install and Update Packages / パッケージの追加・更新

> **Diátaxis:** 🔧 How-to

パッケージの追加、更新、ロールバック、ガベージコレクションの手順です。タスクコマンドの一覧は [mise-tasks.md](../reference/mise-tasks.md) を参照してください。

---

## Adding New Packages

新しいパッケージは、`home.nix` または対応するモジュールファイルの `home.packages` に追加します。

```nix
# nix/modules/dev-tools.nix
home.packages = with pkgs; [
  # Existing packages...

  # Add new package
  cowsay
  htop
];
```

どのモジュールに追加すべきかは [nix-modules.md](../reference/nix-modules.md) を参照してください。

---

## Updating Packages

全パッケージを更新するときは、`nix flake update` で flake のすべての入力を更新します。その後、更新した設定をビルドして有効にします。

```bash
# Update all flake inputs (nixpkgs, home-manager, etc.)
nix flake update

# Rebuild and activate the updated configuration
nix run home-manager/master -- switch --flake .#archie
```

### Updating Specific Package

nixpkgs だけを更新するときは、`nix flake lock --update-input nixpkgs` を使います。

```bash
# Update only nixpkgs
nix flake lock --update-input nixpkgs

# Rebuild
nix run home-manager/master -- switch --flake .#archie
```

---

## Overriding Package Versions

特定のパッケージのバージョンを固定する場合は、次のように `flake.nix` を書きます。

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";  # Specific version
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }: {
    # Use unstable for specific packages
    homeConfigurations.archie = {
      home.packages = [
        nixpkgs-unstable.legacyPackages.${system}.neovim
      ];
    };
  };
}
```

---

## Rolling Back

ロールバックするときは、`home-manager generations` で世代の一覧を確認し、戻したい世代の `activate` を実行します。

```bash
# List all generations
home-manager generations

# Rollback to previous generation
/nix/store/<hash>-home-manager-generation/activate

# Or use the generation number
home-manager generations | head -2 | tail -1 | awk '{print $7}' | xargs -I {} {}/activate
```

---

## Garbage Collection

古い世代を削除するときは、`nix-collect-garbage` を実行します。

```bash
# Remove old generations
nix-collect-garbage -d

# Or keep last N days
nix-collect-garbage --delete-older-than 30d
```

`mise run nix:gc` でも同じことができます。

---

## Development Shell

`nix develop` を実行すると、Nix 用のツール(nil、nixpkgs-fmt、nix-tree)が使える開発シェルに入ります。

```bash
# Enter development shell with Nix tools
nix develop

# Available tools: nil, nixpkgs-fmt, nix-tree
```

---

## 🔗 Related Documentation

- [mise-tasks.md](../reference/mise-tasks.md) - タスクコマンド一覧
- [nix-modules.md](../reference/nix-modules.md) - Nixモジュール構成
- [troubleshoot-nix.md](./troubleshoot-nix.md) - トラブルシューティング
