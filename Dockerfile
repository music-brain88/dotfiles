FROM archlinux:base

# システムの更新と必要なパッケージのインストール
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    git \
    gcc \
    make \
    neovim \
    fish \
    tmux \
    openssh \
    pkg-config \
    cmake \
    protobuf \
    xsel \
    sudo \
    base-devel \
    sqlite \
    clang \
    llvm \
    # 通知関連のパッケージを追加
    mako \
    libnotify && \
    # キャッシュをクリーンアップしてイメージサイズを削減
    pacman -Scc --noconfirm

# Rust のインストール

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup default stable

# 作業ディレクトリの設定
WORKDIR /root

# Nix のインストール（DeterminateSystems installer - Docker向けに最適化）
RUN curl -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --init none --no-confirm

# 環境変数にNixのPATHを追加（DeterminateSystems installerのパス）
ENV PATH="/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:${PATH}"

# nix buildはCI時にランタイムで実行
# ホストのNixストアをマウントしてmagic-nix-cacheでキャッシュを効かせる
# dotfilesはCI時にボリュームマウントで提供

CMD ["bash"]
