# CA の信頼ストアを確かめる / Verify CA Trust Stores

> **Diátaxis:** 🔧 How-to

CA の事故(ルート CA や中間 CA の鍵漏洩、大量の失効)が起きたときに、この環境の各 TLS クライアントが問題のチェーンを拒否するかを確かめる手順です。どのツールがどの束を読むかという設計は [tool-management-map.md の「CA 信頼ストアの管轄」](../reference/tool-management-map.md#ca-信頼ストアの管轄--ca-trust-store-authority) に書いてあります。この手順は 2026-10 の eMudhra 中間 CA 鍵漏洩(Issue #738)で実際に使いました。

## 前提 / Prerequisites

- 事故の報告元が、問題のチェーンで証明書を出す checker ホストを公開していることを前提にします。2026-10 の事故では `https://dv-g3b-emudhra.we-have-a-problem.com/` と `https://dv-g3b-aaa-emudhra.we-have-a-problem.com/` が使えました。以下では `$CHECKER` と書きます。
- 判定の読み方は 1 つだけです。接続が証明書エラーで失敗すればそのクライアントは安全側にいて、HTTP 応答が返ればそのクライアントは問題のチェーンを信頼しています。

## 1. システムの信頼ストアを更新して確かめる

```bash
sudo pacman -Syu ca-certificates-mozilla
trust list --filter=certificates | grep -A2 'label: <問題のルートの名前>'
grep -c 'BEGIN CERT' /etc/ssl/certs/ca-certificates.crt
```

pacman の hook が `update-ca-trust` を実行し、`/etc/ssl/certs/ca-certificates.crt` と `/etc/ssl/certs/java/cacerts` を作り直します。削除されたルートは `trust list` に出なくなり、TLS 用途の信頼だけを外されたルートは `trust dump` で `trust-server-auth: nss-trust-unknown` と表示されるのが目印です。

## 2. OpenSSL を読むクライアントを確かめる

curl・git・openssl・python・go・mise・rustup・uv は `SSL_CERT_FILE` 経由でシステムの束を読むので、手順 1 が済めばまとめて拒否に変わります。

```bash
curl -sS -o /dev/null "$CHECKER"; echo "exit=$?"                          # 60 なら拒否
git ls-remote "$CHECKER"                                                  # 「SSL certificate ... (20)」なら拒否
python3 -c "import urllib.request; urllib.request.urlopen('$CHECKER')"   # CERTIFICATE_VERIFY_FAILED なら拒否
```

## 3. 自前の束を持つランタイムを確かめる

node・deno・awscli・pip・gcloud は `SSL_CERT_FILE` を読みません。`home.nix` の `home.sessionVariables` が宣言するツール固有の変数が効いているかを、新しいシェルで確かめます。

```bash
# node(mise)。NODE_OPTIONS=--use-openssl-ca が効いていれば UNABLE_TO_GET_ISSUER_CERT_LOCALLY になる
node -e "fetch('$CHECKER').then(()=>console.log('TRUSTED')).catch(e=>console.log(e.cause?.code||e.message))"

# deno(cargo)。DENO_TLS_CA_STORE=system が効いていれば client error (Connect) になる
deno eval "try{await fetch('$CHECKER');console.log('TRUSTED')}catch(e){console.log(e.message)}"

# awscli(mise)。AWS_CA_BUNDLE が効いていれば SSL validation failed になる
aws --no-sign-request --endpoint-url "$CHECKER" s3 ls

# pip(mise の python)。環境変数では変わらないので、pip 本体を修正版に上げてから確かめる
python -m pip install -U pip
python -m pip download --no-deps -d /tmp/pipchk --index-url "${CHECKER}simple/" nonexistent-pkg-xyz
```

gcloud は `gcloud info --run-diagnostics` が通ることで、`CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE` の束のまま Google のエンドポイントに到達できることを確かめます。gcloud を checker に向ける手段は、認証トークンを checker に送ってしまうので使いません。

## 4. ブラウザと Electron アプリを確かめる

Vivaldi と Chromium は Chrome Root Store と CRLSet で判断します。checker を開いて証明書エラーのページになれば拒否している、という読み方です。CRLSet が更新されているかは、プロファイルの `CertificateRevocation/<番号>/manifest.json` の更新日時で確かめてください。

Electron アプリは Chrome Root Store を内蔵していて、CRLSet の更新も受け取りません。確かめ方は、アプリが Electron をどう持っているかで分かれます。pacman の electron パッケージに乗るアプリ(`pacman -Qi electronNN` の Required By に出るもの)は、その electron を直接起こせば実機そのものを試せます。

```bash
cat > /tmp/electron_check.js <<'JS'
const { app, net } = require('electron');
app.whenReady().then(async () => {
  for (const u of process.argv.slice(2)) {
    try { const r = await net.fetch(u); console.log(u, '-> HTTP', r.status, 'TRUSTED'); }
    catch (e) { console.log(u, '->', e.message); }
  }
  app.quit();
});
JS
electron43 --disable-gpu /tmp/electron_check.js "$CHECKER"   # ERR_CERT_REVOKED なら拒否
pacman -Qi electron43 | grep 'Required By'                    # どのアプリがこの electron に乗っているか
```

Electron を同梱するアプリ(Discord・Slack・Claude Desktop・ClickUp など)は、同梱の Electron をベンダーが決めているので、Arch や AUR の側では差し替えられません。確かめ方は、版を読む・実機で叩く・バイナリを読む、の 3 段です。

まず、バイナリから `Electron/x.y.z` を読み、Electron の advisory が示す修正版(2026-10 の事故では GHSA-jr5w-w6x2-84p9 の 44.9.1 / 43.8.1 / 42.11.16)と比べます。修正はパッチ版で入るので、43.7.x と 43.8.x のように同じメジャーでも結果が変わります。同じメジャーの electron パッケージを起こす代理テストは目安にとどめてください。Discord のように自己更新するアプリは、パッケージではなく `~/.config/discord/app-*/Discord` のような実体を読んでください。

```bash
grep -aoE 'Electron/[0-9]+\.[0-9]+\.[0-9]+' /usr/lib/slack/slack /usr/lib/claude-desktop/claude-desktop /opt/clickup/ClickUp ~/.config/discord/app-*/Discord 2>/dev/null
```

次に、確定させたいアプリは同梱の実行ファイルそのもので checker を叩きます。アプリのディレクトリを影コピー(実行ファイルだけ複製し、ほかはシンボリックリンク)して、`resources/app.asar` を自前の checker アプリに差し替えて起こすと、同梱の Electron がそのまま動きます。`OnlyLoadAppFromAsar` fuse が有効なアプリでも、asar で渡せば読まれます。userData は影コピーの中に向けて、本物の設定に触らないようにしてください。

```bash
# 1) checker アプリを asar に詰める(Chromium 側の net.fetch と Node 側の https を両方試す)
S=/tmp/cachk/shadow; mkdir -p "$S/resources" "$S/userdata"
cat > /tmp/cachk/main.js <<'JS'
const { app, net } = require('electron');
const https = require('https');
if (process.env.CACHK_USERDATA) app.setPath('userData', process.env.CACHK_USERDATA);
const nodeGet = (u) => new Promise((res) => https.get(u, (r) => { res(`HTTP ${r.statusCode} TRUSTED`); r.resume(); }).on('error', (e) => res(e.code || e.message)));
app.whenReady().then(async () => {
  console.log('[versions] electron', process.versions.electron);
  for (const u of process.argv.slice(1).filter((a) => a.startsWith('https://'))) {
    try { const r = await net.fetch(u); console.log('[chromium]', u, '-> HTTP', r.status, 'TRUSTED'); }
    catch (e) { console.log('[chromium]', u, '->', e.message); }
    console.log('[node https]', u, '->', await nodeGet(u));
  }
  app.quit();
});
JS
echo '{"name":"cachk","version":"1.0.0","main":"main.js"}' > /tmp/cachk/package.json
python3 - "$S/resources/app.asar" /tmp/cachk/main.js /tmp/cachk/package.json <<'PY'
import json, struct, sys, pathlib
out, entries, blobs, off = pathlib.Path(sys.argv[1]), {}, [], 0
for f in sys.argv[2:]:
    b = pathlib.Path(f).read_bytes(); entries[pathlib.Path(f).name] = {"size": len(b), "offset": str(off)}; off += len(b); blobs.append(b)
hdr = json.dumps({"files": entries}).encode(); pad = (4 - len(hdr) % 4) % 4
payload = struct.pack("<I", len(hdr)) + hdr + b"\0" * pad
header = struct.pack("<I", len(payload)) + payload
out.write_bytes(struct.pack("<II", 4, len(header)) + header + b"".join(blobs))
PY

# 2) 影コピーを作って起こす(例は Claude Desktop。ClickUp は APP=/opt/clickup BIN=ClickUp、Discord は APP=~/.config/discord/app-<版> BIN=Discord に読み替える)
APP=/usr/lib/claude-desktop; BIN=claude-desktop
for f in "$APP"/*; do n=$(basename "$f"); case "$n" in resources) ;; "$BIN") cp -f "$f" "$S/$n";; *) ln -sfn "$f" "$S/$n";; esac; done
for f in "$APP"/resources/*; do n=$(basename "$f"); case "$n" in app|app.asar|app.asar.unpacked) ;; *) ln -sfn "$f" "$S/resources/$n";; esac; done
CACHK_USERDATA=$S/userdata "$S/$BIN" --no-sandbox --disable-gpu --user-data-dir="$S/userdata" "$CHECKER" https://www.google.com/ 2>&1 | grep '^\['
```

checker が `HTTP 200 TRUSTED` で返れば、そのアプリは同梱の Electron ごと修正前です。`ERR_CERT_AUTHORITY_INVALID` や `ERR_CERT_REVOKED` で止まれば拒否しています。通常サイトが 200 で返ることも一緒に見て、checker の失敗がネットワークのせいでないことを確かめてください。

最後に、修正の有無はバイナリを読むだけでも分かります。Electron の修正は root を削るのではなく、中間 CA の SPKI の SHA-256 をブロックリストに焼き込む形なので、root「emSign ECC Root CA - G3」の DER は修正版の electron にも残っています。root の有無で判定しないでください。checker の chain から中間 CA の SPKI ハッシュ(生の 32 バイト)を計算し、それがバイナリにあれば修正版、無ければ修正前と読めます。

```bash
H=${CHECKER#https://}; H=${H%%/*}
openssl s_client -connect "$H:443" -servername "$H" -showcerts </dev/null 2>/dev/null \
  | awk '/BEGIN CERT/{n++} n==2' | openssl x509 -noout -pubkey \
  | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary > /tmp/cachk/spki.bin
python3 -c 'import sys, pathlib; k = pathlib.Path(sys.argv[1]).read_bytes()
for b in sys.argv[2:]: print(b, "patched (blocklist entry present)" if k in pathlib.Path(b).read_bytes() else "not patched")' \
  /tmp/cachk/spki.bin /usr/lib/electron43/electron /usr/lib/claude-desktop/claude-desktop /usr/lib/slack/slack /opt/clickup/ClickUp
```

## 5. Nix の cacert を参照するパッケージを洗い出す

```bash
nix-store -q --requisites ~/.nix-profile | grep nss-cacert
nix-store -q --referrers /nix/store/<hash>-nss-cacert-<version> | grep -v '\.drv$'
nix eval --raw github:NixOS/nixpkgs/nixos-unstable#cacert.version
```

ここに出たパッケージ(gcloud・copilot-cli・Python の certifi など)は、nixpkgs の channel が新しい cacert に追従するまで古い束を持ち続けます。手順 3 の変数で束を差し替えられるものは差し替え、残りは channel の版が上がってから `mise run nix:update` で追従させる、という二段構えです。

## トラブルシューティング / Troubleshooting

- **node に `--use-system-ca` を付けても信頼したまま**: `--use-system-ca` は同梱の束に OS の束を追加する動きなので、同梱の束にある問題のルートは消えません。同梱の束を捨てて OS の束に置き換える `--use-openssl-ca` を使います。
- **mise の mirror 設定を checker に向けても `mise ls-remote` が成功する**: `ls-remote` は版の一覧をキャッシュから読むので mirror に接続しません。`mise install node@<版>` で実際のダウンロードを起こすと判定できます。
- **pip に `--cert` や `PIP_CERT` を渡しても信頼したまま**: 2026-10 の実測では pip 26.1.2 がどの指定でも問題のチェーンを通し、原因は特定できていません。pip 26.2.2 に上げると拒否に変わりました。
- **Vivaldi で checker を開いても証明書エラーのページにならない**: CRLSet が古い可能性があります。`vivaldi://components`(Chromium では `chrome://components`)で CRLSet を更新してから開き直します。
