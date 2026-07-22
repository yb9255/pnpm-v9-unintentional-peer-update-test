#!/bin/bash
# =============================================================================
# pnpm auto-install-peers 동작 검증 실험
# =============================================================================
#
# [무대]
#   이 모노레포에는 워크스페이스 폴더가 3개 있고, 어디에도 "eslint를 설치하라"고
#   적혀 있지 않다. 대신 각 폴더가 설치하는 플러그인들이 "나 eslint 필요해"
#   (peerDependency)라고 요구만 하는데, 허용 범위가 폴더마다 다르다:
#
#     루트           eslint-config-next      → "eslint 7 아니면 8만 돼"  (^7||^8, 9 금지)
#     lib/ui-like    eslint-plugin-storybook → "8 이상이면 뭐든 돼"      (>=8, 상한 없음)
#     apps/cra-like  react-scripts           → 자기가 eslint ^8을 직접 들고 있는 대조군
#
#   .npmrc의 auto-install-peers=true 때문에, pnpm이 이 요구들을 보고 eslint
#   버전을 "알아서" 골라 설치해 준다. 이 실험의 질문은 하나다:
#   → pnpm은 도대체 몇 버전을 골라주는가?
#
# [가설] (H = Hypothesis, 가설)
#   H1. 한 폴더 안의 요구 범위는 지켜진다.
#       → 루트는 "9 금지"라고 했으니 8이 설치될 것이다.
#   H2. 상한 없는 폴더는 그 시점의 최신 버전을 받는다.
#       → ui-like는 "8 이상 아무거나"이므로 9가 설치될 것이다.
#       → 결과적으로 같은 설치 안에 eslint 8과 9가 공존하게 된다.
#   H3. (drift) 재설치 때 pnpm은 범위를 다시 협상하지 않고,
#       "이미 저장소에 있는 것 중 제일 높은 버전"을 가져다 붙인다.
#       → ui-like에 eslint와 무관한 패키지 하나만 추가하고 재설치하면,
#         루트가 "9 금지" 규칙을 위반한 채 9로 바뀔 것이다. (위반은 경고 한 줄)
#
# [사용법]
#   ./run-experiment.sh
#   - 1~2분 소요 (전체 재설치부터 시작하므로)
#   - 몇 번을 재실행해도 된다: 시작할 때 스스로 초기 상태로 되돌린다
#   - 마지막에 "H1·H2·H3 모두 PASS"가 나오면 성공, 중간 FAIL 시 그 자리에서 중단
# =============================================================================

set -e                    # 어떤 판정이든 실패하면 즉시 중단
cd "$(dirname "$0")"      # 어디서 실행하든 이 스크립트가 있는 폴더 기준으로 동작

# -----------------------------------------------------------------------------
# 헬퍼: 각 폴더가 "어떤 eslint에 연결됐는지"를 락파일에서 읽는다.
#
# pnpm-lock.yaml에는 플러그인마다 어느 eslint와 연결됐는지가 괄호 표기로 남는다.
#   예) version: 12.3.1(eslint@8.57.1)(typescript@4.8.3)
# 아래 함수들은 그 괄호 안의 eslint@x.y.z 부분만 뽑아낸다.
# -----------------------------------------------------------------------------
root_eslint() {
  # 루트의 eslint-config-next("9 금지"인 플러그인)가 물린 eslint 버전
  grep -A3 'eslint-config-next:' pnpm-lock.yaml \
    | grep -oE 'eslint@[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
ui_eslint() {
  # ui-like의 eslint-plugin-storybook("8 이상 아무거나"인 플러그인)이 물린 eslint 버전
  grep -A3 'eslint-plugin-storybook:' pnpm-lock.yaml \
    | grep -oE 'eslint@[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# =============================================================================
# 실험 1 — 맨바닥에서 설치하면 pnpm은 폴더마다 몇 버전을 골라주는가? (H1 + H2)
# =============================================================================
echo "=== 실험 1: 맨바닥 설치 — 폴더별로 어떤 eslint가 골라지나 (H1 + H2) ==="

# 이전 실행의 흔적을 모두 제거해 완전히 처음 상태로 만든다
rm -rf node_modules apps/*/node_modules lib/*/node_modules pnpm-lock.yaml

# 실험 2가 추가하는 left-pad가 남아 있다면 제거 (재실행 대비 기준 상태 보장)
perl -0pi -e 's/\s*"left-pad": "\^1\.3\.0",//' lib/ui-like/package.json

# 전체 설치. pnpm이 eslint 버전을 스스로 고르는 순간이다
pnpm install --no-frozen-lockfile > /dev/null 2>&1

ROOT1=$(root_eslint)
UI1=$(ui_eslint)
echo "  루트    (\"7 아니면 8만 돼\")   → $ROOT1"
echo "  ui-like (\"8 이상이면 뭐든 돼\") → $UI1"

# H1 판정: 루트는 자기 요구대로 8.x를 받았는가?
case "$ROOT1" in
  eslint@8.*) echo "  H1 PASS: 한 폴더 안의 요구 범위는 지켜진다 — 루트에 9가 아닌 8이 설치됨" ;;
  *)          echo "  H1 FAIL: 루트에 $ROOT1 이 설치됨"; exit 1 ;;
esac

# H2 판정: 상한 없는 ui-like는 최신 9.x를 받았는가?
case "$UI1" in
  eslint@9.*) echo "  H2 PASS: 상한 없는 폴더는 최신을 받는다 — ui-like에 9가 설치됨" ;;
  *)          echo "  H2 FAIL: ui-like에 $UI1 이 설치됨"; exit 1 ;;
esac

echo "  → 같은 설치 안에 eslint 두 버전이 공존하는 상태가 됐다:"
ls node_modules/.pnpm | grep -E '^eslint@' | sed 's/^/      /'

# =============================================================================
# 실험 2 — 이 상태에서 무관한 변경 하나가 일어나면? (H3: drift)
# =============================================================================
echo ""
echo "=== 실험 2: ui-like에 eslint와 무관한 패키지(left-pad) 1개 추가 후 재설치 (H3) ==="

# ui-like의 package.json에 left-pad 한 줄을 추가한다.
# left-pad는 문자열 패딩 유틸로, eslint와 아무 관련이 없다.
# 실제 상황으로 치면 "다른 폴더에서 아무 패키지나 하나 설치한 커밋"에 해당한다.
perl -0pi -e 's/"eslint-plugin-import"/"left-pad": "\^1.3.0",\n    "eslint-plugin-import"/' \
  lib/ui-like/package.json

# 재설치 — 이때 pnpm은 영향받은 부분을 다시 해석한다
pnpm install --no-frozen-lockfile > /dev/null 2>&1

ROOT2=$(root_eslint)
echo "  루트    (\"7 아니면 8만 돼\")   → $ROOT2"

# H3 판정: 루트가 자기 규칙("9 금지")을 위반하며 9로 바뀌었는가?
case "$ROOT2" in
  eslint@9.*)
    echo "  H3 PASS: 루트가 자기 요구 범위를 위반한 채 9로 끌려갔다"
    echo "           (pnpm이 범위를 재협상하지 않고, 이미 있는 최고 버전을 가져다 붙임."
    echo "            이 위반은 설치 실패가 아니라 unmet peer 경고 한 줄로 끝난다)" ;;
  *)
    echo "  H3 FAIL: 루트가 $ROOT2 를 유지함"; exit 1 ;;
esac

# =============================================================================
# 결론
# =============================================================================
echo ""
echo "=== 결론: H1·H2·H3 모두 PASS ==="
echo "① 상한 없는 요구를 가진 폴더가 하나라도 있으면 최신 버전의 '진입'을 막을 수 없다 (H2)"
echo "② 일단 들어온 버전은 무관한 재설치 한 번에 다른 폴더까지 규칙을 어기며 번진다 (H3)"
echo "→ 차단법: pnpm에게 고르게 시키지 말 것."
echo "  peer로 요구되는 패키지는 소비하는 모든 워크스페이스에 구체 버전을 직접 선언한다."
echo "  (모노레포에서는 pnpm catalog로 버전을 한 곳에서 관리)"
