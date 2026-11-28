# Fontconfig / フォント設定

> **Diátaxis:** 📖 Reference

フォント設定でトラブルが起きたときは [troubleshoot-fonts.md](../how-to/troubleshoot-fonts.md) を参照してください。

---

## Vivaldi Browser Font Settings / Vivaldiブラウザのフォント設定

Recommended fonts for Vivaldi (Settings > Webpages > Fonts):

| Category                | Font Name          | Note                          |
| ------------------------ | ------------------- | ------------------------------ |
| Standard / 標準         | Source Han Sans    | Default fallback              |
| Sans-serif / ゴシック体 | Source Han Sans    | or 源ノ角ゴシック             |
| Serif / 明朝体          | Source Han Serif   | or 源ノ明朝                   |
| Monospace / 等幅        | HackGen Console NF | Japanese-compatible monospace |
| Cursive / 草書体        | Source Han Sans    | No JP cursive font available  |
| Fantasy / 装飾文字      | Source Han Sans    | No JP fantasy font available  |

## Source Han Font Naming / フォント名について

- **Source Han Sans** (無印) = Japanese version / 日本語版 = 源ノ角ゴシック
- **Source Han Sans SC** = Simplified Chinese / 簡体字中国語版
- **Source Han Sans TC** = Traditional Chinese / 繁体字中国語版
- **Source Han Sans K** = Korean / 韓国語版
- **Source Han Sans HC** = Hong Kong / 香港版

Note: "Source Han Sans JP" does not exist. The Japanese version is the default (no suffix).

## Installed Fonts / インストール済みフォント

Managed by Nix in `nix/modules/fonts.nix`:

- **hackgen-nf-font** - Programming font (monospace)
- **source-han-sans** - System UI font (sans-serif)
- **source-han-serif** - Document font (serif)
- **noto-fonts-color-emoji** - Color emoji fallback (terminal/desktop)

Native profile only (requested by name in the desktop configs) / native profile のみ (デスクトップの設定が名前で指名するフォント):

- **noto-fonts** - Default sans-serif / serif in `fonts.conf` (Noto Sans, Noto Serif)
- **noto-fonts-cjk-sans** - Japanese UI text in Waybar, Wofi, hyprlock and `fonts.conf` (Noto Sans CJK JP)
- **noto-fonts-cjk-serif** - Japanese serif fallback (Noto Serif CJK JP)
- **nerd-fonts.jetbrains-mono** - UI text and icon glyphs in Waybar, Wofi and Mako (JetBrainsMono Nerd Font)

A family that is requested but not installed is replaced silently by fontconfig. Check with `fc-match "<family>" family`.
指名したフォントが入っていないと、fontconfig は警告を出さずに代役を選びます。`fc-match "<family>" family` で確かめられます。

---

## 🔗 Related Documentation

- [troubleshoot-fonts.md](../how-to/troubleshoot-fonts.md) - フォント関連のトラブルシューティング
- [nix-modules.md](./nix-modules.md) - Nixモジュール構成
