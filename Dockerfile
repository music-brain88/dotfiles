FROM archlinux:latest

RUN pacman -Syu --noconfirm
RUN pacman -S make awk git gcc fish --noconfirm
