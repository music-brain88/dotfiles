# AUR のパッケージを chroot でビルドする / Build AUR Packages in a Chroot

> **Diátaxis:** 🔧 How-to

paru が AUR のパッケージを devtools の chroot の中でビルドするように設定する手順です。対話環境のシェルでは、Nix と mise が PATH と環境変数にツールを置いています。そのシェルから起こした makepkg がそれらを拾うと、Arch のライブラリを見つけられずにビルドが失敗します。この手順は、対話環境の PATH と環境変数がビルドに届く経路を切ります(Issue #743)。漏れが起きる構造は [architecture.md の「対話環境の環境変数と PATH は OS 側のビルドに漏れる」](../explanation/architecture.md#対話環境の環境変数と-path-は-os-側のビルドに漏れる--interactive-environment-leaks-into-os-side-builds) に書いてあります。

## 前提 / Prerequisites

- paru の `Chroot` オプションは、`LocalRepo` オプションが有効でないと使えません。`LocalRepo` は、`/etc/pacman.conf` に宣言済みのローカルリポジトリを要求します。`man paru.conf` の LocalRepo の説明によると、リポジトリはディスク上にまだ無くてもかまいません。
- chroot でのビルドは、`devtools` パッケージの makechrootpkg が行います。makechrootpkg は systemd-nspawn で clean な container を作り、その中で makepkg を動かします。対話環境の PATH と環境変数は container の中に入りません。
- この構成は、Nix や mise が PATH に置くものが Arch のビルドに漏れる問題(#418、#554、#740)を経路ごと閉じます。これまでのように、漏れたツールを 1 つずつ Nix から外す対処は要らなくなります。
- この手順は native 機だけを対象にします。WSL2 機の扱いは「範囲外」の節に書いてあります。

## 1. system 側を準備する(sudo が要る)

最初の作業は devtools の導入です。

```bash
sudo pacman -S --needed devtools
```

次に、`/etc/pacman.conf` の末尾に `[aur]` のブロックを足します。書き方は、ファイル末尾のコメントにある `#[custom]` の例と同じです。

```ini
[aur]
SigLevel = Optional TrustAll
Server = file:///home/<ユーザー名>/.local/share/paru/repo
```

- `SigLevel = Optional TrustAll` にするのは、このリポジトリには自分でビルドしたパッケージしか入らず、署名もしないからです。
- pacman.conf の `Server =` には `file://` に続けて絶対パスを書きます。`~` や `$HOME` は展開されないので、`<ユーザー名>` を自分のユーザー名に置き換えてください。
- `~/.local/share/paru/repo` はユーザーが書けるディレクトリなので、paru はリポジトリにパッケージを足すときに sudo を使いません。
- このディレクトリを手で作る必要はありません。

## 2. Nix 側の設定を当てる

手順 1 が済んでから、Nix の設定を当てます。

```bash
mise run nix:switch
```

`nix/modules/paru.nix` が、リポジトリの `.config/paru/paru.conf` を `~/.config/paru/paru.conf` に symlink します。この設定の中身は、`Include = /etc/paru.conf` で system 側の設定を取り込んだうえで `LocalRepo`・`Chroot`・`SudoLoop` を有効にするものです。

> **Note:** 手順 1 より先に nix:switch を当てないでください。paru はユーザー側の `paru.conf` を見つけると、`/etc/paru.conf` を直接は読みません。そのため symlink が張られた時点で `Chroot` が有効になります。system 側の準備が済んでいないと、paru は `error: no local repos configured` か `error: can not use chroot builds: devtools is not installed` を出して止まります。

symlink が張られたら、次はローカルリポジトリの初期化です。

```bash
paru -Ly
```

`-L`(`--repoctl`)に `-y`(`--refresh`)を付けると、paru はローカルリポジトリを refresh します。paru 自身も、ローカルリポジトリが無いときのエラーでこのコマンドを初期化の手順として案内しています。この初期化が要るのは、`[aur]` を宣言しただけでは DB が無いからです。DB が無い間、`pacman -Sl aur` は `database file for 'aur' does not exist` と警告します。

## 3. 既存の AUR パッケージを [aur] に移す

切り替える前から入っている AUR パッケージを `[aur]` に移さないと、それらは `paru -Syu` の更新対象から外れます。`man paru.conf` の LocalRepo の説明にあるとおり、`LocalRepo` を有効にした paru が更新の対象にするのはローカルリポジトリにあるパッケージで、foreign パッケージ(どの sync リポジトリにも無いパッケージ)は対象から外れるからです。

まず、移す対象の foreign パッケージを一覧します。

```bash
pacman -Qm
```

次に、各パッケージの今の版のアーカイブを `/var/cache/pacman/pkg` と `~/.cache/paru/clone/<pkgbase>/` から探し、`~/.local/share/paru/repo` にコピーします。clone の下のディレクトリ名は pkgbase なので、ループは split パッケージも拾えるように `clone/*/` で探す形です。アーカイブが見つからないパッケージについては、ループが `missing:` の行を表示する仕組みです。

```bash
repo=~/.local/share/paru/repo
mkdir -p "$repo"
pacman -Qm | while read -r name ver; do
  f=$(ls /var/cache/pacman/pkg/"$name-$ver"-*.pkg.tar.* ~/.cache/paru/clone/*/"$name-$ver"-*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -n1)
  if [ -n "$f" ]; then cp "$f" "$repo"/; else echo "missing: $name $ver"; fi
done
```

コピーしたアーカイブを、`repo-add` でローカルリポジトリの DB に登録します。`man repo-add` によると、`repo-add <DB のパス> <パッケージ>...` は DB のファイルが無ければ作りますが、親ディレクトリは先に存在している必要があります。上の `mkdir -p` はそのための保険です。DB のファイル名は、pacman.conf のリポジトリ名 `[aur]` に合わせて `aur.db.tar.gz` にします。

```bash
repo-add ~/.local/share/paru/repo/aur.db.tar.gz ~/.local/share/paru/repo/*.pkg.tar.zst
```

登録したら、`paru -Ly` か `sudo pacman -Sy` で DB を読み直します。`pacman -Qm` の一覧が `missing:` のパッケージだけに減り、移したパッケージが `pacman -Sl aur` に載れば移行は完了です。

アーカイブがキャッシュに無かったパッケージは、chroot でビルドし直して `[aur]` に入れます。`man paru` によると、`--rebuild` はキャッシュにビルド済みのものがあっても対象をビルドし直すオプションです。

```bash
paru -S <パッケージ> --rebuild
```

## 4. 動作を確かめる

次の 3 つのコマンドで、ローカルリポジトリと chroot ビルドと更新が働くことを確かめます。

```bash
pacman -Sl aur                  # 手順 3 で移したパッケージが一覧に出る
paru -S wezterm-git --rebuild   # #418 と #740 でビルドが壊れた再現パッケージ
paru -Syu                       # [aur] のパッケージが更新の対象に入る
```

- `pacman -Sl aur` がエラーなしで終われば、`[aur]` の宣言と初期化は有効です。
- `paru -S wezterm-git --rebuild` は、初回だけ chroot を作るために base-devel をダウンロードします。手順 3 で wezterm-git を `[aur]` に移していても、`--rebuild` を付けるとビルドからやり直すので、chroot ビルドが通るかを確かめられます。ビルドが通ってインストールまで進めば成功です。
- `paru -Syu` の更新対象に `aur/` のパッケージが含まれていれば、更新のビルドも chroot を通ります。

## 5. 運用する

次の表は、chroot ビルドを運用するときに使うコマンドを並べたものです。説明は `man paru` の記述を訳しています。

| やりたいこと | コマンド | `man paru` の説明 |
| --- | --- | --- |
| chroot の中でシェルを開く | `paru -C` | `-C, --chrootctl` は chroot への対話シェルを開く |
| chroot の場所を表示する | `paru -Cp` | `-p, --print` は今の設定の chroot のパスを表示する |
| chroot の中を更新する | `paru -Cu` | `-u, --sysupgrade` は chroot を更新する |
| chroot にパッケージを常設する | `paru -Ci <パッケージ>` | `-i, --install` は master chroot にパッケージを入れる |
| ビルド 1 回だけ chroot にパッケージを足す | `paru -S <対象> --chrootpkgs <パッケージ>` | ビルドの前に chroot へ入れる。PKGBUILD が依存を宣言していないときに使う一時対処で、そのビルドにしか効かない |
| chroot を使わずにビルドする | `paru -S <対象> --nochroot` | chroot の中でビルドしない |
| ローカルリポジトリの中身を一覧する | `paru -Ll` | ローカルリポジトリにあるパッケージを一覧する |
| インストールしていないパッケージをリポジトリから消す | `paru -Lc` | 今インストールされていないパッケージをリポジトリから消す |

### PKGBUILD の depends 漏れでビルドが落ちたとき

chroot には base-devel と PKGBUILD が宣言した依存しか入らないので、PKGBUILD が依存を書き漏らしているとビルドが失敗します。これは対話環境でたまたま通っていた漏れが表に出た状態で、chroot としては正しい挙動です。まず `--chrootpkgs` で足りないパッケージを渡してビルドを通します。`man paru` はこの対処を一時的なものと位置づけていて、本来の対処は PKGBUILD を自分で直すか、メンテナに報告することです。

`--nochroot` は chroot を使わずに対話環境でビルドするので、この手順が閉じた漏れの経路がそのビルドだけ開きます。使うのは、chroot 側の問題を切り分けるときだけにしてください。

### chroot の置き場とディスクの掃除

`.config/paru/paru.conf` の `Chroot` にはパスを付けていないので、paru は既定の場所(paru のキャッシュ配下)に chroot を作ります。`man paru` と `man paru.conf` は既定のパスを明記していないので、実際の場所は `paru -Cp` で確かめてください。paru のキャッシュは `$XDG_CACHE_HOME/paru/` で、`XDG_CACHE_HOME` が未設定なら `~/.cache/paru` です(`man paru` の CACHE DIRECTORY)。

ディスクの使用量は次のコマンドで確かめます。chroot の中身は root が所有するので、`du` にも sudo が要ります。

```bash
sudo du -sh "$(paru -Cp)"
du -sh ~/.local/share/paru/repo
```

ディスクを空けるときの掃除の順序は次のとおりです。

1. `paru -Lc` で、インストールしていないパッケージをローカルリポジトリから消します。
2. `paru -Sc` で、キャッシュにあるビルド済みパッケージと追跡外のファイルを消します。`man paru` によると、VCS の取得済みソースは削除の対象外です。
3. chroot が壊れたときや作り直したいときは、`paru -Cp` が表示するディレクトリを `sudo rm -rf` で消します。chroot が無い状態は初回のビルドと同じなので、次の chroot ビルドで paru が chroot を作り直します。

## 範囲外 / Out of Scope

WSL2 機はこの手順の対象外です。makechrootpkg が使う systemd-nspawn が WSL2 で動く保証は無いので、`home.nix` は `profile == "native"` のときだけ `nix/modules/paru.nix` を読み込みます。WSL2 機に広げるときは、先に systemd-nspawn が動くかを別の作業で確かめてから、`profile == "wsl"` 側に import を足します(Issue #743 の 4 項目目)。

## 関連 / Related

- [tool-management-map.md](../reference/tool-management-map.md) - paru と devtools を OS 層が管理し、paru.conf だけを Nix が symlink する分担
- [nix-modules.md の paru.nix](../reference/nix-modules.md#parunix) - paru.conf を symlink するモジュール
- [install-unmanaged-tools.md](./install-unmanaged-tools.md) - OS 層のツールの導入
