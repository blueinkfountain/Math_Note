#!/usr/bin/env bash
set -euo pipefail

## === 설정 ===
REPO_DIR="/Users/persist/Desktop/Pregraduate_Math_Notes"  # 레포 경로
PDF="${1:-Spaces.pdf}"                                    # ./upload.sh Foo.pdf 로 교체 가능
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"                  # 배포 브랜치(예: export PAGES_BRANCH=io)
VIEW_PAGE="${VIEW_PAGE:-1}"                               # 뷰 시작 페이지(기본 2페이지)
VIEW_ZOOM="${VIEW_ZOOM:-page-width}"                      # 뷰 줌(기본 page-width)
REWRITE_INDEX="${REWRITE_INDEX:-1}"                       # 1: index.html 덮어씀, 0: 건드리지 않음
## ==============

cd "$REPO_DIR"
git rev-parse --is-inside-work-tree >/dev/null

# 현재 작업 브랜치(없으면 main 가정)
CUR_BRANCH="$(git symbolic-ref --short -q HEAD || echo main)"
DEFAULT_BRANCH="$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')"
[[ -n "$DEFAULT_BRANCH" ]] || DEFAULT_BRANCH="main"

# 원격 정보 갱신
git fetch origin --prune >/dev/null 2>&1 || true

# (안전) 현재 브랜치가 없으면 기본 브랜치로 스위치
if ! git rev-parse --verify --quiet "$CUR_BRANCH" >/dev/null; then
  git switch -C "$DEFAULT_BRANCH" --track "origin/$DEFAULT_BRANCH" \
    || git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
  CUR_BRANCH="$DEFAULT_BRANCH"
fi

# 업스트림 보장(있으면 설정)
if git rev-parse --verify --quiet "refs/remotes/origin/$CUR_BRANCH" >/dev/null; then
  git branch --set-upstream-to="origin/$CUR_BRANCH" "$CUR_BRANCH" >/dev/null 2>&1 || true
fi

# 파일 체크
if [[ ! -f "$PDF" ]]; then
  echo "❌ 파일 없음: $PDF"
  exit 1
fi

# 변경 감지(HEAD blob vs 현재 파일)
HEAD_HASH="$(git ls-tree -r HEAD -- "$PDF" 2>/dev/null | awk '{print $3}' || true)"
CUR_HASH="$(git hash-object "$PDF")"
DID_COMMIT=0

if [[ "${HEAD_HASH:-}" != "$CUR_HASH" ]]; then
  echo "M       $PDF"
  git add -f -- "$PDF"                                  # 오직 PDF만 스테이징(README 등은 건드리지 않음)
  git commit -m "Update $PDF [$(date +'%Y-%m-%d %H:%M:%S %z')]" || true
  DID_COMMIT=1
else
  echo "ℹ️ $PDF 변경 없음(커밋 생략)"
fi

# 리베이스 풀 + 푸시(현재 브랜치 기준, 업스트림 없으면 -u로 설정)
git -c rebase.autostash=true pull --rebase origin "$CUR_BRANCH" 2>/dev/null || true
git push -u origin "$CUR_BRANCH" || true
[[ $DID_COMMIT -eq 1 ]] && echo "✅ pushed to $CUR_BRANCH: $PDF"

# --- GitHub Pages 배포 ---
# PDF가 바뀐 경우에만 자동 배포, 강제로 하려면 두번째 인자에 --deploy
if [[ $DID_COMMIT -eq 1 || "${2:-}" == "--deploy" ]]; then
  echo "🚀 Deploying $PDF to ${PAGES_BRANCH}…"
  git fetch origin --prune >/dev/null 2>&1 || true

  # worktree 절대경로
  SITE_DIR="$(cd "$REPO_DIR/.."; pwd)/_site"

  # 기존 worktree가 SITE_DIR에 묶여 있으면 제거 + prune (상태 일관성 확보)
  if git worktree list | awk '{print $1}' | grep -Fxq "$SITE_DIR"; then
    git worktree remove -f "$SITE_DIR" || true
  fi
  git worktree prune
  rm -rf "$SITE_DIR"

  # 배포 브랜치 준비: 원격에 있으면 트래킹, 없으면 orphan 생성
  if git ls-remote --exit-code --heads origin "$PAGES_BRANCH" >/dev/null 2>&1; then
    git worktree add -B "$PAGES_BRANCH" "$SITE_DIR" "origin/$PAGES_BRANCH" || {
      git worktree remove -f "$SITE_DIR" || true
      git worktree prune
      rm -rf "$SITE_DIR"
      git worktree add -B "$PAGES_BRANCH" "$SITE_DIR" "origin/$PAGES_BRANCH"
    }
  else
    git worktree add --orphan "$PAGES_BRANCH" "$SITE_DIR"
  fi

  SRC_SHA="$(git rev-parse --short HEAD)"

  (
    cd "$SITE_DIR"

    # 필요한 파일만 갱신 (README.md, CNAME 등은 그대로 유지)
    : > .nojekyll

    # index.html(옵션) — 2페이지부터 가로맞춤, 캐시버스트 ?v=${SRC_SHA}
    if [[ "$REWRITE_INDEX" == "1" ]]; then
      cat > index.html <<HTML
<!doctype html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${PDF}</title>
<style>html,body{margin:0;height:100%}iframe{border:0;width:100%;height:100vh}</style>
</head><body>
<iframe src="${PDF}?v=${SRC_SHA}#page=${VIEW_PAGE}&zoom=${VIEW_ZOOM}"></iframe>
</body></html>
HTML
      git add -f -- index.html
    fi

    # PDF만 덮어쓰기(동일 파일이어도 조용히 통과)
    cp -f "${REPO_DIR}/${PDF}" "./" 2>/dev/null || true
    git add -f -- "${PDF}" .nojekyll

    if ! git diff --quiet --staged; then
      git commit -m "Deploy ${PDF} (${SRC_SHA}) $(date +%F' '%T)"
      git push -u origin "$PAGES_BRANCH"
      echo "✅ Pages pushed → branch: ${PAGES_BRANCH}"
    else
      echo "ℹ️ Pages 변경 없음(커밋 생략)"
    fi
  )

  # 깔끔한 Pages URL 출력 (git@ / https 모두 대응)
  REMOTE_URL="$(git remote get-url origin)"
  case "$REMOTE_URL" in
    https://github.com/*) PATH_PART="${REMOTE_URL#https://github.com/}" ;;
    git@github.com:*)     PATH_PART="${REMOTE_URL#git@github.com:}" ;;
    *)                    PATH_PART="${REMOTE_URL##*/}" ;;
  esac
  PATH_PART="${PATH_PART%.git}"
  OWNER="${PATH_PART%%/*}"
  REPO_NAME="${PATH_PART#*/}"
  echo "🔗 Pages index : https://${OWNER}.github.io/${REPO_NAME}/?v=${SRC_SHA}"
  echo "🔗 PDF direct  : https://${OWNER}.github.io/${REPO_NAME}/${PDF}?v=${SRC_SHA}#page=${VIEW_PAGE}&zoom=${VIEW_ZOOM}"
else
  echo "ℹ️ 배포 생략(새 ${PDF} 커밋 없음). 강제 배포: $0 ${PDF} --deploy"
fi
