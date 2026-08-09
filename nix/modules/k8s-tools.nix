{ config, pkgs, ... }:

{
  # Kubernetes / hexhive cluster tools
  # hexhive クラスタ運用ツール — ノード OS 層(Talos)+ k8s CLI/TUI + Secrets(SOPS + age)
  # k8s 関連ツールはこのモジュールに集約する(dev-tools からは分離)
  # All Kubernetes-domain tooling lives here so ownership is unambiguous
  home.packages = with pkgs; [
    talosctl # Talos Linux CLI (hexhive node OS / ノード管理)
    kubectl # Kubernetes CLI
    k9s # Kubernetes TUI
    sops # Secrets encryption for git-committed files / コミット前の秘密暗号化
    age # Encryption backend for SOPS / SOPS の暗号化バックエンド
  ];
}
