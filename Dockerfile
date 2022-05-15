FROM archlinux/archlinux:base-devel-20220508.0.55614

RUN pacman -Syu --noconfirm
RUN pacman -S neovim make awk git gcc fish pkg-config python --noconfirm

WORKDIR /root

COPY . dotfiles/
