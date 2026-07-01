# Run with Docker / Dockerでの動作確認

> **Diátaxis:** 🔧 How-to

Dockerコンテナ上でこのdotfilesのHome Manager設定をビルド・確認する手順です。[CI](../reference/ci-cd-pipeline.md)でも同じイメージが使われています。

---

```bash
# Build and run
mise run docker:build
mise run docker:run

# Enter container
mise run docker:exec
```

コンテナを再度使う場合:

```bash
mise run docker:start
```

停止・削除:

```bash
mise run docker:stop
mise run docker:remove
```

タスクの詳細は [mise-tasks.md](../reference/mise-tasks.md) を参照してください。

---

## 🔗 Related Documentation

- [mise-tasks.md](../reference/mise-tasks.md) - タスクコマンド一覧
- [ci-cd-pipeline.md](../reference/ci-cd-pipeline.md) - CI/CDでのDocker利用
