#/bin/bash

set -ue

set -o errexit    # exit when command fails
set -o nounset    # error when referencing undefined variable

# An cargo update tools
cargo install cargo-update

# A simple, fast and user-friendly alternative to 'find'
cargo install fd-find

# ripgrep recursively searches directories for a regex pattern while respecting your gitignore
cargo install ripgrep

# A replacement for 'ls'
cargo install eza

# A replacement for 'cat'
cargo install bat

# A replacement for 'ps'
cargo install procs

# terminal-ui for git written in Rust
cargo install gitui --locked

# A syntax-highlighting pager for git, diff, and grep output
cargo install git-delta

# A very fast implementation of tldr in Rust.
cargo install tealdeer

# A better way to navigate directories
cargo install broot

# A command-line benchmarking tool
cargo install hyperfine

# A more intuitive version of du in rust
cargo install du-dust

# Count your code, quickly.
cargo install tokei

# Fuzzy Finder in rust!
cargo install skim

# JSON Query Language tool built with Rust 🦀.
cargo install jql
