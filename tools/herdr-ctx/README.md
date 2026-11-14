# herdr-ctx

Gathers the machine-readable values of the `/wt` board: each herdr agent's context usage regardless of pane width, and the decision maker's open review requests on GitHub.

herdr-ctx は、`/wt` の司令塔と決定者が同じ盤面を見るために、機械が取れる値を集める計器である。集める値は次の 2 つである。

- herdr の各 agent の context 使用率。司令塔は worker に「context 50% で引き継ぎ」を課しているが、これまでは pane 下部の `💭 n%` を目視で読むしかなく、pane が狭いと値が `…` で切れた。herdr-ctx はこの値をファイル経由で読めるようにする(Issue #784 のゴール 3)。
- 決定者に割り当てられた open のレビュー依頼。herdr-ctx が GitHub から集めて `~/.herdr/ctx/reviews.json` に書き、盤面を映す窓はこのファイルを読むだけにする(Issue #805)。値を集める係を herdr-ctx の 1 か所にまとめるためである。

herdr-ctx は、herdr 本体には手を入れない外付けの道具である。名前の `ctx` は最初の役目である context の計器に由来する。

## 何を読んで何を書くか

herdr-ctx は、Claude Code の statusline が書く sidecar と `herdr agent list` の出力を、pane id で結合する。sidecar は、statusline の入力に含まれる使用率を pane ごとに書き出した JSON ファイルである。レビュー依頼は、`gh api` で GitHub の検索 API から取る。次の表は、関係するファイルとコマンドを、書き手と読み手ごとに示す。

| 対象 | 書き手 | 読み手 |
|---|---|---|
| `~/.herdr/ctx/panes/<pane id>.json`(sidecar) | `.config/claude/statusline-command.sh` | `herdr-ctx list`、`self`、`watch` |
| `herdr agent list`、`herdr agent get` | herdr | `herdr-ctx list`、`self`、`watch` |
| `~/.herdr/ctx/agents.json` | `herdr-ctx watch` | 司令塔などの利用者 |
| `~/.herdr/ctx/notify_state.json` | `herdr-ctx watch` | `herdr-ctx watch` |
| `gh api search/issues`(GitHub の検索 API) | GitHub | `herdr-ctx reviews`、`watch` |
| `~/.herdr/ctx/reviews.json` | `herdr-ctx watch` | 盤面を映す窓(Herdr アプリの mod の試作。このリポジトリの外にある)、司令塔 |

statusline のスクリプトは Claude Code の子プロセスなので、herdr が pane に設定した環境変数 `HERDR_PANE_ID` を継承している。この変数が結合のキーになる。herdr-ctx は transcript の JSONL を読まない。

## サブコマンド

4 つのサブコマンドは、読む人と呼ばれる場面がそれぞれ違う。

### list

`herdr-ctx list` は、全 agent の使用率を 1 行 1 agent の JSON(JSON Lines)で出す。司令塔はこの 1 回の実行で worker 全員の残量を読める。`--table` を付けると、人が読む表(名前・状態・pct・最終更新)を出す。

```json
{"name":"commander-dotfiles","pane_id":"w3C:p1W","agent_status":"working","cwd":"/home/archie/dotfiles","pct":62,"ctx_tokens":620000,"context_window_size":1000000,"model":"Fable 5.1","last_turn_at":"2026-11-05T12:34:56Z","stale":false,"note":null,"session_match":true}
```

次の表は、値が欠けるときの出力を示す。どの場合も agent は一覧から落とさない。

| 状況 | 出力 |
|---|---|
| sidecar が無い | `pct` が null で、`note` が `"no sidecar"` になる |
| sidecar を読めない | `pct` が null で、`note` が `"unreadable sidecar"` になる |
| sidecar が agent の session のものでない | `session_match` が false になり、値はそのまま出る。`--table` は PCT に `(session?)` を添える |
| agent が Claude Code ではない(`herdr agent list` の `agent` が `claude` 以外) | context の欄が null で、`note` が `"not a claude agent"` になる。前の Claude Code の sidecar が pane に残っていても結合しない |
| `used_percentage` が null である(最初の API 呼び出しの前と `/compact` の直後) | `pct` が null で、`note` も null になる |
| `updated_at` が 10 分より古い | `stale` が true になり、値はそのまま出る |

statusline はイベントでしか走らないので、待機中の agent も 10 分で `stale` になる。`stale` は値が古い可能性を示す印であり、値の誤りを意味しない。

`session_match` は、sidecar が agent の session のものかを示す。同じ pane で新しいセッションが最初の statusline の更新より前に始まると、前のセッションの sidecar が残っているからである。herdr-ctx は、sidecar の `session_id` と `herdr agent list` の `agent_session.value` を比べる。両方あって一致すれば true になる。違うときは、sidecar の `transcript_path` のファイル名(拡張子を除く)が `agent_session.value` と一致すれば true になり、それでも違えば false になる。どちらかが無ければ null になる。

裏の job に乗ったセッションでは、TUI 側と backend 側で id が違うことがある。そのため、値が正しくても false が付く可能性がある。司令塔が配備後に実機で確かめて、次の PR で判定を詰める。

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

`$HERDR_PANE_ID` か sidecar が無いときと使用率が null のときは、何も出さず終了コード 0 で終わる。sidecar を読めないときも同じである。使用率が 50% 未満のときは、hook の実行を軽くするために `herdr` を呼ばない。`herdr` に繋がらないときは、1 行目の使用率だけを出して助言を省き、理由を stderr に 1 行書く。hook の主な役目は 1 行目の使用率を届けることなので、このときも終了コードは 0 である。

hook から呼ばれたときは、stdin の JSON の `session_id` と `transcript_path` を sidecar の値と照らす。同じ pane で新しいセッションが最初の statusline の更新より前に prompt を送ると、前のセッションの sidecar が残っているからである。どちらかの鍵が両方にあって一致すれば、sidecar を使う。どちらも一致しないときは、何も出さず終了コード 0 で終わり、stderr に「sidecar は別の session のもの」と 1 行書く。`transcript_path` を第 2 の鍵にするのは、`/remote-control` などで裏の job に乗ったセッションでは、TUI 側と backend 側で session id が違うことがあるからである。stdin に照合できる JSON が無いときは、照合せずに出す。stdin が端末か空のときと、JSON でないときと、鍵が無いときがこれに当たる。手で `herdr-ctx self` を打ったときも同じである。

### reviews

`herdr-ctx reviews` は、決定者個人に割り当てられた open のレビュー依頼の一覧を、JSON で stdout に出す。検索の条件は `is:pr is:open user-review-requested:@me` である。herdr-ctx は `gh api` を子プロセスとして呼び、GitHub の検索 API(`search/issues`)に `sort=updated`、`order=desc`、`per_page=100` で 1 回だけ問い合わせる。認証は `gh` に任せるので、herdr-ctx はトークンを持たない。出力の形は「ファイルの形」の節の `reviews.json` と同じである。`reviews` はファイルを書かない。

`review_requests` は `updated_at` の新しい順に並ぶ。herdr-ctx は、検索 API が返した順を並べ替えずに保つ。

依頼が 100 件を超えるとき、herdr-ctx は先頭の 100 件だけを `review_requests` に入れ、続きのページを取りに行かない。`total_count` は検索に一致した全体の数なので、読む側は `total_count` と `review_requests` の件数の差から「ほか n 件」を出せる。この形を選んだのは、問い合わせが 1 回で済んで実装が単純になり、新しい順の先頭 100 件があれば盤面には足りるからである。

次の表は、失敗したときの stderr の例を示す。どの場合も、herdr-ctx は理由を stderr に 1 行書き、stdout には何も出さず、終了コード 1 で終わる。

| 状況 | stderr の例 |
|---|---|
| `gh` が無い | `herdr-ctx: gh を実行できない: No such file or directory (os error 2)` |
| `gh` が失敗した(認証が切れたときなど) | `herdr-ctx: gh: Bad credentials (HTTP 401)` |
| `gh` が期限内に応答しない | `herdr-ctx: gh が 15 秒以内に応答しない` |
| 応答が壊れた JSON である | `herdr-ctx: GitHub の JSON を読めない: …` |
| 検索が途中で打ち切られた(応答の `incomplete_results` が true) | `herdr-ctx: GitHub の検索が途中で打ち切られた(incomplete_results)` |
| `repository_url` から `owner/name` を取り出せない | `herdr-ctx: repository_url を読めない: …` |

herdr-ctx は、検索が途中で打ち切られた応答も失敗として扱う。打ち切られた一覧を書くと、まだある依頼が一覧から消えて見えるからである。

### watch

`herdr-ctx watch` は、常駐して 30 秒おきに `list` と同じ計算をする。結果を `~/.herdr/ctx/agents.json` に書き、50 / 60 / 80 % の閾値を下から上に跨いだ agent ごとに、`herdr notification show` で 1 回だけ知らせる。周期は `--interval <秒>` で、閾値は `--thresholds <カンマ区切り>` で変えられる。

通知の判定は次の規則に従う。

- 一度に複数の閾値を跨いだときは、通知を 1 回だけ出す。
- 起動して最初に見た値が閾値を超えていたときも、1 回知らせる。
- pct が下がると、記録を今の pct 以下の閾値まで下げる。このとき通知は出さない。同じ閾値をもう一度上に跨ぐと、再び知らせる。
- agent が一覧から消えると、その agent の記録を消す。
- 同じ pane で sidecar の `session_id` が変わると、前の session の記録を消してから判定する。前の session が 80% で知らせた pane で別の session が 62% から始まると、新しい session の閾値として 1 回知らせる。
- `session_match` が false の行は、通知を出さず、記録も変えない。別のセッションの値かもしれないからである。
- pct が null の周期は、同じ session の記録を変えない。`/compact` の直後の null で同じ閾値を知らせ直さないためである。
- 通知に失敗したときは、知らせた記録を残さず、次の周期でもう一度試す。herdr は通知を表示しなかったときも成功の応答を返すので、応答の `shown` が `true` でないときも失敗として扱う。
- `notify_state.json` の保存に失敗したときは、メモリ上の記録を保ったまま、次の周期で保存をもう一度試す。

herdr のソケットに繋がらないときは、stderr に 1 行書いて次の周期まで待つ。このとき `agents.json` は更新しない。SIGTERM を受けると、`watch` はそのまま終了する。

`watch` はスレッドを 2 本持つ。主スレッドは、ここまでに書いた agent の一覧と通知を受け持つ。もう 1 本のスレッドは、`reviews` と同じ取得を起動の直後に 1 回行い、以後は 5 分おきに行って、結果を `~/.herdr/ctx/reviews.json` に書く。この周期は `--reviews-interval <秒>` で変えられる。2 本のスレッドは状態を共有せず、書くファイルも別なので、`reviews.json` の更新は agent の一覧の周期と独立している。`gh` が遅くても失敗しても、agent の一覧と通知の 30 秒の周期は遅れない。GitHub の検索 API の上限は 1 分あたり 30 回なので、5 分おきの取得は上限に届かない。

レビュー依頼の取得は、次の規則に従う。

- 取得・解釈・書き込みのどこかで失敗した周期は、`reviews.json` を書き換えない。理由は `herdr-ctx: レビュー依頼を更新できない: <理由>` の 1 行で stderr に書く。空の一覧で上書きすると、読む側には「依頼が 0 件」に見えるからである。読む側は `generated_at` で古さを判断する。
- 依頼が 0 件の周期は成功なので、`review_requests` が空の `reviews.json` を書く。
- 失敗した周期の後も、スレッドは止まらずに次の周期でもう一度取得する。万一 panic しても、その周期だけを捨てて続ける。スレッドが黙って止まると、`reviews.json` が古いまま誰も気づけないからである。
- `gh` が無い機械では、`reviews.json` は作られない。GitHub に繋がらない機械では、`reviews.json` は前の中身のまま残る。どちらの機械でも、agent の一覧と通知は今までどおり動く。

子プロセスの呼び出しには期限がある。`herdr` の期限は、`list` と `self` が 3 秒で、`watch` が 10 秒である。`gh` の期限は、`reviews` と `watch` のどちらも 15 秒である。期限を過ぎると、herdr-ctx は子プロセスを止めて、失敗として扱う。`self` の期限を hook の 5 秒より短くしているのは、1 行目の使用率を出す時間を残すためである。環境変数 `HERDR_CTX_TIMEOUT_SECS` は、`herdr` と `gh` の両方の期限を上書きする。統合テストが期限を短くするために使う。

## ファイルの形

statusline と `watch` は、どちらも同じディレクトリの一時ファイルに書いてから置き換える。読む側が書きかけのファイルを見ることはない。

sidecar のファイル名は、pane id の `:` を `_` に置き換えたものである(例: `w3C_p1W.json`)。次の例は sidecar の中身を示す。

```json
{"pane_id":"w3C:p1W","session_id":"…","transcript_path":"…","cwd":"/home/archie/dotfiles","model_id":"claude-fable-5-1","model_name":"Fable 5.1","used_percentage":62,"context_window_size":1000000,"total_input_tokens":620000,"updated_at":"2026-11-05T12:34:56Z"}
```

`used_percentage` は statusline の入力の `context_window.used_percentage` をそのまま写した値である。入力に無いときは、statusline が `current_usage` から計算した値を書く。`total_input_tokens` は `current_usage` の 3 つのトークン数の合計である。

`agents.json` は、`generated_at` と、`list` の 1 行と同じ形の要素を持つ配列 `agents` からなる。`notify_state.json` は、pane id をキーに、今いる閾値(`threshold`)とその閾値を知らせた session(`session_id`)の組を値に持つオブジェクトである。`watch` を再起動しても同じ通知を繰り返さないように、この状態をファイルに残す。

`reviews.json` は、`herdr-ctx reviews` の出力と同じ形を持つ。盤面を映す窓がこのファイルを読むので、形を変えるときは窓の側も直す。次の例のリポジトリ名・題・作者は架空の値である。

```json
{
  "generated_at": "2026-11-14T02:13:38Z",
  "total_count": 152,
  "review_requests": [
    {
      "repo": "owner/name",
      "number": 123,
      "title": "Add the widget",
      "url": "https://github.com/owner/name/pull/123",
      "author": "login",
      "draft": false,
      "updated_at": "2026-11-13T09:00:00Z",
      "created_at": "2026-11-10T01:00:00Z"
    }
  ]
}
```

次の表は、各鍵の中身と出所を示す。

| 鍵 | 中身 |
|---|---|
| `generated_at` | 取得した時刻(UTC) |
| `total_count` | 検索に一致した全体の数。100 を超えても、`review_requests` は先頭の 100 件だけを持つ |
| `review_requests[].repo` | 検索 API の `repository_url` のうち、最初の `/repos/` より後ろ(`owner/name`) |
| `review_requests[].number` | PR の番号 |
| `review_requests[].title` | PR の題 |
| `review_requests[].url` | PR の画面の URL(検索 API の `html_url`) |
| `review_requests[].author` | PR を出した人の login(`user.login`)。応答に `user` が無いときは null |
| `review_requests[].draft` | draft の PR なら true。応答に `draft` が無いときは false |
| `review_requests[].updated_at`、`created_at` | 検索 API の時刻をそのまま写した値 |

`reviews.json` は、非公開のリポジトリの名前と PR の題を含みうる。そのため、このファイルを `~/.herdr/ctx/` の外に写さない。

## 常駐の起動のしかた

`nix/modules/herdr.nix` が、`herdr-ctx watch` を systemd の user service `herdr-ctx-watch` として定義する。`systemd.user.startServices` の既定値は `true` なので、`mise run nix:switch` を実行すると service が起動する。手で打つコマンドは要らない。

WSL 機で systemd の user session が動いていないときは、home-manager が service の起動を飛ばす。その機械では `watch` は常駐しない。`list` と `self` は sidecar を直接読むので、常駐が無くても動く。

## 確かめ方

`mise run nix:switch` の後に、次の 5 つを確かめる。

1. `herdr-ctx list --table` の pct が、各 pane の statusline の `💭` の値と一致する。一致を見るには、対象の agent が switch の後に 1 ターン以上動いて、sidecar が書かれている必要がある。
2. `systemctl --user status herdr-ctx-watch` が `active (running)` を示す。
3. 新しい Claude Code のセッションの 2 ターン目以降の prompt で、文脈に `context n%` の行が入る。最初のターンでは出ない。最初の API 応答の前は `used_percentage` が null で、`self` は何も出さないからである。
4. 裏の job に乗ったセッション(`/remote-control` など)でも、文脈に `context n%` の行が入り、`herdr-ctx list` の `session_match` が false にならない。statusline が TUI 側と backend 側のどちらの session id を受け取るかが未確認なので、司令塔が配備後に確かめる。false が付くと、`watch` はその agent を知らせない。
5. `~/.herdr/ctx/reviews.json` の `generated_at` が 5 分以内の時刻を示し、`journalctl --user -u herdr-ctx-watch` に「レビュー依頼を更新できない」の行が続いていない。この行が続くときは、service から `gh` の認証を読めていない可能性がある。

## 開発

```sh
cd tools/herdr-ctx
cargo test                       # 単体テスト + tests/cli.rs(偽の herdr と偽の gh で終了コードと出力を確かめる)
cargo run -- list --table
nix build .#herdr-ctx            # dotfiles のルートで実行する
bash .config/claude/scripts/tests/statusline_sidecar_test.sh   # dotfiles のルートで実行する。sidecar の中身を確かめる
```

rustfmt の設定 `rustfmt.toml` は、リポジトリの規約に合わせてインデントを 2 スペースにしている。

## やらないこと

次の 5 つは、今の範囲に入れていない。

- `herdr pane rename` で pane のラベルに `[62%]` を付ける。agent の名前は `herdr agent prompt` の宛先なので触らない。
- transcript の JSONL を読む。形式が Claude Code の内部形式で、context window の大きさも分からないので、フォールバックとしても作らない。
- 常駐の HTTP サーバーを立てる。`watch` が書くファイルを読むだけで、司令塔も hook も足りる。
- レビュー依頼の 101 件目より先を、ページを辿って取る。理由は「reviews」の節に書いた。
- 自分が出した PR について、マージできるか、未解決の review thread の数、CI の結果を集める。これは別の Issue で扱う。
