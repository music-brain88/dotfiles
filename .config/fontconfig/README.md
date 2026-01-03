# Fontconfig Settings / フォント設定

## Vivaldi Browser Font Settings / Vivaldiブラウザのフォント設定

Recommended fonts for Vivaldi (Settings > Webpages > Fonts):

| Category                | Font Name          | Note                          |
| ----------------------- | ------------------ | ----------------------------- |
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

## Troubleshooting / トラブルシューティング

If fonts don't appear correctly in browsers:

```bash
# Refresh font cache / フォントキャッシュをリフレッシュ
rm -rf ~/.cache/fontconfig
fc-cache -fv

# Verify font is recognized / フォントが認識されているか確認
fc-match "Source Han Sans"
fc-list | grep -i "source han"
```

## Installed Fonts / インストール済みフォント

Managed by Nix in `nix/modules/fonts.nix`:

- **hackgen-nf-font** - Programming font (monospace)
- **source-han-sans** - System UI font (sans-serif)
- **source-han-serif** - Document font (serif)
