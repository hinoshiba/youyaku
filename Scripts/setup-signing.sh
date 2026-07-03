#!/bin/zsh
# Youyaku 用のローカル署名をセットアップする(一度だけ実行)。
#
# 背景: ad-hoc 署名アプリへの macOS の許可(アクセシビリティ等)はバイナリの
# ハッシュ(cdhash)に紐づくため、再ビルドのたびに無効化される。
# 自己署名証明書で署名すると「バンドルID + 証明書」に紐づくようになり、
# 何度ビルドし直しても許可が維持される。
#
# 実行の最後に macOS のパスワードダイアログが 1 回表示される(証明書の信頼設定)。
set -e

CERT_NAME="Youyaku Local Signing"
CONFIG_DIR="$HOME/.config/youyaku"
KEYCHAIN="$HOME/Library/Keychains/youyaku-codesign.keychain-db"
PASS_FILE="$CONFIG_DIR/keychain-pass"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "==> セットアップ済みです: $CERT_NAME"
    exit 0
fi

mkdir -p "$CONFIG_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> 1/5 自己署名コード署名証明書を生成"
cat > "$TMP/ext.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_codesign
prompt = no
[dn]
CN = $CERT_NAME
[v3_codesign]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
subjectKeyIdentifier = hash
EOF
# /usr/bin/openssl(LibreSSL)を明示使用。Homebrew の OpenSSL 3 だと
# pkcs12 のデフォルト暗号が新しすぎて security import が MAC エラーになる
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/ext.cnf" 2>/dev/null
cp "$TMP/cert.pem" "$CONFIG_DIR/codesign-cert.pem"   # 信頼を外す時のために保存

echo "==> 2/5 PKCS#12 に変換"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -out "$TMP/cert.p12" -passout pass:youyaku-tmp 2>/dev/null

echo "==> 3/5 専用キーチェーンを作成してインポート"
KC_PASS=$(/usr/bin/openssl rand -hex 16)
(umask 077; printf '%s' "$KC_PASS" > "$PASS_FILE")
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # 自動ロックしない
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P youyaku-tmp -T /usr/bin/codesign
security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null

echo "==> 4/5 キーチェーン検索リストへ追加(既存のリストは維持)"
# `security list-keychains -s` はリストを丸ごと置き換えるため、現在のリストへ追記する
current=("${(@f)$(security list-keychains -d user | sed 's/^ *"//; s/"$//')}")
if [[ ! " ${current[*]} " == *"$KEYCHAIN"* ]]; then
    security list-keychains -d user -s "$KEYCHAIN" "${current[@]}"
fi

echo "==> 5/5 コード署名として信頼(macOS のパスワードダイアログが 1 回出ます)"
security add-trusted-cert -p codeSign -p basic -k "$KEYCHAIN" "$CONFIG_DIR/codesign-cert.pem"

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$CERT_NAME"; then
    echo ""
    echo "==> 完了。次回の ./build.sh から自動的にこの署名が使われます。"
    echo "    署名切替後の初回のみ、アプリの「許可する」でアクセシビリティを許可し直してください。"
else
    echo "!! 署名 identity が有効になっていません(信頼設定がキャンセルされた可能性)" >&2
    exit 1
fi
