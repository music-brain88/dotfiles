{ config, pkgs, ... }:

{
  # Font packages
  home.packages = with pkgs; [
    # Programming font (monospace) - for terminal and editors
    hackgen-nf-font

    # System UI font (sans-serif) - for browser and desktop
    source-han-sans

    # System UI font (serif) - for documents and reading
    source-han-serif

    # Color emoji font - fallback for emoji glyphs in terminal and desktop
    # 絵文字フォールバック用 (WezTerm の確認オーバーレイ 🛑 等が豆腐になるのを防ぐ)
    noto-fonts-color-emoji
  ];
}
