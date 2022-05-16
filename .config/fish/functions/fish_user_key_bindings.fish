function fish_user_key_bindings
  # Ctrl + y を潰す理由 
  # 貼り付け。ctrl+wなどで一気に削除された部分を貼り付けられる。
  # マウスやtmuxのコピーモードで代用できるので潰す優先度は高い。
  bind \cy fzf-docker-continer-name-select
  fzf_key_bindings
end
