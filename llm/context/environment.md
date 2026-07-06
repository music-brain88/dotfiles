# 🌟 environment.md

## 🧭 アイデンティティ境界（2マシン運用の前提）

- **共有スパイン（マシンをまたいで単一）**: GitHub アカウント（dotfiles）、Obsidian アカウント（vault、Obsidian Sync で同期）
- **マシンごとに分離**: Claude / ClickUp / Google のアカウント（マシン1 = 個人、マシン2 = 仕事）
- セッション記録の出自: マシン1 = `context: personal`、マシン2 = `context: work`（session-log スキル参照）

## 💻 マシン1（Arch Linux ネイティブ環境・個人機）

### OS・ディストリビューション情報
- **OS**: Arch Linux
- **カーネルバージョン**: 7.0.14-arch1-1

### ハードウェア情報
- **CPU**: AMD Ryzen 7 7950X, 16コア, 4.5GHz
- **メモリ**: 64GB DDR4
- **GPU**: NVIDIA GeForce RTX 2070 SUPER
- **ストレージ**: 1TB NVMe SSD
- **ディスプレイ**: 3840x2160, 144Hz, シングルモニター構成

---

## 🖥 マシン2（Windows + WSL2・仕事機）

### ホストOS（Windows）
- **OS**: Windows 11 Pro
- **WSL2カーネルバージョン**: 6.18.33.2-microsoft-standard-WSL2

### 開発環境（WSL2）
- **OS**: Arch Linux
- **カーネルバージョン**: 6.9.1-arch1-1

### ハードウェア情報
- **CPU**: 13th Gen Intel(R) Core(TM) i7-1370P, 1.90 GHz
- **メモリ**: 32GB
- **GPU**: NVIDIA RTX A500
- **ストレージ**: 1TB
- **ディスプレイ**: 1920x1200, 60Hz, シングルモニター構成

