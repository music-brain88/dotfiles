# herdr-ctx

Reads each herdr agent's context usage regardless of pane width, from a sidecar file the Claude Code statusline writes.

herdr-ctx は、herdr の各 agent の context 使用率を、pane の幅に依存せず読む CLI である。`/wt` の司令塔は worker に「context 50% で引き継ぎ」を課しているが、これまでは pane 下部の `💭 n%` を目視で読むしかなく、pane が狭いと値が `…` で切れた。herdr-ctx はこの値をファイル経由で読めるようにする(Issue #784 のゴール 3)。herdr 本体には手を入れない外付けの道具である。

## 何を読んで何を書くか

herdr-ctx は、Claude Code の statusline が書く sidecar と `herdr agent list` の出力を、pane id で結合する。sidecar は、statusline の入力に含まれる使用率を pane ごとに書き出した JSON ファイルである。次の表は、関係するファイルとコマンドを、書き手と読み手ごとに示す。

| 対象 | 書き手 | 読み手 |
|---|---|---|
| `~/.herdr/ctx/panes/<pane id>.json`(sidecar) | `.config/claude/statusline-command.sh` | `herdr-ctx list`、`self`、`watch` |
| `herdr agent list`、`herdr agent get` | herdr | `herdr-ctx list`、`self`、`watch` |
| `~/.herdr/ctx/agents.json` | `herdr-ctx watch` | 司令塔などの利用者 |
| `~/.herdr/ctx/notify_state.json` | `herdr-ctx watch` | `herdr-ctx watch` |

statusline のスクリプトは Claude Code の子プロセスなので、herdr が pane に設定した環境変数 `HERDR_PANE_ID` を継承している。この変数が結合のキーになる。herdr-ctx は transcript の JSONL を読まない。

## サブコマンド

3 つのサブコマンドは、読む人と呼ばれる場面がそれぞれ違う。

### list

`herdr-ctx list` は、全 agent の使用率を 1 行 1 agent の JSON(JSON Lines)で出す。司令塔はこの 1 回の実行で worker 全員の残量を読める。`--table` を付けると、人が読む表(名前・状態・pct・最終更新)を出す。

```json
{"name":"commander-dotfiles","pane_id":"w3C:p1W","agent_status":"working","cwd":"/home/archie/dotfiles","pct":62,"ctx_tokens":620000,"context_window_size":1000000,"model":"Fable 5.1","last_turn_at":"2026-11-05T12:34:56Z","stale":false,"note":null}
```

次の表は、値が欠けるときの出力を示す。どの場合も agent は一覧から落とさない。

| 状況 | 出力 |
|---|---|
| sidecar が無い | `pct` が null で、`note` が `"no sidecar"` になる |
| sidecar を読めない | `pct` が null で、`note` が `"unreadable sidecar"` になる |
| `used_percentage` が null である(最初の API 呼び出しの前と `/compact` の直後) | `pct` が null で、`note` も null になる |
| `updated_at` が 10 分より古い | `stale` が true になり、値はそのまま出る |

statusline はイベントでしか走らないので、待機中の agent も 10 分で `stale` になる。`stale` は値が古い可能性を示す印であり、値の誤りを意味しない。

### self

`herdr-ctx self` は、自分の pane の使用率を 1 行で出す。Claude Code の UserPromptSubmit の hook がこのコマンドを呼び、stdout の内容が Claude の文脈に足される。

```text
context 62% (pane w3C:p1W, model Fable 5.1, as of 21:34)
```

`as of` の時刻は、実行した機械の地方時である。使用率が上限を超えると、`herdr agent get` で読んだ agent の名前に応じて、2 行目に次の表の助言を足す。

| agent の名前 | 上限 | 2 行目の内容 |
|---|---|---|
| `commander-` で始まる | 60% | 次の worker の報告の節目で `/wtclose` を呼び、新しいセッションに交代する |
| それ以外 | 50% | 差し戻しのラウンドを受ける前に、司令塔へ引き継ぎの準備を相談する |

`$HERDR_PANE_ID` か sidecar が無いときと使用率が null のときは、何も出さず終了コード 0 で終わる。sidecar を読めないときも同じである。使用率が 50% 未満のときは、hook の実行を軽くするために `herdr` を呼ばない。

### watch

`herdr-ctx watch` は、常駐して 30 秒おきに `list` と同じ計算をする。結果を `~/.herdr/ctx/agents.json` に書き、50 / 60 / 80 % の閾値を下から上に跨いだ agent ごとに、`herdr notification show` で 1 回だけ知らせる。周期は `--interval <秒>` で、閾値は `--thresholds <カンマ区切り>` で変えられる。

通知の判定は次の規則に従う。

- 一度に複数の閾値を跨いだときは、通知を 1 回だけ出す。
- 起動して最初に見た値が閾値を超えていたときも、1 回知らせる。
- pct が下がると、記録を今の pct 以下の閾値まで下げる。このとき通知は出さない。同じ閾値をもう一度上に跨ぐと、再び知らせる。
- agent が一覧から消えると、その agent の記録を消す。
- pct が null の周期は記録を変えない。`/compact` の直後の null で同じ閾値を知らせ直さないためである。
- 通知に失敗したときは、知らせた記録を残さず、次の周期でもう一度試す。

herdr のソケットに繋がらないときは、stderr に 1 行書いて次の周期まで待つ。このとき `agents.json` は更新しない。SIGTERM を受けると、`watch` はそのまま終了する。

## ファイルの形

statusline と `watch` は、どちらも同じディレクトリの一時ファイルに書いてから置き換える。読む側が書きかけのファイルを見ることはない。

sidecar のファイル名は、pane id の `:` を `_` に置き換えたものである(例: `w3C_p1W.json`)。次の例は sidecar の中身を示す。

```json
{"pane_id":"w3C:p1W","session_id":"…","transcript_path":"…","cwd":"/home/archie/dotfiles","model_id":"claude-fable-5-1","model_name":"Fable 5.1","used_percentage":62,"context_window_size":1000000,"total_input_tokens":620000,"updated_at":"2026-11-05T12:34:56Z"}
```

`used_percentage` は statusline の入力の `context_window.used_percentage` をそのまま写した値である。入力に無いときは、statusline が `current_usage` から計算した値を書く。`total_input_tokens` は `current_usage` の 3 つのトークン数の合計である。

`agents.json` は、`generated_at` と、`list` の 1 行と同じ形の要素を持つ配列 `agents` からなる。`notify_state.json` は、pane id をキーに、今いる閾値を値に持つオブジェクトである。`watch` を再起動しても同じ通知を繰り返さないように、この状態をファイルに残す。

## 常駐の起動のしかた

`nix/modules/herdr.nix` が、`herdr-ctx watch` を systemd の user service `herdr-ctx-watch` として定義する。`systemd.user.startServices` の既定値は `true` なので、`mise run nix:switch` を実行すると service が起動する。手で打つコマンドは要らない。

WSL 機で systemd の user session が動いていないときは、home-manager が service の起動を飛ばす。その機械では `watch` は常駐しない。`list` と `self` は sidecar を直接読むので、常駐が無くても動く。

## 確かめ方

`mise run nix:switch` の後に、次の 3 つを確かめる。

1. `herdr-ctx list --table` の pct が、各 pane の statusline の `💭` の値と一致する。一致を見るには、対象の agent が switch の後に 1 ターン以上動いて、sidecar が書かれている必要がある。
2. `systemctl --user status herdr-ctx-watch` が `active (running)` を示す。
3. 新しい Claude Code のセッションの最初のターンで、文脈に `context n%` の行が入る。

## 開発

```sh
cd tools/herdr-ctx
cargo test                       # 単体テスト + tests/cli.rs(偽の herdr で終了コードと出力を確かめる)
cargo run -- list --table
nix build .#herdr-ctx            # dotfiles のルートで実行する
bash .config/claude/scripts/tests/statusline_sidecar_test.sh   # dotfiles のルートで実行する。sidecar の中身を確かめる
```

rustfmt の設定 `rustfmt.toml` は、リポジトリの規約に合わせてインデントを 2 スペースにしている。

## やらないこと

次の 3 つは、v1 の範囲に入れていない。

- `herdr pane rename` で pane のラベルに `[62%]` を付ける。agent の名前は `herdr agent prompt` の宛先なので触らない。
- transcript の JSONL を読む。形式が Claude Code の内部形式で、context window の大きさも分からないので、フォールバックとしても作らない。
- 常駐の HTTP サーバーを立てる。`watch` が書くファイルを読むだけで、司令塔も hook も足りる。
