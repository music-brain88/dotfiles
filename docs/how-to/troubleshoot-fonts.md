# Troubleshoot Fonts / フォントのトラブルシューティング

> **Diátaxis:** 🔧 How-to

フォントの一覧・設定値は [fontconfig.md](../reference/fontconfig.md) を参照してください。

---

If fonts don't appear correctly in browsers:

```bash
# Refresh font cache / フォントキャッシュをリフレッシュ
rm -rf ~/.cache/fontconfig
fc-cache -fv

# Verify font is recognized / フォントが認識されているか確認
fc-match "Source Han Sans"
fc-list | grep -i "source han"
```

---

## 🔗 Related Documentation

- [fontconfig.md](../reference/fontconfig.md) - フォント設定一覧
