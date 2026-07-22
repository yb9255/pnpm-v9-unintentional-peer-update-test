# pnpm auto-install-peers 동작 검증

pnpm 모노레포에서 `auto-install-peers=true`일 때, **아무도 선언하지 않은 패키지의 특정 major 버전이 어떻게 설치되고, 어떻게 peer 범위를 위반하면서까지 전체 워크스페이스로 번지는지**를 단독으로 증명하는 최소 재현이다. 이 폴더만으로 완결되며 외부 저장소·히스토리 참조가 필요 없다.

## 가설

- **H1**: peer 범위 병합(교집합)은 importer(워크스페이스) 단위로 일어난다 — 같은 importer 안에 상한 있는 범위가 하나라도 있으면 그 상한이 이긴다.
- **H2**: 상한 없는 peer 범위(`>=8` 등)만 가진 importer는 단독으로 최신 major를 선택한다.
- **H3 (drift)**: 일단 그래프에 들어온 버전은, 이후 **무관한 증분 재해석**에서 다른 importer로 번진다 — 그 importer의 peer 범위를 위반하더라도 경고만 내고 연결된다.

## 구조

```
.npmrc                     auto-install-peers=true, strict-peer-dependencies=false
pnpm-workspace.yaml        apps/*, lib/*
package.json               루트: eslint-config-next(peer eslint ^7||^8 — 상한 있음) + prettier 계열(>=7)
lib/ui-like/               eslint-plugin-import(^2..^9) + eslint-plugin-storybook(>=8 — 상한 없음)
apps/cra-like/             react-scripts 5 (+react 18) — 자체 의존성으로 peer를 충족하는 대조군
run-experiment.sh          전체 실험 자동 실행 + PASS/FAIL 판정
```

핵심 조건: **어느 워크스페이스에도 eslint 본체 선언이 없다.** pnpm 9.9.0 (packageManager 필드로 고정, corepack).

## 실행

```bash
./run-experiment.sh
```

스크립트가 하는 일:

1. **실험 1 (H1+H2)** — 락파일·node_modules를 지우고 신선한 전체 해석. 판정: 루트는 eslint **8.x**(교집합이 상한에 갇힘), ui-like는 **9.x**(상한 없음 → 최신 major). 같은 설치에서 두 버전이 공존한다.
2. **실험 2 (H3)** — ui-like에 eslint와 무관한 패키지(left-pad) 하나만 추가하고 재설치. 판정: 루트의 eslint-config-next가 자기 peer 범위(`^7||^8`)를 **위반하며 9.x로 끌려간다.** unmet peer 경고만 뜨고 설치는 성공한다.

2026-07-22 실행 결과: H1·H2·H3 모두 PASS (8.57.1 / 9.39.5 기준).

## 해석

- 교집합은 워크스페이스 경계를 넘지 못한다. **상한 없는 importer가 하나라도 있으면 최신 major의 진입(H2)을 막을 수 없다.**
- 진입한 버전은 증분 재해석 때 "그래프에 이미 있는 최고 버전을 범위 무시하고 재사용"하는 pnpm 내부 동작(`hoistPeers`의 `maxSatisfying(versions, '*')`) 때문에 다른 importer로 번진다(H3). 위반은 `strict-peer-dependencies=false`(기본값)에서 경고로 강등된다.
- 따라서 **차단법은 범위 협상이 아니라 공급이다**: peer로 요구되는 패키지를 소비하는 모든 워크스페이스에 구체 버전을 직접 선언하면(모노레포에선 pnpm catalog로 버전 단일화) auto-install이 개입할 틈 자체가 사라진다.

## 참고

- 최신 버전 숫자는 실행 시점의 레지스트리에 따라 달라진다 (eslint-plugin-import의 peer 상한이 `^9`라 10.x는 선택되지 않음). 스크립트는 major 단위로 판정하므로 결과는 재현된다.
- 재실행하면 스크립트가 스스로 초기 상태로 되돌린 뒤 시작한다. 실행 후 폴더는 실험 2 종료 상태(left-pad 포함, drift된 락파일)로 남는다.
