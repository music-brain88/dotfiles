# Sync Atuin History Across Machines / atuin の履歴を複数端末で同期する

> **Diátaxis:** 🔧 How-to

native 機と WSL 機の atuin の履歴を、公式のホスト先 `api.atuin.sh` で 1 本に同期するための手順です。1 台目で register して暗号化鍵を控え、2 台目を同じ鍵で login します。同期先を自前サーバーへ移すとき(#719)も、同じ手順で 2 台目以降を login します。

---

## 前提 / Prerequisites

atuin の同期は end-to-end 暗号化です。履歴はローカルで暗号化されてからサーバーに送られるので、サーバーは中身を読めません。暗号化鍵は各端末の `~/.local/share/atuin/key` にだけあります。

2 台目が 1 台目の記録を復号するには、2 台目に 1 台目と同じ鍵を持たせる必要があります。鍵が違うと、同期は成功したように見えても、互いの記録は復号できずに読めません。

`nix/modules/dev-tools.nix` の `programs.atuin.settings` は、すでに `auto_sync = true`、`sync_address = "https://api.atuin.sh"`、`sync_frequency = "5m"` を設定しています。server に login していない間は、同期が黙って何もしません。

> **⚠️ 利用者は register と login を自分のターミナルで打ちます:** Claude Code の Bash 経由で打つと、エージェントフック(`atuin hook claude-code`)がその行を記録する経路を通ります。この経路で `history_filter` が効くかは確かめていません。

---

## 鍵の置き場の規約 / Where the Key Lives

- `atuin key` が表示する BIP39 の単語列は、利用者がパスワードマネージャに保存します。
- 単語列を Obsidian の vault にもこのリポジトリにも書きません。どちらも複数の端末や AI エージェントから読める場所なので、鍵が履歴の送信先とは別の経路に漏れるのを避けるためです。
- 鍵を失うと、サーバー上の記録は誰にも復号できません。パスワードマネージャへの保存が、鍵の唯一のバックアップです。

---

## パスワードの入力方法 / How to Enter the Password

`atuin register` と `atuin login` のパスワードは、`-p` で渡さずに対話の prompt へ入力します。`-p <password>` で渡すと、パスワードがシェルの履歴に残るからです。

`nix/modules/dev-tools.nix` の `history_filter` には `^atuin register` と `^atuin login` が入っていて、この 2 つで始まる行は atuin に記録されません。ただしこれは打ち間違えたときの保険です。`-p` を使わない運用を第一の防衛線にします。

---

## 1 台目(native 機)で register する / Register on the First Machine

1. 利用者は `atuin register` を打ちます。パスワードは prompt に入力します。

   ```bash
   atuin register -u <username> -e <email>
   ```

2. 利用者は `atuin sync` と `atuin status` で、サーバーへ件数が上がったことを確かめます。

   ```bash
   atuin sync
   atuin status
   ```

3. 利用者は `atuin key` を打ち、表示された BIP39 の単語列をパスワードマネージャに保存します。保存先の規約は「鍵の置き場の規約」のとおりです。

   ```bash
   atuin key
   ```

---

## 2 台目(WSL 機)で同じ鍵で login する / Log In on the Second Machine

### 1. 鍵が無いことを確かめる

2 台目で、利用者は `~/.local/share/atuin/key` が無いことを確かめます。

```bash
ls -l ~/.local/share/atuin/key   # No such file or directory が出れば正常
```

鍵が既にあった場合は、login の前に次の「2 台目に鍵が既にあった場合」を実行してください。

### 2. login する

利用者は `atuin login` を打ち、prompt にパスワードと、1 台目の鍵(パスワードマネージャに保存した BIP39 の単語列)を入力します。

```bash
atuin login -u <username>
```

> **⚠️ `mise run nix:switch` より先に login します:** この dotfiles の switch で fish のフックが入ると、2 台目で最初のコマンドが記録された瞬間に、`atuin` が別の鍵を自動で生成します。その鍵は 1 台目の鍵と違うので、2 台目の記録は 1 台目で復号できません。鍵を入れてから switch すれば、この事故は起きません。

### 3. switch して同期する

利用者は、dotfiles を更新して switch し、同期の結果を確かめます。

```bash
git pull
mise run nix:switch
exec fish
atuin sync
atuin status
```

### 4. 1 台目で 2 台目の記録を確かめる

1 台目で、利用者は 2 台目の hostname を含む記録を検索します。2 台目の記録が返れば、同期は成立しています。

```bash
atuin sync
atuin history list --format "{host} {command}" | grep <2 台目の hostname>
```

---

## 2 台目に鍵が既にあった場合 / When the Second Machine Already Has a Key

「鍵が無いことを確かめる」で鍵が見つかった場合、その鍵は 2 台目で単独に生成された別の鍵です。その鍵で暗号化された記録は、同期先では復号できません。

利用者は `key` と `records.db*` を日付つきで退避してから、login します。

```bash
cd ~/.local/share/atuin
mv key "key.$(date +%Y%m%d).bak"
for f in records.db*; do mv "$f" "$f.$(date +%Y%m%d).bak"; done
```

退避した分の履歴を捨ててよいかどうかは、その時点の件数を見て利用者が決めます。残したい履歴があれば、退避したファイルを消さずに残してください。

---

## 完了の確認 / Done Criteria

- 両機の `atuin status` が同じ件数を示す。
- 1 台目の検索に、2 台目の hostname の記録が出る。
- 鍵がパスワードマネージャに保存されている。

---

## 補足 / Notes

- 同期は、`atuin` の呼び出し(フックの記録・`Ctrl+r`)のたびに、前回から `sync_frequency`(5 分)以上たっていれば走ります。daemon は使いません。
- 2 台目がオフラインの間は、同期が失敗するだけで、記録は続きます。
- 同期先を自前サーバーへ移すとき(#719)は、`atuin logout` → `sync_address` の切替 → 同じ鍵で register し直し → `atuin sync` の順に進めます。ローカル DB の記録が新しいサーバーに再アップロードされ、2 台目以降はこの文書の login 手順をそのまま使います。

---

## 🔗 Related Documentation

- [daily-workflow-commands.md](./daily-workflow-commands.md) — 日常的によく使うコマンド集(`Ctrl+r` の履歴検索を含む)
- [keybindings.md](../reference/keybindings.md) — atuin の履歴検索のキーバインド
- [manage-gpg-keys.md](./manage-gpg-keys.md) — 鍵を複数端末で運用する別の例(GPG 鍵)
