#!/usr/bin/env bash
set -euo pipefail

# ===== 설정 =====
PDF_FILE="${1:-Spaces.pdf}"
REMOTE_NAME="origin"
TARGET_BRANCH="main"
# =================

# 스크립트 위치 → 저장소 루트
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Git 저장소가 아닙니다: $SCRIPT_DIR"
  exit 1
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# 진행 중인 git 작업 차단
if [ -f .git/MERGE_HEAD ] || [ -d .git/rebase-apply ] || [ -d .git/rebase-merge ] \
   || [ -f .git/CHERRY_PICK_HEAD ] || [ -f .git/REVERT_HEAD ]; then
  echo "❌ 진행 중인 Git 작업(merge/rebase/cherry-pick/revert)을 먼저 정리하세요."
  exit 128
fi

# 파일 존재 확인
if [[ ! -f "$PDF_FILE" ]]; then
  echo "❌ 파일 없음: $REPO_ROOT/$PDF_FILE"
  exit 1
fi

# 브랜치 전환 (이미 main이면 그대로)
git fetch "$REMOTE_NAME"
git switch "$TARGET_BRANCH"

# 1) PDF 변경 먼저 커밋 (다른 변경은 그대로 둠)
if ! git diff --quiet -- "$PDF_FILE"; then
  # .gitignore에 막히면 강제 추가
  if git check-ignore -q -- "$PDF_FILE"; then
    git add -f -- "$PDF_FILE"
  else
    git add -- "$PDF_FILE"
  fi
  if ! git diff --cached --quiet -- "$PDF_FILE"; then
    git commit -m "Update $PDF_FILE [$(date +'%Y-%m-%d %H:%M:%S %z')]"
  fi
fi

# 2) PDF 외 변경이 있으면 임시 저장(stash)하되, PDF는 제외
NEEDS_STASH=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  # PDF를 제외하고 stash (pathspec exclude 사용)
  if git status --porcelain | awk '{print $2}' | grep -v -x "$PDF_FILE" | grep -q .; then
    NEEDS_STASH=1
    echo "ℹ️ PDF 외 변경을 임시 저장(stash)합니다."
    # Git 2.13+ 에서 pathspec exclude 문법 사용
    git stash push -u -m "auto-stash before pull $(date +'%F %T')" -- ":(exclude)$PDF_FILE" .
  fi
fi

# 3) 원격 최신 반영
git pull --rebase "$REMOTE_NAME" "$TARGET_BRANCH"

# 4) (pull 후) 혹시 PDF가 또 바뀌었으면 한 번 더 커밋
if ! git diff --quiet -- "$PDF_FILE"; then
  if git check-ignore -q -- "$PDF_FILE"; then
    git add -f -- "$PDF_FILE"
  else
    git add -- "$PDF_FILE"
  fi
  if ! git diff --cached --quiet -- "$PDF_FILE"; then
    git commit -m "Update $PDF_FILE [$(date +'%Y-%m-%d %H:%M:%S %z')]"
  fi
fi

# 5) 푸시
if git log "@{u}..HEAD" --oneline | grep -q .; then
  git push "$REMOTE_NAME" "$TARGET_BRANCH"
  echo "✅ Pushed to $TARGET_BRANCH: $PDF_FILE"
else
  echo "ℹ️ 원격과 동일: 푸시할 커밋이 없습니다."
fi

# 6) stash 복원
if [ "$NEEDS_STASH" -eq 1 ]; then
  git stash pop || true
  echo "ℹ️ stash 복원 완료(충돌 시 수동 해결 필요)."
fi

# 안내
REMOTE_URL="$(git remote get-url "$REMOTE_NAME" 2>/dev/null || true)"
echo "   remote: $REMOTE_URL"
echo "   branch: $TARGET_BRANCH"
