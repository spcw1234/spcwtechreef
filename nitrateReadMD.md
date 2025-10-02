# 질산염(Nitrate) 기능 개발 요약

본 문서는 spcwtechreef 앱의 질산염 센서/스마트 도징 관련 개발 과정을 요약합니다. 개요 → 핵심 컴포넌트 → 자동화 로직 → 안전장치 → UI/UX → 데이터 보관 및 삭제 → 향후 과제로 구성되어 있습니다.

## 개요
- 목표: 질산염(ppm) 자동 관리. 실시간 측정, 장기 추세 분석(기울기/적분), 스마트 도징 스케줄 자동 보정, 안전한 보호장치(클램프), 사용성 높은 UI 제공.
- 기술 스택: Flutter(Provider), MQTT 통신, Local DB(SQLite via sqflite), SharedPreferences, fl_chart.

## 핵심 컴포넌트
- DeviceProvider (`lib/device_provider.dart`)
  - 센서 메시지 수신, 상태 관리, 스마트 도징 계산/스케줄 조정.
  - NitrateInfo: ppm, gradients(실시간/장기), integral(적분), clamp 상태, 모델 품질, 분석 커버리지 등.
  - DOSE 스케줄 CRUD 및 충돌 회피/쿨다운 분할 로직.
- History Service (`lib/nitrate_history_service.dart`)
  - DB 스키마 및 CRUD, 기간 조회, 평균 계산, 보관기간 삭제, 전체 삭제(clearAllData).
- UI
  - `lib/nitrate_settings_screen.dart`: 메인 설정/상태 + 스마트 도징 카드(상세 진입, 적분 그래프 버튼).
  - `lib/nitrate_graph_screen.dart`: 일반 히스토리 그래프(ppm/전압/온도) + 삭제 버튼.
  - `lib/nitrate_analysis_graph_screen.dart`: 분석 그래프(적분/기울기/모델/클램프) + 삭제 버튼.
  - `lib/smart_dosing_detail_screen.dart`: 스케줄 상세/수동 테스트/선택 저장/지표 칩.

## 자동화 로직(스마트 도징)
- 장기 평균 기울기(ppm/h) 기반 자동 보정:
  - 분석 창: 설정 `smartAnalysisHours` (기본 6h).
  - 임계: 설정 `smartGradientThreshold` (기본 0.5ppm/h).
  - 도징 레벨링: |기울기| 크기에 따라 ±1/±2/±3 ml 매핑, 부호는 목표 방향으로.
  - 쿨다운: `smartCooldownSeconds` (기본 2h) 동안 재조정 제한.
  - 최대 펌프 시간 cap: `smartMaxDosingMs` (예: 2000~3000ms).
- 스케줄 조정 방식:
  - 마지막 스케줄 가감, cap 초과분은 쿨다운 간격으로 분할 생성.
  - 충돌 회피: 동일 분의 중복 방지를 위해 최대 1440분 탐색하여 빈 시간대 배치.
- 올리고트로피(저농도) 안내:
  - 스케줄이 없고 장기 기울기 음수 임계 이하이면 안내 메시지 표시(과도한 제거 방지 안내).

## 안전장치(클램프/적분)
- 적분값(누적 드리프트) 기반 보호:
  - “ppm 드리프트 누적임계”를 초과 시 Clamp ACTIVE.
  - ACTIVE 동안 자동 스케줄 보정 일시 중지, 적분 누적 동결.
- 해제 조건: 일정 시간 안정화 또는 적분값 정상화(구현에 따라).

## UI/UX 개선 포인트
- 스마트 도징 카드:
  - 장치/펌프 선택 요약, 스케줄 목록, 펌프 토글 및 테스트 조정 버튼.
  - 상세 설정 진입 버튼과 “적분 그래프” 버튼 배치.
- 상세 화면:
  - 실시간/평균 기울기 칩, 분석 창 커버리지/남은 시간, Clamp 상태.
  - 장치/펌프 선택 즉시 저장(Provider + SharedPreferences), 변경 시 스케줄 재요청.
- 그래프 화면 상단 우측에 삭제 버튼 추가(복구 불가 경고 다이얼로그 포함).

## 데이터 보관 및 삭제
- 보관 정책: 기본 30일 초과 데이터 자동 정리(`deleteOldData`).
- 전체 삭제: 화면 AppBar의 삭제 버튼 → 경고 → `NitrateHistoryService.clearAllData(deviceId)` → 재로딩.

## 개발 중 주요 이슈와 해결
- await 비동기 핸들러 오류: onChanged 내 await 사용 → handler를 async로 변경.
- 스케줄 충돌 및 분할 시점: cap 사이즈 조각은 쿨다운 간격으로 분산, 분 단위 충돌 회피 스캔 추가.
- 설정-로직 연동: 사용자 설정값을 Provider의 계산 파이프라인에 반영(smart* 설정).

## 향후 과제
- 아이콘 생성(flutter_launcher_icons) 마무리.
- Clamp 해제 히스테리시스/표시 개선.
- 분석/예측 모델 고도화 및 알림(임계 초과 이벤트).

---
본 문서는 질산염 자동화/시각화 기능의 구조와 사용법을 효율적으로 파악할 수 있도록 요약한 자료입니다. 개선/보완 사항은 PR이나 이슈로 제안해 주세요.
