# Customize Your Fork / フォークのカスタマイズ

> **Diátaxis:** 🔧 How-to

このdotfilesをフォークして自分用にカスタマイズする手順です。

---

## Changing User Information

フォークした利用者は、まず `home.nix` のユーザー名とホームディレクトリを自分のものに書き換えます。

```nix
home.username = "your-username";
home.homeDirectory = "/home/your-username";
```

次に、`.config/git/config.local.sample` を `~/.gitconfig.local` にコピーし、名前・メールアドレス・署名鍵を自分のものに書き換えます。

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

新しい Nix モジュールを追加するときは、次の 2 つの手順を行います。

1. `nix/modules/` に新しいモジュールファイルを作成します。

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

2. `home.nix` の `imports` にモジュールを追加します。

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
