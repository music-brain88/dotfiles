# mocha-arch-wallpaper: Hyprland の壁紙 (mocha_arch.svg) を resvg で PNG にする (Issue #840)。
# flake.nix の overlay から callPackage され、nix/modules/desktop.nix が ~/.local/share/wallpapers/ に置く。
# Renders the Hyprland wallpaper (mocha_arch.svg) to PNG with resvg (Issue #840).
# Built via overlay in flake.nix; nix/modules/desktop.nix places it under ~/.local/share/wallpapers/.
{ lib, runCommand, resvg, nerd-fonts }:

let
  # Nix のサンドボックスには fontconfig の設定が無いので、フォントは名前ではなくパッケージの中のファイルを直接渡す。
  # The build sandbox has no fontconfig setup, so fonts are passed as files from the package, not by name.
  fontDir = "${nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono";
in
runCommand "mocha-arch-wallpaper"
{
  nativeBuildInputs = [ resvg ];

  meta = with lib; {
    description = "Catppuccin Mocha の地に Nerd Font の Arch グリフと「I use Arch btw」を置いた壁紙";
    homepage = "https://github.com/music-brain88/dotfiles/tree/main/tools/wallpaper";
    license = licenses.mit;
    platforms = platforms.linux;
  };
} ''
  mkdir -p "$out"
  # --skip-system-fonts で、渡したフォントのファイル以外を使わない (グリフが無ければ代役ではなく欠けとして見える)。
  # --skip-system-fonts restricts resvg to the given font files, so a missing glyph shows up instead of being substituted.
  resvg \
    --skip-system-fonts \
    --use-font-file ${fontDir}/JetBrainsMonoNerdFont-Regular.ttf \
    --use-font-file ${fontDir}/JetBrainsMonoNerdFont-Bold.ttf \
    ${./mocha_arch.svg} "$out/mocha_arch.png"
''
