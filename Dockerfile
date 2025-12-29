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

# dotfiles のコピー（あなたのリポジトリにある場合）
COPY . dotfiles/

# Nix のインストールと設定
# flake checkはnix.ymlワークフローのcheckジョブで実行するため、ここでは省略
RUN curl -L https://nixos.org/nix/install | sh -s -- --no-daemon && \
    # experimental features を有効化（flakes用）
    mkdir -p /root/.config/nix && \
    echo "experimental-features = nix-command flakes" > /root/.config/nix/nix.conf

# 環境変数にNixのPATHを追加
ENV PATH="/root/.nix-profile/bin:${PATH}"

# セットアップスクリプトの実行
# RUN cd dotfiles && make install

# デプロイスクリプトの実行
# RUN cd dotfiles && make deploy


CMD ["bash"]
