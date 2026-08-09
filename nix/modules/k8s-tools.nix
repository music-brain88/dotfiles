{ config, pkgs, ... }:

{
  # Kubernetes / hexhive cluster tools
  # hexhive クラスタ運用ツール — ノード OS 層(Talos)+ Secrets(SOPS + age)+ k8s CLI
  home.packages = with pkgs; [
    talosctl # Talos Linux CLI (hexhive node OS / ノード管理)
    kubectl # Kubernetes CLI
    sops # Secrets encryption for git-committed files / コミット前の秘密暗号化
    age # Encryption backend for SOPS / SOPS の暗号化バックエンド
  ];
}
