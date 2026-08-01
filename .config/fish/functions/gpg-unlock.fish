function gpg-unlock --description "Warm gpg-agent passphrase cache via a fresh pty (for Tailscale SSH) / ptyを挟んでGPGキャッシュを温める"
  script -qec 'export GPG_TTY=$(tty); gpg-connect-agent updatestartuptty /bye; echo unlock | gpg --clearsign -o /dev/null' /dev/null
end
