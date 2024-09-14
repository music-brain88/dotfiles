FROM archlinux:base

# システムの更新と必要なパッケージのインストール
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    git \
    gcc \
    make \
    neovim \
    fish \
    openssh \
    pkg-config \
    cmake \
    protobuf \
    xsel \
    sudo \
    base-devel

# Rust のインストール

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# 作業ディレクトリの設定
WORKDIR /root

# dotfiles のコピー（あなたのリポジトリにある場合）
COPY . dotfiles/

# セットアップスクリプトの実行
# RUN cd dotfiles && make install

# デプロイスクリプトの実行
# RUN cd dotfiles && make deploy


CMD ["bash"]
