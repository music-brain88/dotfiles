# Pull Request 作成

Pull Request を作成します。

## 手順

1. `.github/PULL_REQUEST_TEMPLATE.md` を読み込んでテンプレートの形式を確認
2. `git log main..HEAD` と `git diff main...HEAD` で変更内容を確認
3. Conventional Commits スタイルでタイトルを決定:
   - `feat`: 新しい機能
   - `fix`: バグ修正
   - `docs`: ドキュメントのみの変更
   - `chore`: コードに触れない変更
   - `refactor`: リファクタリング
   - `style`: フォーマットのみの変更
   - `test`: テストの追加・修正
   - `perf`: パフォーマンス改善
   - `ci`: CI設定の変更
   - `build`: ビルドシステムの変更
4. テンプレートに沿って PR 本文を作成
5. `gh pr create` で PR を作成
6. 作成した PR の URL を表示

## 追加情報

$ARGUMENTS
