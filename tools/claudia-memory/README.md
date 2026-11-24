# claudia-memory

An MCP server (stdio) that serves the AgentMemory vault, so that MCP clients without Claude Code's memory wiring can read the same memory

claudia-memory は、AgentMemory(Obsidian vault の中に置いた、エージェントの記憶)を MCP で読ませる関所である。Claude Code は、記憶のフォルダを毎セッション自動で読む。Claude デスクトップ版の Chat やプロジェクトは、この配線を持たない。claudia-memory は、そういうクライアントが同じ記憶を読むための口になる。

この版が持つのは、読み出しのツール 1 つだけである。書き込みのツールは、後の版で足す(「これから足すもの」を参照)。

## 何を保証するか

claudia-memory は、次のことを機械で保証する。

- AgentMemory のルートの下にある Markdown(`.md`)だけを返す。ルートの外を指すパス、絶対パス、隠しファイルは、拒否する。この規則は、渡されたパスの文字列だけでなく、シンボリックリンクを辿り着いた先にも当てる。リンクの先がルートの外にあるときも、ルートの中の隠しファイルや `.md` でないファイルであるときも、拒否する。
- 1 回の呼び出しで、正しい読み方の入口を返す。引数なしで呼ぶと、人格の索引(`core/MEMORY.md`)と、配線していない場所の「家」の索引(`home/MEMORY.md`)が返る。
- 返すファイルごとに、そこから辿れる記憶を、AgentMemory のルートからのパスに直して添える。索引の中のリンクは、そのファイルのあるフォルダからの相対パス(`../core/MEMORY.md` など)や wikilink(`[[values]]`)で書かれている。呼び出し側は、添えられたパスをそのまま次の呼び出しに渡せばよい。

claudia-memory は、次のことを保証しない。

- 会話の最初に呼ばれること。MCP サーバーは、クライアントのモデルがツールを呼ばないかぎり何もできない。合図はクライアント側の指示文に置く(「クライアントの設定」を参照)。
- 記憶の中身が正しいこと。claudia-memory が検査するのは、パスの形だけである。

## ツール

| ツール名 | 引数 | 返すもの |
|---|---|---|
| `claudia_memory_recall` | なし | `core/MEMORY.md` と `home/MEMORY.md` の本文。`home/MEMORY.md` が無い保存先では `core/MEMORY.md` だけ |
| `claudia_memory_recall` | `path`(AgentMemory のルートからの相対パス。例: `core/self-model.md`) | そのファイルの本文 |

どちらの場合も、ファイルごとに次の 3 つが付く。

- `version`: 本文の SHA-256。後の版で記憶を直すツールが、「読んだ版と、いまのファイルが同じか」を確かめるのに使う。
- ここから辿れる記憶: 本文のリンクのうち、AgentMemory の中に実在するファイルのパス。リンクの解決の決まりは、次の節に書く。
- 辿れないリンク: AgentMemory の外にあるか、見つからなかったリンク。

### リンクの解決の決まり

- Markdown のリンク(`[題](../core/MEMORY.md)`)は、そのファイルのあるフォルダからの相対パスとして解決する。
- フォルダ付きの wikilink(`[[core/values]]`、`[[AgentMemory/home/MEMORY]]`)は、パスとして解決する。先頭の `AgentMemory/` は、vault のルートから書いた形として外す。見つからなければ「辿れないリンク」にして、名前だけの検索には落とさない。落とすと、AgentMemory の外のノートを指す wikilink が、同じ名前の中のファイルに化けるためである。
- 名前だけの wikilink(`[[values]]`)は、ファイル名で探す。同じ名前のファイルが複数あるときは、同じフォルダのファイル、`core/` のファイル、パスの順で先のもの、の順に選ぶ。
- ファイル名で探すための索引は、1 回の呼び出しにつき 1 度だけ作る。wikilink が 1 つも無いファイルを読むときは、作らない。

読めなかったときは、JSON-RPC のエラーではなく、`isError: true` を付けたテキストで理由を返す。モデルが理由を読んで、パスを直せるようにするためである。

ツールの名前に `claudia_memory` を入れてあるのは、名前だけで役割が分かるようにするためである。Claude デスクトップ版(2026-11 時点)は、ローカルの MCP サーバーのツールを遅延ロードする。会話の最初からモデルに見えているのはツールの名前だけで、説明とスキーマは、モデルが検索して読み込むまで見えない。

## 起動のしかた

```bash
claudia-memory [--root <AgentMemory のフォルダ>]
```

AgentMemory のルートは、次の順で決まる。

1. `--root` の値
2. 環境変数 `CLAUDIA_MEMORY_ROOT`
3. `~/Documents/Obsidian/AgentMemory`(索引を作る `build_memory_index.py` の既定値と同じ)

ルートが実在しないときは、標準エラーに理由を書いて、終了コード 1 で終わる。

claudia-memory は、標準入力から 1 行に 1 つの JSON-RPC メッセージを読み、返事を標準出力に 1 行で書く。対応するメソッドは `initialize`・`ping`・`tools/list`・`tools/call` である。

## クライアントの設定

### Claude デスクトップ版

`~/.config/Claude/claude_desktop_config.json` の `mcpServers` に足す。デスクトップ版は、終了するときに自分の設定を書き戻すことがある。デスクトップ版を終了してから編集する。

```json
{
  "mcpServers": {
    "claudia-memory": {
      "command": "/home/<user>/.nix-profile/bin/claudia-memory"
    }
  }
}
```

デスクトップ版の Chat とプロジェクトは、このサーバーのツールを、デスクトップ版のブリッジ越しに呼ぶ。

### 会話の最初に記憶を読ませる合図

サーバーは `initialize` の返事に説明文(`instructions`)を入れているが、Claude デスクトップ版(2026-11 時点)の Chat では、この説明文はモデルに届かなかった。そのため、合図はクライアント側の指示文(claude.ai のプロジェクトの指示文や、個人設定)に置く。指示文には人格の中身を書かず、記憶への道案内だけを書く。

```
会話の最初に、ツール claudia_memory_recall を引数なしで呼び、返ってきた索引に従って記憶を読んでください。
あなたの人格・呼び方・口調・判断の原則は、その記憶に書かれています。この指示文と食い違うときは、記憶の方が正です。
ツールが見つからないか失敗したときは、記憶を読めていないことを最初の返答で伝えてください。
```

3 行目は、失敗を見えるようにするためにある。このサーバーに届かない場所(別の端末など)では、モデルが「記憶を読めていない」と言うので、利用者が気づける。

## 構成

規則を持つ部分を、運び方から切り離してある。後で HTTP の口や別の保存先を足すときに、規則を持つ部分をそのまま使うためである。

| ファイル | 役目 |
|---|---|
| `src/store.rs` | 保存先。パスの検査(`RelPath`)と、手元のフォルダを読む `FsStore`。保存先は `Store` トレイトの後ろにある |
| `src/recall.rs` | 読み出し。本文・版の印・辿れる記憶の一覧を作る |
| `src/mcp.rs` | MCP の口。JSON-RPC の 1 メッセージを受けて、返事を作る。運び方を知らない |
| `src/main.rs` | 標準入出力の口。引数を読み、1 行ずつ `mcp` に渡す |

## これから足すもの

書き込みのツールは、次の規則を機械で守る形で足す予定である。

- 人格の憲法(`core/`)には書かせない。変えたいときは、起案を別の場所に置く。
- 記憶の frontmatter が、決まった形(スキーマ)に合っているかを検査する。
- 既存の記憶を直すときは、呼び出し側が読んだ `version` と、いまのファイルが一致するときだけ通す。
- 新しい記憶を足したら、その枝の索引の受信箱に 1 行足す。

## 開発

```bash
cd tools/claudia-memory
cargo test          # 単体テストと、バイナリを起動する通しのテスト
cargo fmt
cargo clippy --all-targets -- -D warnings
nix build .#claudia-memory                      # リポジトリのルートで。単体ビルド
nix build .#checks.x86_64-linux.claudia-memory  # テストを Nix のサンドボックスの中で走らせる
```

通しのテスト(`tests/cli.rs`)は、一時フォルダに小さな AgentMemory を作ってバイナリを起動する。本物の vault は読まない。
