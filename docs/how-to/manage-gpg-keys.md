# Manage GPG Keys / GPG鍵の複数端末運用

> **Diátaxis:** 🔧 How-to

コミット署名用GPG鍵を複数端末で運用するための手順です。新端末セットアップ、SSH 認証の一元化、有効期限の延長、主キーのオフライン保管をカバーします。タスクコマンドの一覧は [mise-tasks.md](../reference/mise-tasks.md) を参照してください。

---

## 鍵構成の考え方 / Key Layout

この運用は「主キー + サブキー」構成を前提としています。次の図は、主キーと 3 つのサブキーの構成と、それぞれの役割を示します。

```
sec  ed25519 [SC]  ← 主キー: 証明(Certify)専用。サブキーの発行・失効に使う
ssb  cv25519 [E]   ← 暗号化サブキー: 日常の暗号化
ssb  ed25519 [S]   ← 署名サブキー: コミット署名の実体
ssb  ed25519 [A]   ← 認証サブキー: SSH 認証(GitHub 等)の実体
```

- **利用者が各端末に配るのは、サブキーの秘密鍵だけです**。主キーの秘密鍵は信頼できる1箇所(オフラインのUSB等)に保管します。
- 端末が漏洩しても、サブキーだけを失効(revoke)すれば、主キーと鍵のアイデンティティは守られます。
- git の `user.signingkey` には主キーIDを指定すれば足ります。GPGが自動的に有効な署名サブキーを選んで署名します。
- SSH 認証も同じ鍵束で管理し、端末ごとに別の SSH 鍵は持ちません。1 台の端末が漏洩したら全端末の [A] サブキーをローテーションする運用を受け入れています。端末ごとに [A] サブキーを分ける案は、必要になったときに追加できます。

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

タスクは最後に `gpg --show-keys` で `public.asc` の中身を表示するので、`sub` の行に [E] [S] [A] がそろっていることを確かめます。

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

## SSH 認証の一元化 / SSH Authentication via gpg-agent

SSH 認証には、素の `ssh-agent` と端末ごとの SSH 鍵ではなく、gpg-agent と [A] サブキーを使います。gpg-agent の SSH ソケットは `gpgconf --list-dirs agent-ssh-socket` で得られ、config.fish がこの値を `SSH_AUTH_SOCK` に設定します。利用者は、[A] サブキーを次の手順で作成し、登録し、配布します。

### 1. [A] サブキーを作成

利用者は、**主キーの秘密鍵がある端末で**次のコマンドを実行します。

```bash
gpg --quick-add-key <主キーの fingerprint> ed25519 auth <既存サブキーと同じ期限 YYYY-MM-DD>
```

期限を既存サブキーと揃えておくと、`mise run gpg:extend` で全サブキーを一括で延長できます。

### 2. SSH に出す鍵として印を付ける

利用者は、[A] サブキーの keygrip を確かめてから、その鍵に `Use-for-ssh` 属性を付けます。

```bash
# [A] 行の直後の「Keygrip =」の値を控える
gpg --list-secret-keys --with-keygrip

gpg-connect-agent 'KEYATTR <[A] サブキーの keygrip> Use-for-ssh: yes' /bye
```

GnuPG 2.4 では `~/.gnupg/sshcontrol` は非推奨で、鍵ファイルの `Use-for-ssh` 属性が正です(`man gpg-agent` に明記されています)。

### 3. agent が鍵を出していることを確認

次のコマンドで、gpg-agent が [A] サブキーを SSH 鍵として出していることを確認します。

```bash
SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket) ssh-add -L
gpg --export-ssh-key <主キーの fingerprint>
```

`ssh-add -L` に鍵が出ていて、その鍵が `gpg --export-ssh-key` の出力と同じであれば正常です。

### 4. GitHub に SSH 鍵として登録

利用者は、次のコマンドで公開鍵を GitHub に登録します。

```bash
gpg --export-ssh-key <主キーの fingerprint> | gh ssh-key add --title "gpg-auth <[A] サブキーの ID>"
```

gh の token には `admin:public_key` スコープが必要です。スコープが無い場合は、先に `gh auth refresh -h github.com -s admin:public_key` を実行します。

### 5. 他端末へ配布

`mise run gpg:export` は `--export-secret-subkeys` を使うので、[A] サブキーも自動でバンドルに入ります。ただし `Use-for-ssh` 属性は agent 側の鍵ファイルの属性で、OpenPGP のバンドルには含まれません。そのため利用者は、各端末で `mise run gpg:import` を実行した後に、手順 2 の `KEYATTR` をやり直します。

### 6. pinentry の出方

SSH の署名要求には tty の情報が無いので、gpg-agent は「最後に `updatestartuptty` された tty」に pinentry を出します。config.fish の `fish_preexec` ハンドラがコマンドのたびにこの tty を更新するので、pinentry は通常、コマンドを打った pane に出ます。pinentry は `pinentry-tty` なので、どの大きさの pane でも 1 行のプロンプトとして出ます。入力したパスフレーズは `default-cache-ttl-ssh`(8 時間)の間キャッシュされます。

---

## 有効期限の延長 / Extending Expiry

期限切れが近づいたら(`mise run gpg:status` が警告したら)、利用者は**主キーの秘密鍵がある端末で**次のコマンドを実行します。

```bash
mise run gpg:extend
```

このタスクは主キーの期限を5年、サブキーの期限を2年延ばし、バンドルを再エクスポートします。その後、利用者は次の 2 つを行います。

1. **GitHub に公開鍵を再登録**: Settings → SSH and GPG keys で旧鍵を削除し、`public.asc` の内容を再登録します(GitHubは期限情報を自動更新しません)。SSH 鍵として登録した公開鍵は期限の情報を持たないので、SSH 鍵の再登録は不要です。
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
| `git@github.com: Permission denied (publickey)` で、`ssh -v` の `Offering public key` に agent の鍵が無い | `SSH_AUTH_SOCK` が空か、別の agent を指しています。`echo $SSH_AUTH_SOCK` の値が `gpgconf --list-dirs agent-ssh-socket` の値と一致するか確認する。値が `/run/user/<uid>/wezterm/agent.<pid>` なら WezTerm 内蔵の ssh-agent proxy を指していて、wezterm.lua の `mux_enable_ssh_agent = false` が効く前の WezTerm が動いています。`mise run nix:switch` のあとにログインし直す |
| `sign_and_send_pubkey: signing failed ... agent refused operation` | `journalctl --user -u gpg-agent.service -n 5` を読む。`Screen or window too small` なら、pinentry が curses のまま(#440 より前の設定)なので、`mise run nix:switch` 後に `gpg-connect-agent reloadagent /bye` を実行する。`Timeout` なら、pinentry が別の pane に出て 60 秒放置されているので、今の pane で `gpg-connect-agent updatestartuptty /bye` を実行してから再試行する |
| 他端末で `ssh-add -L` に [A] サブキーが出ない | `Use-for-ssh` 属性が付いていません。[SSH 認証の一元化](#ssh-認証の一元化--ssh-authentication-via-gpg-agent) の手順 2 で付け直す |
| `gpg --show-keys .backup/gpg/public.asc` に [E] や [A] のサブキーが出ない | #770 より前の `gpg:export` は `signingkey` の `!` 付き指定をそのまま使っていたので、[S] だけのバンドルになっていました。`mise run gpg:export` を実行し直し、最後に表示される `gpg --show-keys` の出力に全サブキーが出ることを確かめます。Bitwarden の添付も `mise run gpg:bw:push` で差し替えます |

---

## 参考 / References

- [Debian Wiki: Subkeys](https://wiki.debian.org/Subkeys)
- [GitHub Docs: Commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification)
