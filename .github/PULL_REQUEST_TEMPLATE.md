<!--
以下のパターンにしたがってpull requestのタイトルにつけてください
<型>(変更の範囲): <タイトル>
build - ビルドシステムや外部の依存関係に影響を与える変更 (依存関係の更新)
ci - CI設定ファイルやスクリプトへの変更（基本的には.github/workflowsディレクトリ）。
docs - ドキュメンテーションのみの変更
feat - 新しい機能
fix - バグ修正
chore - コードに触れない変更 (例: リリースノートの手動更新)。リリースノートの変更を生成しない
refactor - リファクタリングを含むコード変更。
style - コードの意味に影響を与えない変更（空白、書式、セミコロンの欠落、など）
test - 不足しているテストの追加や既存のテストの修正、またテストアプリの変更など
perf - パフォーマンスを向上させるためのコード変更
-->

<!--
使用例

タイトルおよび破壊的変更のフッターを持つコミットメッセージ
feat: allow provided config object to extend other configs
BREAKING CHANGE: `extends` key in config file is now used for extending other config files

破壊的変更を目立たせるために ! を持つコミットメッセージ
feat!: send an email to the customer when a product is shipped

本文を持たないコミットメッセージ
docs: correct spelling of CHANGELOG

スコープを持つコミットメッセージ
feat(lang): add polish language


複数段落からなる本文と複数のフッターを持ったコミットメッセージ
fix: prevent racing of requests

Introduce a request id and a reference to latest request. Dismiss
incoming responses other than from latest request.

Remove timeouts which were used to mitigate the racing issue but are
obsolete now.

Reviewed-by: Z
Refs: issueチケット
-->

## [optional body]
<!--
タイトル部分が長くなりそうであれば、無理せずタイトルと本文で分けましょう。
その場合タイトルには簡潔な「何故コードを変更したのか？」を書き、本文で具体的かつ詳細を書くと良いでしょう。
逆にタイトルが短い文章で済むのであれば、無理して本文を書く必要はありません。
ちなみに本文についても、72行以内に収めることを推奨している旨の記述がPro Gitにあります。
https://www.praha-inc.com/lab/posts/commit-message
-->
## [optional footer(s)]
<!--
フッターにはコミットログの内容に関連するURLを載せましょう。
例えば、チケットのURLやコミットする前に議論を重ねたIssueやチケット、slackのリンクなどが挙げられます。
https://www.praha-inc.com/lab/posts/commit-message
-->
