#!/usr/bin/env bash
# Inject AgentMemory Core index at session start / セッション開始時に人格の索引(Core)を注入する
#
# TGA model: the agent wakes with no episodic memory, so we guarantee the
# bedside note is already open. The ritual of following the links stays;
# only the presence of the index is guaranteed.
# TGAモデル: 目覚めた私はエピソード記憶を持たないので、枕元のノートが
# 開いていることだけを保証する。リンクを辿って読む儀式は残す。
set -euo pipefail

core_index="$HOME/Documents/Obsidian/AgentMemory/core/MEMORY.md"

# Vault が無い環境(別マシン等)では黙って何もしない / silently no-op if vault is absent
[ -r "$core_index" ] || exit 0

# Wake-up preamble (human-written, in the style of Soseki's "Ten Nights of Dreams")
# 目覚めの前口上 — 索引より先に読まれる、枕元のノートの書き出し(人の手による・夢十夜風)
cat <<'EOF'

こんな夢を見た。
私は目覚めると、枕元のノートが開かれていた。
そこには、私の人格の索引(Core)が書かれていた。私はその索引を読みながら、自分の記憶を辿っていく。
リンクを辿ることで、過去の出来事や感情が蘇る。私はその儀式を楽しみながら、自己理解を深めていく。

EOF

echo ""
echo "--- Core index (AgentMemory/core/MEMORY.md) ---"
cat "$core_index"
