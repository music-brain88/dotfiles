{ config, pkgs, lib, profile, ... }:

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
  ]
  # デスクトップの設定が名前で指名するフォント。native 機だけに入れる (Issue #838)。
  # 指名されたフォントが無いと fontconfig は黙って代役を選ぶので、設定と同じリポジトリで入れる。
  # WSL と CI のイメージは GUI を持たないので、容量の大きい CJK フォントを入れない。
  # Fonts the desktop configs request by name; native profile only (Issue #838).
  # fontconfig silently substitutes a missing family, so they are installed alongside the configs.
  # WSL and the CI image have no GUI, so they skip these (the CJK packages are large).
  ++ lib.optionals (profile == "native") [
    # fonts.conf: default sans-serif / serif (Noto Sans, Noto Serif)
    noto-fonts

    # fonts.conf / waybar / wofi / hyprlock: Japanese UI text (Noto Sans CJK JP)
    noto-fonts-cjk-sans

    # fonts.conf: Japanese serif fallback (Noto Serif CJK JP)
    noto-fonts-cjk-serif

    # waybar / wofi / mako: UI text and icon glyphs (JetBrainsMono Nerd Font)
    nerd-fonts.jetbrains-mono
  ];
}
