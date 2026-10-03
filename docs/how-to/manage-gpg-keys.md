# Manage GPG Keys / GPG鍵の複数端末運用

> **Diátaxis:** 🔧 How-to

コミット署名用GPG鍵を複数端末で運用するための手順です。新端末セットアップ、有効期限の延長、主キーのオフライン保管をカバーします。タスクコマンドの一覧は [mise-tasks.md](../reference/mise-tasks.md) を参照してください。

---

## 鍵構成の考え方 / Key Layout

この運用は「主キー + サブキー」構成を前提としています。次の図は、主キーと 2 つのサブキーの構成と、それぞれの役割を示します。

```
sec  ed25519 [SC]  ← 主キー: 証明(Certify)専用。サブキーの発行・失効に使う
ssb  cv25519 [E]   ← 暗号化サブキー: 日常の暗号化
ssb  ed25519 [S]   ← 署名サブキー: コミット署名の実体
```

- **利用者が各端末に配るのは、サブキーの秘密鍵だけです**。主キーの秘密鍵は信頼できる1箇所(オフラインのUSB等)に保管します。
- 端末が漏洩しても、サブキーだけを失効(revoke)すれば、主キーと鍵のアイデンティティは守られます。
- git の `user.signingkey` には主キーIDを指定すれば足ります。GPGが自動的に有効な署名サブキーを選んで署名します。

---

## 新端末セットアップ / New Machine Setup

### 1. 転送元(既存端末)でバンドルを作成

```bash
mise run gpg:export
```

`mise run gpg:export` は、`.backup/gpg/` に次の 3 ファイルを生成します(`.backup/` は gitignore 対象です)。

| File | Contents |
|------|----------|
| `public.asc` | 公開鍵(主キー + 全サブキー) |
| `secret-subkeys.asc` | **サブキーのみ**の秘密鍵(パスフレーズで保護されたまま) |
| `ownertrust.txt` | trust設定(これがあると「trustを毎回設定し直す」作業が消える) |

### 2. 新端末へ安全に転送

バンドルを新端末へ転送する方法は 2 つあります。推奨するのは方法A の Bitwarden 経由で、方法B は scp による直接転送です。

**方法A: Bitwarden 経由(推奨)**

```bash
# 転送元: バンドルを vault にアップロード(既存添付は自動で置き換え)
mise run gpg:bw:push
```

初回だけ、利用者は事前に Bitwarden に `gpg-bundle` という名前のセキュアノートを作成しておきます(アイテム名は環境変数 `GPG_BW_ITEM` で変更できます)。バンドルの保存に添付ファイル機能を使うため、Bitwarden Premium が必要です。

> **⚠️ 運用ルール:** GPGのパスフレーズを同じアイテム(またはvault)に保存しないこと。バンドルの秘密サブキーはパスフレーズで保護されており、これが二重ロックとして機能する。

**方法B: scp で直接転送**

```bash
scp -r .backup/gpg new-machine:~/dotfiles/.backup/
```

### 3. 新端末でインポート

新端末では、次のコマンドでバンドルをインポートします。

```bash
# Bitwarden 経由の場合は先にログイン(端末ごとに初回のみ)
bw login

mise run gpg:import   # .backup/gpg/ が無ければ Bitwarden から自動取得
```

> **Note:** vault がロック中の場合は、タスクがその場でマスターパスワードを聞いてきます(自己解錠)。そのため、利用者がシェルごとに `BW_SESSION` を export する必要はありません。

インポート後、`sec#`(`#` 付き)と表示されれば「主キーの秘密鍵はこの端末に無い」状態で正常です。

### 4. 転送済みバンドルを削除

インポートが終わったら、利用者は転送元と新端末の両方でバンドルを削除します。

```bash
rm -rf .backup/gpg   # 両端末で
```

---

## 有効期限の延長 / Extending Expiry

期限切れが近づいたら(`mise run gpg:status` が警告したら)、利用者は**主キーの秘密鍵がある端末で**次のコマンドを実行します。

```bash
mise run gpg:extend
```

このタスクは主キーの期限を5年、サブキーの期限を2年延ばし、バンドルを再エクスポートします。その後、利用者は次の 2 つを行います。

1. **GitHub に公開鍵を再登録**: Settings → SSH and GPG keys で旧鍵を削除し、`public.asc` の内容を再登録します(GitHubは期限情報を自動更新しません)。
2. **他端末に公開鍵を配布**: バンドルを転送して `mise run gpg:import` を実行します。期限延長は公開鍵の更新だけで反映されるので、秘密鍵を再転送する必要はありません。

> **Note:** 期限延長は秘密鍵の作り直しではありません。署名済みコミットの検証にも影響しません。

---

## 主キーのオフライン保管 / Offline Primary Key

サブキー運用の仕上げとして、日常端末から主キーの秘密鍵を取り除きます。

```bash
# 1. まず主キーを含む完全バックアップを安全な場所へ(USB等・暗号化推奨)
umask 077   # 秘密鍵ファイルを 600 で作る
gpg --export-secret-keys --armor "$(git config user.signingkey)" > /path/to/usb/master-full.asc

# 2. 検証: バックアップが本当にインポート可能か、一時キーリングで確認
tmp=$(mktemp -d)
GNUPGHOME=$tmp gpg --import /path/to/usb/master-full.asc
GNUPGHOME=$tmp gpgconf --kill gpg-agent && rm -rf "$tmp"   # 検証後、秘密鍵をディスクに残さない

# 3. 主キーの秘密鍵だけをこの端末から削除(grip指定)
grip=$(gpg --list-secret-keys --with-keygrip "$(git config user.signingkey)" | awk '/Keygrip/{print $3; exit}')
gpg-connect-agent "DELETE_KEY $grip" /bye

# 4. 確認: sec が sec# になっていればOK
gpg --list-secret-keys
```

主キーが必要になるのは「サブキーの追加・失効」「期限延長」「他人の鍵への署名」のときだけです。その際はUSBから一時的にインポートして作業し、再度削除します。

---

## トラブルシューティング / Troubleshooting

| 症状 | 対処 |
|------|------|
| 署名時に `No secret key` | `gpg --list-secret-keys` でサブキーに `ssb` があるか確認。無ければ `mise run gpg:import` |
| GitHub で `Unverified` 表示 | GitHub側の公開鍵が期限切れのまま。公開鍵を再登録する |
| pinentry が出ない | `~/.gnupg/gpg-agent.conf` を確認し `gpg-connect-agent reloadagent /bye` |
| `gpg: signing failed: No pinentry`(`gpg-unlock` でも出る) | 稼働中の agent が Nix 版 gnupg(`readlink /proc/$(gpg-connect-agent 'getinfo pid' /bye \| awk '/^D/{print $2}')/exe`)。`gpg-agent.conf` の `pinentry-program` が効いていない世代なら `mise run nix:switch` 後に `gpg-connect-agent reloadagent /bye`。それでも駄目なら手元で `gpgconf --kill gpg-agent` → `/usr/bin/gpg-agent --homedir ~/.gnupg --daemon` → `gpg-unlock`(#634) |
| trust が `unknown` になる | `gpg --import-ownertrust .backup/gpg/ownertrust.txt` |

---

## 参考 / References

- [Debian Wiki: Subkeys](https://wiki.debian.org/Subkeys)
- [GitHub Docs: Commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification)
