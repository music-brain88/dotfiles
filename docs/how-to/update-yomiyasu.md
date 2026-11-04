# yomiyasu を上げる / Update yomiyasu

> **Diátaxis:** 🔧 How-to

dotfiles が参照している yomiyasu スキルのバージョンを上げる手順です。yomiyasu は AI が書いた日本語を推敲するスキルで、`standalone-report-writing` スキルの点検手順と点検ツール `standalone-check --with-yomiyasu` が、yomiyasu の lint(`scripts/yomiyasu_lint.py`)を使います。dotfiles は yomiyasu をリポジトリにコピーせず、flake input でタグを固定して上流を参照します(Issue #782)。それまでは、#638 で取り込んだ v1.0.0 を `.config/skills/yomiyasu/` にコピーしていました。

## 取り込み元と固定の仕方 / Source and pinning

次の表は、dotfiles が yomiyasu をどこから取り込み、どう固定しているかを示します。

| 項目 | 値 |
|---|---|
| 取り込み元 | [nanaism/yomiyasu](https://github.com/nanaism/yomiyasu) の `skills/yomiyasu/` を丸ごと使います |
| 固定しているバージョン | タグ `v2.5.0`(コミット `29d67ccb05e370b5958d72920a9cd1aa829dee80`)に固定しています |
| 固定の仕方 | `flake.nix` の `inputs.yomiyasu` に `url = "github:nanaism/yomiyasu/v2.5.0"; flake = false;` と書き、`flake.lock` がコミットと narHash を記録します |
| マウント先 | `home.nix` が `"${inputs.yomiyasu}/skills/yomiyasu"` を `~/.claude/skills/yomiyasu` と `~/.copilot/skills/yomiyasu` に `recursive = true` でマウントします |

- `flake.nix` にタグを書いているので、`nix flake update`(`mise run nix:update`)を実行しても yomiyasu のバージョンは変わりません。`nix flake update` はタグを解決し直すだけなので、上流がタグを付け直さない限り同じコミットになります。
- `flake.lock` の narHash が上流のファイルの中身を固定します。dotfiles の側で上流のファイルを書き換える場所はないので、上流のファイルは無改変のまま使われます。
- マウント先はコピーしていたころと同じです。そのため、`standalone-check` が lint を探す場所(`~/.claude/skills/yomiyasu/scripts/yomiyasu_lint.py`、次に `~/.copilot/skills/yomiyasu/scripts/yomiyasu_lint.py`)も変わっていません。
- lint は Python の標準ライブラリだけで動きます。python3 は `nix/modules/dev-tools.nix` が入れています。

## 本環境での読み替え / Local reading rules

dotfiles は上流のファイルを書き換えません。本環境の表記と衝突する指摘(走査型文書で太字と箇条書きが多いという指摘、版管理と法律文書の用語として使う「正本」への指摘など)は、次の 2 か所で読み替えます。

- `.config/skills/standalone-report-writing/SKILL.md` の「yomiyasu の指摘の読み方」の表が、指摘の種類ごとに従うか読まないかを決めます。表の各行には、対応する yomiyasu の rule ID を書いています。
- `tools/standalone-check/src/main.rs` の `YOMIYASU_IGNORED_RULES` と `YOMIYASU_IGNORED_SLOP_MARK` が、`--with-yomiyasu` で表示しない指摘を決めます。判定の詳細は、[standalone-check の README の「yomiyasu の指摘のうち除外するもの」](../../tools/standalone-check/README.md#yomiyasu-の指摘のうち除外するもの)の節にあります。

上流の挙動を変えたくなったときも、上流のファイルではなく、この 2 か所を直します。読み替えでは足りず、上流のファイルに手を入れる必要が出たときは、取り込み方を見直す Issue を立てます。取り込み方の比較は #782 を見てください。

## 更新の手順 / Update procedure

バージョンを上げる作業者は、次の順で作業します。手順 1 から 6 は作業ブランチで行い、手順 7 だけを PR のマージ後に main で行います。

1. `flake.nix` の `inputs.yomiyasu` の `url` のタグを、新しいタグに書き換えます。上流のタグの一覧は `gh release list -R nanaism/yomiyasu` で見られます。
2. `nix flake lock` を実行します。`nix flake lock` は `url` が変わった input だけを解決し直し、`• Updated input 'yomiyasu'` と表示します。ほかの input を動かさないため、`nix flake update` は使いません。
3. `git diff flake.lock` で、yomiyasu のノードの `locked` と `original` の `ref` だけが変わったことを確かめます。
4. 上流の `CHANGELOG.md` を、今のバージョンから新しいバージョンまで読みます。新しいバージョンの store のパスは、次のコマンドで引けます。

   ```bash
   nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.yomiyasu.outPath'
   ```

   作業者は、CHANGELOG と store の `skills/yomiyasu/scripts/yomiyasu_lint.py` で、次の項目が変わっていないかを確かめます。
   - `--json` の出力の形が同じかを確かめます。見る項目は、`format_version`、トップレベルの `findings` の配列、各指摘の `rule`、`severity`、`message`、`snippet` です。
   - 除外に使う rule ID(`excess_bold`、`excess_list`、`slop_vocabulary`)が残っているかを確かめます。
   - `slop_vocabulary` の語の一覧(`SLOP_WORDS`)に「正本」が入っているかを確かめます。
   - `slop_vocabulary` の message が「AI頻出語彙「<語>」が含まれています…」の形のままかを確かめます。standalone-check は、この形の鉤括弧の部分で「正本」を見分けます。上流がこの形を変えると、「正本」の指摘は除外されずに表示されます。
   - lint が、`--strict` も `--fail-on` も付けないときに、指摘があっても終了コード 0 で終わるかを確かめます。standalone-check は 0 以外を失敗として扱います。
   - 新しく足された規則のうち、本環境の表記と衝突するものがないかを確かめます。
5. 手順 4 で変わっていた項目に合わせて、「本環境での読み替え」の節の 2 か所を直します。standalone-check を直したときは、`cd tools/standalone-check && cargo test` を実行します。
6. 動作を確かめます。`mise run nix:build` は Home Manager の設定をビルドするだけで、反映はしません。そのため、PATH にある `standalone-check` は前に反映したバージョンのままです。手順 5 で除外判定を直した場合も確かめられるように、新しくビルドした `result/home-path/bin/standalone-check` を使います。

   ```bash
   mise run nix:build
   grep -m1 'version:' result/home-files/.claude/skills/yomiyasu/SKILL.md
   result/home-path/bin/standalone-check <日本語の Markdown> --with-yomiyasu \
     --yomiyasu-script result/home-files/.claude/skills/yomiyasu/scripts/yomiyasu_lint.py
   ```

   `SKILL.md` の `version` が新しいバージョンになっていて、standalone-check の出力が `[SKIP] yomiyasu` にならなければ、動作の確認は済みです。
7. PR のマージ後に、main で `mise run nix:switch` を実行します。

## ライセンス / License

yomiyasu のライセンスは MIT です。上流の `LICENSE` は store の `skills/yomiyasu/LICENSE` に入っていて、マウント先の `~/.claude/skills/yomiyasu/LICENSE` からも読めます。lint が使う絵文字のデータは Unicode, Inc. のデータから作られていて、その Unicode License V3 の表示の置き場は `skills/yomiyasu/UNICODE-LICENSE.txt` です。dotfiles のリポジトリには上流のファイルが入らないので、ライセンスの表示は store の上流のファイルがそのまま担います。
