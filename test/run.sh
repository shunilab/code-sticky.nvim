#!/usr/bin/env bash
# code-sticky.nvim テストランナー。test/test_*.lua を nvim --headless で実行する。
# amnesia.vim/test/run.sh と同じ流儀: 未捕捉エラーで黙って PASS 扱いにしないよう、
# 各テストの成否は終了コードと標準出力の両方で確認する。
set -uo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

if ! command -v nvim >/dev/null 2>&1; then
    echo "skip: nvim not found"
    exit 0
fi

echo "== running with nvim ($(nvim --version | head -1)) =="

overall_status=0

for test_file in test/test_*.lua; do
    out="$(nvim --headless -u NONE -i NONE \
        -c "set rtp+=${REPO_ROOT}" \
        -c "runtime plugin/code-sticky.lua" \
        -c "luafile ${test_file}" 2>&1)"
    status=$?

    if [ "$status" -ne 0 ] || ! grep -q "^PASS$" <<<"$out"; then
        echo "FAIL: ${test_file}"
        echo "$out" | sed 's/^/    /'
        overall_status=1
    else
        echo "PASS: ${test_file}"
    fi
done

exit $overall_status
