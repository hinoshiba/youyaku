# CI ベースライン

`ci-check.py` が比較に使う、モデルごとの基準値(`<model>.json`)を置く場所。

**必ず CI(GitHub Actions)上で採ること。** CPU とローカル Metal ではトークンが
変わるので、ローカルで作った値を置くと誤検知する。採り方は ../README.md の
「初回セットアップ」を参照。
