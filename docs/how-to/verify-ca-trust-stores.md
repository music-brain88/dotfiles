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

Electron を同梱するアプリ(Discord・Slack・Claude Desktop など)は、バイナリから `Electron/x.y.z` を読み、Electron の advisory が示す修正版(2026-10 の事故では 44.9.1 / 43.8.1 / 42.11.16)と比べて判定します。同じメジャーの electron パッケージを起こすテストは目安にしかなりません。修正はパッチ版で入るので、43.7.x と 43.8.x のように同じメジャーでも結果が変わります。版が読めないか修正版と比べられないアプリは「未検証」と記録し、安全側に数えないでください。

```bash
grep -aoE 'Electron/[0-9]+\.[0-9]+\.[0-9]+' /opt/discord/Discord /usr/lib/slack/slack /usr/lib/claude-desktop/claude-desktop 2>/dev/null
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
