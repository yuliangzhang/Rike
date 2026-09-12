#!/usr/bin/env bash
# 一次性脚本：把 codex 原始 stdout 转录从 git 历史里摘掉。
#
# 为什么需要它：`git rm --cached` 只让**新提交**不再包含这些文件，
# 旧提交里的 blob 仍然在历史中、推上去照样公开。仓库还没推过，现在改零代价。
#
# 原始历史保留在 backup-before-purge 分支上，确认无误后再删。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

LOGS="docs/_r3_stdout.log docs/_r4_stdout.log docs/_r5_stdout.log docs/_r6_stdout.log docs/_r7_stdout.log"

echo "==> 改写 main 的历史（backup-before-purge 分支保持原样）"
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f \
  --index-filter "git rm --cached --ignore-unmatch -q $LOGS" \
  --prune-empty main

echo
echo "==> 核对：历史里还剩多少这类 blob"
git rev-list --objects main \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
  | awk '$1=="blob" && $4 ~ /_r[0-9]_stdout\.log/ {s+=$3; n++}
         END {printf "    main 历史中剩余 %d 个 blob，共 %.1f MB（应为 0）\n", n, s/1048576}'

echo
echo "==> 本地文件是否还在（它们应该还在，只是不再被跟踪）"
ls -1 docs/_r*_stdout.log 2>/dev/null | sed 's/^/    /' || echo "    （无）"

echo
echo "确认上面「剩余 0 个 blob」之后，执行下面两步收尾并推送："
echo "    git branch -D backup-before-purge && rm -rf .git/refs/original && git reflog expire --expire=now --all && git gc --prune=now"
echo "    git push -u origin main"
