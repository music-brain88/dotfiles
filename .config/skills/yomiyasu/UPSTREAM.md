# yomiyasu の取り込み元と更新手順 / Upstream and update procedure

このディレクトリは [nanaism/yomiyasu](https://github.com/nanaism/yomiyasu) の `skills/yomiyasu/` を無改変で同梱したものである。
This directory vendors `skills/yomiyasu/` from nanaism/yomiyasu without modification.

| 項目 | 値 |
|---|---|
| 取り込み元 | https://github.com/nanaism/yomiyasu |
| タグ / コミット | `v1.0.0` / `42e78b8a8b62e23674cebc800b6d49c4554de3be` |
| 取り込み日 | 2026-10-01 |
| ライセンス | MIT（同梱の `LICENSE`。著作権表示は上流のまま） |
| 取り込んだもの | `SKILL.md`、`references/`（統語変換規則、スロップ語カタログ、ドメイン別仕様）、`scripts/yomiyasu_lint.py` |
| 取り込まなかったもの | `assets/`（ロゴ画像。SKILL.md から参照されていない）、`.claude-plugin/`（マーケットプレイス用メタデータ。home-manager で直接マウントするので不要） |

## 本環境での読み替え

上流のファイルはここでは書き換えない。本環境の表記（和欧文間の半角スペースあり、走査型文書での表と箇条書きの多用、法律文書の語彙としての「正本」など）と衝突する指摘をどう扱うかは、`../standalone-report-writing/SKILL.md` の「yomiyasu の指摘の読み方」に書く。上流へ修正を送るときに diff を綺麗に保つため。

## 更新手順

1. `git clone --depth 1 --branch <新タグ> https://github.com/nanaism/yomiyasu.git /tmp/yomiyasu` で取得する。
2. `skills/yomiyasu/SKILL.md`、`skills/yomiyasu/references/`、`skills/yomiyasu/scripts/` と、リポジトリ直下の `LICENSE` をこのディレクトリへ上書きコピーする。
3. 本ファイルの「タグ / コミット」「取り込み日」を更新する。
4. `../standalone-report-writing/SKILL.md` の「yomiyasu の指摘の読み方」を見直す。スロップ語リスト（`scripts/yomiyasu_lint.py` の `SLOP_WORDS`）と閾値（太字頻度、箇条書き比率）が変わっていたら、読み替え表を合わせる。
5. `python3 scripts/yomiyasu_lint.py <任意の日本語 Markdown>` で動作を確認する。
