# Customize Your Fork / フォークのカスタマイズ

> **Diátaxis:** 🔧 How-to

このdotfilesをフォークして自分用にカスタマイズする手順です。

---

## Changing User Information

`home.nix` を編集:

```nix
home.username = "your-username";
home.homeDirectory = "/home/your-username";
```

`nix/modules/git.nix` を編集:

```nix
programs.git = {
  userName = "Your Name";
  userEmail = "your.email@example.com";
};
```

---

## Creating New Module

1. `nix/modules/` に新しいモジュールファイルを作成:

```nix
# nix/modules/custom.nix
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Your packages here
  ];

  # Additional configuration
}
```

2. `home.nix` でモジュールをインポート:

```nix
imports = [
  # Existing modules...
  ./nix/modules/custom.nix
];
```

既存モジュールの構成は [nix-modules.md](../reference/nix-modules.md) を参照してください。

---

## 🔗 Related Documentation

- [nix-modules.md](../reference/nix-modules.md) - Nixモジュール構成
- [install-and-update-packages.md](./install-and-update-packages.md) - パッケージの追加・更新
- [getting-started.md](../tutorials/getting-started.md) - 初回セットアップ
