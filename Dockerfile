FROM archlinux:latest

RUN pacman -Syu --noconfirm
RUN pacman -S neovim make awk git gcc fish --noconfirm

WORKDIR /root

COPY dotfiles .
