# standalone-check

配布文書(報告・依頼書・引き継ぎ資料・Issue と PR の本文)の自立可読性を機械的に点検する CLI である。`.config/skills/standalone-report-writing/SKILL.md` の「執筆後の点検手順」から呼ばれる。もとは Python スクリプトだったが、dotfiles に Python のツールを持たない方針で Rust に書き直した(Issue #639)。

## 何を検査するか

検査は 6 種類あり、次の表にコードと内容と重さを示す。

| コード | 内容 | 重さ |
|---|---|---|
| MAIN | 節の冒頭の段落が句点で終わる文を含まない | WARN |
| MAIN | 節の冒頭が表か箇条書きで始まる(見出しが主文を兼ねているか確認する) | INFO |
| TAIGEN | 段落が句点で終わらない、または文が名詞で終わる(体言止め) | WARN |
| LIST | 20 字以上の箇条書き項目が句点で終わらない | WARN |
| CONTEXT | 直前の会話を前提にする語(「こっち」「先方」「例の」「さっき」など) | WARN |
| TOUTEN | 1 文に読点が 3 つ以上あり、節がつながれている | WARN |
| TSUIKU | 「X は A、Y は B」型の並列で動詞がない(対句の疑い) | WARN |

CONTEXT は、「例の件」のように書き手と読み手が共有していると決めつけた対象を指す「例の」を WARN にする。直前の文字が漢字の「例の」(「事例の」「判例の」)と、直前が「この」「その」「次の」「上の」「表の」「以下の」の「例の」(例そのものを指す書き方)は WARN にしない。表の行でも段落と同じく、インラインコードの中は CONTEXT の検査の対象にしない。

判定は物理行ではなく段落単位で行う。連続する本文行と引用行は 1 つの段落に結合し、箇条書きは続きの行(インデント行と、空行を挟まない直後の行)を項目に結合する。行に `<!-- standalone: ignore -->` を置くと、その行は検査しない。

## 使い方

```sh
standalone-check FILE [FILE ...]
standalone-check FILE --with-yomiyasu            # yomiyasu の lint も実行する
standalone-check FILE --yomiyasu-script PATH      # lint の場所を指定する(.py なら python3 で実行)
standalone-check FILE --json                      # JSON で出力する
```

終了コードは、WARN なしが 0、本ツールの WARN か yomiyasu の warn / error があれば 1、ファイルを読めないか lint を実行できなければ 2 である。INFO と yomiyasu の info は表示だけで、終了コードに影響しない。

lint の異常終了は、JSON を出力していても失敗として扱う。終了コードが 0 の場合も、応答は `findings` 配列を持つ JSON オブジェクトでなければならない。各指摘には文字列の `message` と `snippet` が必要で、`severity` は `info` / `warn` / `error` を大文字小文字を区別せずに受ける。`severity` の省略時は従来どおり `warn` とする。`line` や `rule` などの追加フィールドは保持する。応答形式が不正な場合は、終了コード 2 と `yomiyasu_status` の `failed` で返し、通常出力では `[SKIP]` と表示する。

`--with-yomiyasu` は `~/.claude/skills/yomiyasu/scripts/yomiyasu_lint.py`(次に `~/.copilot/skills/...`)を探し、`python3` で実行する。本環境の表記と衝突する指摘(和欧文間の半角スペース、太字頻度、箇条書き比率、用語「正本」)は除いて表示する。環境変数 `STANDALONE_CHECK_YOMIYASU` でも場所を指定できる。

## 開発

```sh
cd tools/standalone-check
cargo test                      # 単体テスト + tests/cli.rs(fixtures は #638 のレビューの再現ケース)
cargo run -- path/to/doc.md
nix build ..#standalone-check   # dotfiles ルートで nix build .#standalone-check
```

配布は `flake.nix` の overlay で `pkgs.standalone-check` を定義し、`nix/modules/dev-tools.nix` の `home.packages` に入れている。`mise run nix:switch` で `~/.nix-profile/bin/standalone-check` に入る。
