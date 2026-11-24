# Send Mail Across Machines / 別の機械の司令塔に連絡する

> **Diátaxis:** 🔧 How-to

この手順書は、司令塔(`/wt` の調整役のエージェント)が別の機械で動く司令塔に連絡を送る手順と、受け取った司令塔が連絡を読んで印を付ける手順を書いたものです。連絡の本文は vault の作業記憶に md で置き、「本文が届いた」という知らせ(以下、呼び鈴)を `atuin kv` で運びます。呼び鈴を扱うスクリプトは `~/.claude/scripts/claude_mail.sh` です(#826)。

この手順書では、連絡を送る機械を「機械 A」、受け取る機械を「機械 B」と呼びます。

---

## 前提 / Prerequisites

次の 3 つが、両方の機械でそろっている必要があります。

- 同じアカウントと同じ鍵で atuin に login している。login の手順は [sync-atuin-history-across-machines.md](./sync-atuin-history-across-machines.md) にあります。
- vault が Obsidian Sync で同期されている。
- この dotfiles を `mise run nix:switch` で反映している。

---

## 宛先の決まり / Addresses

宛先は `commander-<project>` の形で書きます。`<project>` は、宛先の司令塔が動く場所で次のコマンドが出す名前です。

```bash
bash ~/.claude/skills/wtclose/close_gate.sh --where project
```

> **⚠️ 宛先は herdr の名前ではなく、`commander-<--where project>` です。** 司令塔が herdr で `commander-dotfiles-2` のようなサフィックス付きの名前を名乗っていても、その司令塔が読むのは `commander-dotfiles` あての呼び鈴です。herdr の名前はリポジトリのディレクトリ名から作るので、`--where project` が出す名前とは大文字小文字が違うこともあります。

`send` は、vault に `AgentMemory/<project>` のフォルダが無い宛先を拒否します。書き間違えた宛先やサフィックス付きの宛先に置いた呼び鈴は、誰にも読まれないためです。

差出人も同じ形で、`send` を実行した場所の `commander-<project>` になります。

---

## 連絡を送る(機械 A) / Send

1. 司令塔は、連絡の本文を vault の作業記憶 `AgentMemory/workbench/<project>/` に md で書きます。ファイル名は `<YYYYMMDD>-handoff-<題>.md` とし、frontmatter の `kind` は `handoff` にします。

2. 司令塔は `send` を実行します。引数は、宛先・文書のパス・1 行の用件の 3 つです。

   ```bash
   bash ~/.claude/scripts/claude_mail.sh send commander-dotfiles \
     ~/Documents/Obsidian/AgentMemory/workbench/dotfiles/20261124-handoff-example.md \
     '記憶を 1 件直した。読んで確かめてほしい'
   ```

3. `send` が `sent commander-dotfiles <キー>` を出して終了コード 0 で終われば、呼び鈴は同期のサーバーまで届いています。

`send` が受け付ける文書は、vault の `AgentMemory/workbench/` の中に実在する md だけです。用件は 600 バイト(日本語で約 200 字)までの 1 行です。`send` は、改行・タブなどの制御文字を含む用件を拒否します。用件は呼び鈴の値に入り、本文は値に入りません。

---

## 連絡を読む(機械 B) / Read

機械 B の司令塔は、次の 2 つの時点で、自分あての呼び鈴を自動で見ます。

| 時点 | 仕組み | 見え方 |
|---|---|---|
| セッションの開始 | `settings.json` の SessionStart の hook が、`startup`・`resume`・`clear` のときに `claude_mail.sh list` を呼ぶ | 呼び鈴があれば、Claude の会話の文脈に入る。無ければ何も出ない |
| `/wtclose` の検問 | `close_gate.sh` が `claude_mail.sh list --to commander-<project>` を呼ぶ | 「記録した注意」に出る。締めは止めない |

司令塔は、`list` を手で実行して読むこともできます。`--to` を省くと、今いる場所の `commander-<project>` あての呼び鈴を読みます。

```bash
bash ~/.claude/scripts/claude_mail.sh list
bash ~/.claude/scripts/claude_mail.sh list --to commander-dotfiles
```

`list` は、先に `atuin sync` を実行してから、呼び鈴を 1 件 1 行で古い順に出します。キーの先頭の時刻は UTC で、`時刻=` は差出人の機械の時刻です。

```text
呼び鈴 20261124-000015-commander-example-1a2b3c4d 宛先=commander-dotfiles 差出人=commander-example 時刻=2026-11-24T09:00:15+0900 文書=/home/user/Documents/Obsidian/AgentMemory/workbench/dotfiles/20261124-handoff-example.md 用件=記憶を 1 件直した。読んで確かめてほしい | 読んで対応したら: bash ~/.claude/scripts/claude_mail.sh ack commander-dotfiles 20261124-000015-commander-example-1a2b3c4d
```

呼び鈴は、本文より先に届くことがあります。そのとき `list` は「本文がまだ届いていない」と出し、呼び鈴を残します。司令塔は、Obsidian Sync が本文を運ぶのを待ってから、もう一度 `list` を実行します。

> **📝 worktree のセッションには出ません:** `--to` を省いた `list` は、linked worktree の中では何も出しません。`/wt` の作業者のセッションに、司令塔あての呼び鈴を見せないためです。vault が無い機械と、git リポジトリの外でも、何も出しません。

---

## 読み終えた印を付ける(機械 B) / Acknowledge

司令塔は、文書を読んで対応した後に、`list` の行末に出ている `ack` のコマンドを実行します。

```bash
bash ~/.claude/scripts/claude_mail.sh ack commander-dotfiles 20261124-000015-commander-example-1a2b3c4d
```

`ack` は、呼び鈴を 1 件消して同期します。連絡の本文は vault に残ります。

---

## うまくいかないとき / Troubleshooting

`list` は、問題があっても理由を 1 行で出して終了コード 0 で終わり、セッションの開始と検問を止めません。`send` と `ack` は、失敗を 0 以外の終了コードで返します。次の表は、理由の行と、そのときにすることを並べたものです。

| 理由の行 | すること |
|---|---|
| `atuin が無い` | 利用者が `mise run nix:switch` を実行する |
| `atuin sync が失敗した` | 利用者が `atuin status` で login とネットワークを確かめる |
| `atuin sync が時間切れになった` | 司令塔が `atuin sync` を手で 1 回実行してから、`list` をもう一度実行する。上げる履歴が多いと、同期に時間がかかる |
| `atuin sync が「Sync complete!」を出さずに終わった` | 利用者が `atuin sync` を手で実行し、出力を読む。未ログインか、atuin の出力の変更が考えられる |
| `宛先を拒否した` | 司令塔が「宛先の決まり」の節のコマンドで、宛先の名前を確かめる |
| `呼び鈴はこの機械に置いた`(終了コード 4) | 送り直さない。次の `atuin sync` で届く。送り直すと、同じ連絡が 2 通になる |
| `文書が作業記憶の外を指している。読まない` | 司令塔はその文書を開かず、`ack` もしない。利用者に報告し、受け取る機械の作業記憶に置かれたリンクを確かめてもらう。呼び鈴は残る |
| `値の形が合わない` | 司令塔が差出人に確かめる。要らない呼び鈴なら `ack` で消す |

時間の上限は、次の環境変数(秒)で変えられます。

| 環境変数 | 対象 | `list` の既定 | `send` と `ack` の既定 |
|---|---|---|---|
| `CLAUDE_MAIL_SYNC_TIMEOUT` | `atuin sync` 1 回 | 10 | 30 |
| `CLAUDE_MAIL_KV_TIMEOUT` | `atuin kv` 1 回 | 2 | 5 |
| `CLAUDE_MAIL_TOTAL_TIMEOUT` | スクリプト全体 | 15 | 45 |

終了コードと出力の契約は、`claude_mail.sh` の先頭のコメントにあります。

---

## 補足 / Notes

- 呼び鈴は、司令塔が動いている最中には自動で届きません。司令塔は、`list` を手で実行すれば途中でも読めます。
- 呼び鈴を消した記録(誰がいつ読んだか)は残りません。
- 連絡の本文は、ほかの作業物と同じ扱いになります。状態ファイル・記憶・セッションノートのどこからも辿れなくなって 14 日を過ぎると、`/wtclose` の検問が「忘れる候補」として一覧に出します。
- スクリプトのテストは `mise run claude:mail-test` で走ります。テストは偽の `atuin` だけを使い、実物の同期データには触りません。

---

## 🔗 Related Documentation

- [sync-atuin-history-across-machines.md](./sync-atuin-history-across-machines.md) — atuin の register と login
- [mise-tasks.md](../reference/mise-tasks.md) — `claude:mail-test` を含む mise タスクの一覧
