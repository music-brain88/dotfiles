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

`.config/git/config.local.sample` を `~/.gitconfig.local` にコピーして編集:

```bash
cp .config/git/config.local.sample ~/.gitconfig.local
```

```ini
[user]
	name = Your Name
	email = your.email@example.com
	signingkey = your-signing-key
```

`.config/git/config` 冒頭の `[include] path = ~/.gitconfig.local` でこのファイルが読み込まれます。`nix/modules/git.nix` は `home.file.".gitconfig".source = ../../.config/git/config` として共通設定のみをシンボリックリンクしており、`programs.git` はこのリポジトリでは使用されていません。ユーザー情報は `~/.gitconfig.local` 側で管理してください。

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
