---
name: herdr-chat
description: |
  herdr を介して、ユーザー・Claude Code・Copilot CLI・copilot-quorum の四者が
  pane 越しに対話するためのプロトコル。相手 pane の見つけ方、宛先プレフィックス付き
  メッセージ形式、送信・応答待ちの手順、ループ防止の原則を定める。
  ユーザーが「Copilot と相談して」「quorum に合議させて」「他のエージェントに聞いて」
  「隣の pane と話して」などと言った時、または他エージェントからの宛先付きメッセージ
  (【from→to】形式)を pane 上で検知した時に使う。
  司令塔↔作業者プロトコル(herdr スキルの `agent send` / 上り報告)とは別物 — あちらは
  上下関係の報告経路、こちらは対等な対話。既存プロトコルは変更しない。
---

# herdr-chat — 四者会話プロトコル

herdr の pane を介して、ユーザー・Claude Code・Copilot CLI・copilot-quorum が
対等な立場で会話するためのプロトコル。前提として herdr スキルの基本操作
(`pane list` / `pane send-text` / `pane send-keys` / `wait output` など)を理解していること。

## 参加者モデル

| 参加者 | 実体 | 役割 |
|---|---|---|
| ユーザー | 任意の pane に直接入力 | 最優先。全エージェントはユーザー入力を最優先で扱う |
| Claude Code | pane (多くは `commander-*` または agent 名付き) | 対話 + herdr 操作のハブ |
| Copilot CLI | `herdr agent start` した pane | 対等な対話相手 |
| copilot-quorum | Agent REPL pane | 合議が欲しい論点を投げる「合議体」。単独モデルの応答ではなく Quorum→Peer Review→Synthesis の結論を返す |

## 1. 参加者の発見

会話を始める前に、必ず `herdr agent list` と `herdr pane list --workspace <ws>` で
相手 pane を特定する。**宛先を推測でメッセージを送らない** — pane id はセッションごとに
変わりうるため、送信直前に毎回確認する。

```bash
herdr agent list
herdr pane list --workspace <workspace_id>
```

- `agent` フィールドが `claude` のものは herdr がエージェント検知している。Copilot CLI /
  copilot-quorum は `agent: null` / `agent_status: unknown` になるため、`name` フィールド
  (`herdr agent start <name> ...` で付けた名前)で区別する。名前を付けずに起動された pane は
  `cwd` や直近の `agent read` の内容で人間側が判断してから送る
- **宛先誤送信の防止**: 送信直前に対象 pane を `herdr agent read <target>` で読み、
  想定した相手(Copilot のプロンプト、quorum の `solo>` 入力欄など)が実際にそこにいるか
  確認してから `send-text` する。特に同一 workspace 内に複数の作業用 pane がある場合、
  pane id の取り違えは容易に起こる
- 自分自身の workspace 外の pane(他ユーザー・他司令塔のもの)には触れない

## 2. メッセージ形式

宛先プレフィックスを本文の先頭に付ける:

```
【<from>→<to>】<本文>
```

`from` / `to` は次のいずれか: `claude` / `copilot` / `quorum` / `user`

例:
```
【claude→copilot】このコードのレビューをお願いします
【copilot→claude】レビューしました。src/foo.rs:42 が気になります
【claude→quorum】キャッシュ戦略をLRUにするかTTLにするか合議してください
【quorum→claude】Quorum結論: TTL推奨(理由は3点)
```

ユーザーが pane に直接入力する場合、プレフィックスは省略されうる。プレフィックスの
有無に関わらず、pane への直接入力は常にユーザー入力として最優先で扱う([5](#5-ユーザー最優先の原則)節)。

## 3. 送信: 2段構え

`pane send-text` は挿入のみで実行されない。必ず `send-keys <pane-id> Enter` を続ける:

```bash
herdr pane send-text <pane_id> "【claude→copilot】疎通確認です"
herdr pane send-keys <pane_id> Enter
```

## 4. 応答待ち: `wait output` + 応答マーカー

**自己エコーの罠**: 送信文に含まれる文字列で `wait output` すると、応答より先に
自分の入力行のエコーにマッチする。応答待ちは応答マーカー込みのパターンで行う
(相手ごとの応答マーカーは [6](#6-参加者ごとの起動方法と応答マーカー) の一覧表を参照)。

```bash
herdr wait output <pane_id> --match "● " --timeout 30000
herdr agent read <pane_id>
```

**複数ターンでのラベル使い回しの罠**(copilot-quorum で実測): `Agent:` のような
固定ラベルは会話が進むと画面内に複数回出現する。2ターン目以降に単純にラベルだけで
`--match` すると、直前ターンの古い応答に即マッチしてしまい、新しい応答を待たない。
2ターン目以降は、応答本文にのみ出現する一意なトークンを相手への質問文で指定させ
(例: 「回答には一意な合言葉を含めてください」)、そのトークン文字列自体でマッチする。
トークンを送信文(自分の入力エコー行)に含めないこと — 含めると自己エコーの罠に戻る。

## 5. ユーザー最優先の原則

ユーザーからの直接入力(プレフィックスの有無に関わらず、pane 上での直接入力)を検知したら、
進行中の他エージェントとの対話より優先してそれを処理する。他エージェントとの対話中に
ユーザー入力が割り込んだ場合、対話を打ち切ってユーザーの用件に応答してよい。

## 6. ループ防止の原則

四者会話は自動転送や無条件応答を許すと容易に無限ループする。以下を厳守する:

- **自分宛にのみ応答する**: pane 上のメッセージを読み、宛先プレフィックスが
  `→<自分>` になっているものにのみ応答する。宛先が他者宛のメッセージは読んでも
  反応しない(黙って無視する)
- **受信メッセージの自動転送を禁止する**: 受け取った内容をそのまま他の pane に
  右から左へ転送しない。他者に伝える必要がある場合は、自分の判断を通した要約・
  言い換えとして送る
- **応答は1メッセージにつき1回**: 同じ受信メッセージに対して複数回応答しない。
  応答済みかどうか、直前に自分がそのメッセージへ返信済みでないかを確認してから送る
- 上記を満たしていても会話が3往復以上続きそうな場合は、一度ユーザーに状況を報告し
  継続の是非を確認する(合議や長考が必要な論点は quorum に投げる判断も含めて)

## 7. 参加者ごとの起動方法と応答マーカー

| 参加者 | 起動コマンド | 応答マーカー | 終了方法 | 備考 |
|---|---|---|---|---|
| Claude Code | `herdr agent start <name> --workspace <ws> --split <right\|down> -- claude` | herdr の `agent_status`(`idle`/`working`)で検知可能。文字列で待つ場合はプロンプト行 `>` | pane 内で `/exit` または pane close | Claude 同士は `wait agent-status` が使える(herdr が正式にエージェント検知する) |
| Copilot CLI | `herdr agent start <name> --workspace <ws> --split down -- copilot` | `● `(行頭。応答本文の先頭に付く) | 入力欄に `/exit` + Enter | herdr はエージェント検知しない(`agent=null`/`agent_status=unknown`)。`wait output` のパターンマッチで代替する |
| copilot-quorum | `herdr agent start <name> --workspace <ws> --split down -- copilot-quorum --no-quorum` | `Agent:` ラベル行(初回のみ。2ターン目以降は [4](#4-応答待ち-wait-output--応答マーカー) のトークン方式を使う) | `send-keys <pane_id> C-c`(pane ごと片付く。実測確認済み) | 引数なし起動で Agent REPL。`--no-quorum` で合議レビューをスキップ(軽い疎通確認向け)。`/discuss` でアドホック合議、省略時 `--ensemble` で全問合議になる。応答完了は画面上部ステータスが `Planning`→`Ready` に変化し、`System: Agent completed` の直後に `Agent:` ラベルが出る |

### copilot-quorum プローブの実測ログ(2026-07-11, w2W:p3 で実施)

```
起動: herdr agent start quorum-probe --workspace w2W --split down -- copilot-quorum --no-quorum
送信: herdr pane send-text w2W:p3 "疎通確認です。「プローブOK-qz9」とだけ一言返してください。"
      herdr pane send-keys w2W:p3 Enter
1ターン目応答(5秒後): Agent: プローブOK-qz9  ← ラベル `Agent:` で初検出
2ターン目: 同じ「Agent:」でwait outputすると直前ターンの行に即マッチ(新規性なし) ← 罠を確認
終了: herdr pane send-keys w2W:p3 C-c → pane 自体が消滅(pane list から w2W:p3 が消える)
```

## 8. セットアップ

### Copilot CLI に herdr コマンドの実行を許可する

Copilot CLI のツール許可は `~/.copilot/permissions-config.json` の
`locations.<絶対パス>.tool_approvals` に永続化される。対話モードで `herdr ...` の
実行時に「常に許可」を選ぶと、そのロケーション(cwd の絶対パス)に対して自動的に
`{"kind": "commands", "commandIdentifiers": ["herdr"]}` が書き込まれる。

このファイルは **Nix では管理しない**。理由:

- キーが worktree ごとに異なる絶対パスであり、worktree を作るたびにエントリが増える
  動的な性質を持つ。home.nix のような宣言的シードと相性が悪い
- Copilot CLI 自身が対話操作で書き換える実行時状態ファイルであり、シードで固定内容を
  書くと CLI 側の管理と競合しうる

**運用手順**: 新しい worktree で Copilot CLI から herdr コマンドを初めて実行する際は、
対話プロンプトで一度「常に許可」を選ぶ(以後そのディレクトリでは自動承認される)。
非対話的に起動する場合は `copilot --allow-tool='shell(herdr:*)'` をセッション起動時に
明示する。無理に自動化しない。
