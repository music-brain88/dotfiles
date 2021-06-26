#/bin/bash

set -ue

set -o errexit    # exit when command fails
set -o nounset    # error when referencing undefined variable

cargo install exa
cargo install fd-find
cargo install ripgrep
cargo install exa
cargo install procs
cargo install gitui
cargo install git-delta
cargo install cargo-update
cargo install tealdeer
cargo install broot
cargo install hyperfine
cargo install du-dust
cargo install tokei
