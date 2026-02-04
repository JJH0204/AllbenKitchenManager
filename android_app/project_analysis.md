# KDS(Kitchen Display System) Project Analysis Report

본 보고서는 현재 개발 중인 Flutter 기반 PC방 주방 관리 시스템(KDS)의 구조와 기술 스택을 분석한 결과입니다.

## 1. 전체 프로젝트 구조 (`lib/`)

프로젝트는 명확한 관심사 분리를 위해 기능별 폴더 구조를 채택하고 있습니다.

- **`models/`**: 데이터의 구조를 정의하는 클래스들이 위치합니다. (`MenuInfo`, `OrderInfo`)
- **`providers/`**: 앱의 상태 관리 및 비즈니스 로직을 담당하는 Provider 클래스가 위치합니다. (`KitchenProvider`)
- **`services/`**: 외부 시스템(서버, 로컬 저장소)과의 통신을 담당하는 서비스 계층입니다. (`ApiService`, `WebSocketService`, `StorageService`)
- **`ui/`**: 사용자 인터페이스를 담당하며, `screens`(전체 화면)와 `widgets`(재사용 가능한 컴포넌트)으로 나뉩니다.
- **`utils/`**: 프로젝트 전반에서 공통으로 사용되는 유틸리티 함수들이 위치합니다. (`HangulUtils` 등)

## 2. 상태 관리 및 디자인 패턴

- **상태 관리 라이브러리**: `Provider` (version ^6.1.1)
  - `ChangeNotifier`와 `ChangeNotifierProvider`를 사용하여 데이터 변화를 감지하고 UI를 갱신합니다.
- **디자인 패턴**: **MVVM (Model-View-ViewModel)** 패턴과 유사한 **Provider Pattern**을 따르고 있습니다.
  - **Model**: `models/` 내의 데이터 클래스.
  - **View**: `ui/` 내의 Flutter 위젯들.
  - **ViewModel (Provider)**: `KitchenProvider`가 상태 데이터와 UI 로직을 결합하여 중재자 역할을 수행합니다.

## 3. 주요 외부 라이브러리 (Dependencies)

`pubspec.yaml` 파일을 통해 확인된 주요 의존성은 다음과 같습니다.

| 분류 | 라이브러리 | 용도 |
| :--- | :--- | :--- |
| **상태 관리** | `provider` | 앱 전역 상태 관리 및 의존성 주입 |
| **데이터 통신** | `http`, `web_socket_channel` | REST API 통신 및 실시간 주문 업데이트용 웹소켓 |
| **이미지/캐시** | `cached_network_image`, `flutter_cache_manager` | 서버 이미지의 효율적인 로딩 및 캐싱 |
| **데이터 보관** | `shared_preferences`, `path_provider` | 서버 IP/Port 설정값 및 로컬 데이터 저장 |

## 4. 데이터 모델(Model)과 UI의 연결 관계

이 프로젝트에서 데이터는 **단방향 데이터 흐름**과 **이벤트 기반 업데이트**를 통해 UI와 연결됩니다.

1.  **데이터 수신**: `WebSocketService`를 통해 실시간 주문(`ORDER_CREATE`)이나 전체 데이터(`KITCHEN_DATA`)가 들어오면, `KitchenProvider`의 핸들러(`_handleWsMessage`)가 이를 가공합니다.
2.  **상태 갱신**: 가공된 데이터를 `_orders`나 `_allMenus` 리스트에 업데이트하고 `notifyListeners()`를 호출합니다.
3.  **UI 반응**: `HomeScreen` 등에서 `Consumer<KitchenProvider>` 또는 `context.watch<KitchenProvider>()`를 사용하여 Provider를 구독(Subscribe)하고 있으며, `notifyListeners()` 호출 시 해당 데이터가 포함된 위젯들이 자동으로 재빌드됩니다.
4.  **필터링 로직**: `KitchenProvider`의 `filteredMenus` getter가 검색어 및 카테고리에 따라 데이터를 필터링하여 UI(`GridView`)에 제공합니다.

---
## 5. React 프로토타입 분석 및 통합 전략

새로 도입하려는 `prototype.tsx`의 핵심 로직을 Flutter에 통합하기 위한 분석 결과입니다.

### 5.1 메뉴 파싱 로직 매칭 (Main[Sub])
- **현황**: React는 `RegExp`를 통해 `제육덮밥[코카콜라+계란후라이]`와 같은 문자열을 파싱합니다.
- **전략**: 
  - Flutter의 `OrderItem` 모델에 `parentMenu`와 `subItems` 필드를 각각 추가합니다.
  - `DataTransformer` 유틸리티를 생성하여 MySQL 스니핑으로 수신된 원시 문자열을 `RegExp(r"(.+)\[(.+)\]")`로 파싱하여 객체화합니다.
  - 이를 통해 MySQL의 평면적(flat) 데이터 구조를 UI의 계층적(hierarchical) 구조로 변환합니다.

### 5.2 타이머 및 상태 관리 재구현
- **현황**: React는 위젯 내부의 `useState`와 `useEffect`로 개별 타이머를 관리합니다.
- **설계**:
  - `KitchenProvider` 내부에 중앙 집중식 타이머(`Timer.periodic`)를 구현합니다.
  - 각 `OrderItem`은 `cookingStatus`(WAITING, COOKING, DONE)와 `remainingTime` 상태를 가집니다.
  - '시작' 버튼 클릭 시 Provider가 해당 아이템의 타이머를 활성화하고 `notifyListeners()`로 UI를 갱신합니다. 이 방식은 화면 전환 시에도 타이머가 초기화되지 않고 유지되는 장점이 있습니다.

### 5.3 데이터 변환 레이어(Data Transformation Layer)의 필요성
- **결론**: **필수적임**
- **이유**: 
  - MySQL 패킷 데이터는 순수 문자열이나 로우(Row) 데이터 형태인 경우가 많습니다.
  - 이를 그대로 UI에 바인딩하면 코드가 복잡해지고 유지보수가 어렵습니다.
  - `Service`에서 수신한 원시 데이터를 `Provider`가 사용하기 좋은 형태의 `OrderInfo` 객체로 변환하는 레이어를 둠으로써, UI 로직과 데이터 수신 로직을 명확히 분리할 수 있습니다.

---
**분석 및 전략 수정 완료**
