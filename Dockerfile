FROM archlinux:latest

RUN pacman -Syu --noconfirm
RUN pacman -S neovim make awk git gcc fish --noconfirm

WORKDIR /root

RUN git clone https://github.com/music-brain88/dotfiles.git
