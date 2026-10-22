{ config, pkgs, lib, ... }:

{
  # paru: AUR のビルドを devtools の chroot に移す設定を symlink する (Issue #743)。
  # native 機だけで読み込む (home.nix の profile == "native")。chroot は systemd-nspawn を
  # 使うが、WSL 機で動く保証が無いので別の作業で確かめる。paru と devtools は OS 層
  # (pacman) が入れるので、ここではパッケージを入れない。手順は
  # docs/how-to/build-aur-packages-in-chroot.md。
  # paru: symlink the config that moves AUR builds into a devtools chroot (Issue #743).
  # Imported on the native machine only (profile == "native" in home.nix): the chroot
  # uses systemd-nspawn, which is not guaranteed to work on WSL, so that is checked
  # separately. paru and devtools belong to the OS layer (pacman), so no packages here.
  # See docs/how-to/build-aur-packages-in-chroot.md.
  xdg.configFile."paru/paru.conf".source = ../../.config/paru/paru.conf;
}
