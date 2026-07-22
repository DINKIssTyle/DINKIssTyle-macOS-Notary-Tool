# DKST macOS Notary Tool

## ⚠️ 경고, 이 앱은 알파테스트 중입니다. 의도한대로 작동하지 않을 수 있으니 사용에 유의하여야 합니다.

## 소개
<div align="center"><img src="Docs/Screenshot-Main-01.png" alt="메인화면" width="1000"><br><br></div>
이 도구는 macOS용 앱 번들에 Apple 등록 개발자의 서명과 공증을 쉽고 간편하게 진행하고 진단할 수 있는 도구입니다. 또한, PKG, DMG, ZIP 파일로 패키징이 가능하며, 특히 PKG와 DMG의 경우 배포에 맞게 꾸미는 작업을 도와줍니다.


## 사전 준비 사항
- 개발자 서명 및 공증을 받으려면 멤버십이 활성화된 개발자 계정이 필요합니다.
- 앱 실행 환경에 Xcode 및 Xcode CLI 도구가 설치되어 있어야 합니다.
- 앱이 올바르게 서명 및 공증되려면 실행 환경의 키체인에 사용 가능한 인증서가 설치되어 있어야 합니다. 필수 인증서는 다음과 같습니다.
  - `Developer ID Applications`: 앱스토어가 아닌 배포 환경에서 앱을 서명하는 데 사용됩니다.
  - `Developer ID Installer`: PKG 설치 패키지를 서명하는 데 사용됩니다.

## 서명과 공증 준비하기

<div align="center"><img src="Docs/Screenshot-Main-02.png" alt="메인화면" width="1000"><br><br></div>

서명과 공증을 시작하기 위해서는 실행 환경에 공증 프로필이 설치되어 있어야 합니다.  
`Notary Profiles` 탭에서 macOS에 설치되어 있는 프로필을 확인하고 연결`Link Existing`하거나, 새 프로필을 생성`Register New Profile`할 수 있습니다.

### 새 프로필 생성 (Register New Profile)
- **Profile Name**: 사용할 프로필 이름을 정하세요. 프로젝트나 팀 이름 등 어떤 것이든 괜찮습니다.
- **Apple ID (Email)**: Apple Developer Membership이 활성화된 Apple ID를 입력하세요.
- **Apple Developer Team ID**: 각 계정에 부여된 고유 ID입니다. Xcode 계정에서 확인하실 수 있습니다.
- **App-Specific Password**: https://account.apple.com 에서 생성한 앱별 암호를 입력하세요. 주의: 이는 Apple ID 로그인 암호가 아닙니다. 

`Register to System Keychain` 버튼을 클릭하여 정보를 macOS 키체인에 저장하세요.


### 기존 프로필 연결 (Link Existing)
- Profile Name: macOS에 저장된 프로필 이름을 입력하세요.
- `Link Profile to App`을 클릭하면, 우측의 'Saved Profiles'에 표시됩니다.
  - `Saved Profiles`에 있다는 것이 해당 프로필이 올바르다는 것을 의미하지는 않습니다. 단순히 저장된 내용일 뿐입니다.
 

## 서명과 공증 시작하기

<div align="center"><img src="Docs/Screenshot-Main-Part-01.png" alt="메인화면" width="600"><br><br></div>

1. `Notarize` 화면 Drag & Drop 으로 부터 시작합니다.
1. 서명, 공증, 검증 할 앱번들 또는 .pkg 파일을 Drag & Drop 합니다.

서명된 앱 번들을 Drag & Drop 하면 이미 서명되어 있음을 알려줍니다. 'Verify Only'를 사용하면 서명 및 공증 상태만 확인할 수 있으며, 물론 다시 서명하거나 공증할 수도 있습니다.

<div align="center"><img src="Docs/Screenshot-Main-Part-02.png" alt="메인화면" width="600"><br><br></div>


- **Code Signing**: 을 켜고 선택한 `Developer ID Applications` 인증서로 서명 합니다.
- **Notarization**: 서명 후 최종 공증까지 합니다.
- **Notary Credentials**: 공증에 사용할 `Notary Profiles` 을 선택합니다.


`Sign & Notarize` 버튼을 클릭한 후, 서명 및 공증이 완료될 때까지 기다려 주세요. 작업이 완료되면 오른쪽의 `Verification Checklist Report`에 서명 및 공증 검증 상태가 표시됩니다.


<div align="center"><img src="Docs/Screenshot-Main-Part-03.png" alt="메인화면" width="300"><br><br></div>


자! 이것으로 앱번들은 서명되었고, 공증까지 받은 상태가 됩니다.


## PKG 설치로 배포하기
DKST macOS Notary Tool에서 간단하지만 빠르게 PKG를 사용자화 할 수 있습니다.

<div align="center"><img src="Docs/Screenshot-Main-Part-04.png" alt="메인화면" width="300"><br><img src="Docs/Screenshot-Main-Part-05.png" alt="메인화면" width="300"><br><br></div>

1. **Build Installer (.pkg)** 를 켜주세요.
1. `Developer ID Installer` 인증서를 선택해주세요.  
   앱이 이미 공증되어 있고 변경이 없어도, .pkg 재생성마다 .pkg를 다시 공증 받아야 합니다.
1. **Installer Title**: 인스톨러에 사용되는 타이틀바 이름을 입력합니다. 앱번들 내용을 자동삽입하지만, 원하는 경우 변경하세요.
1. **Package Identifier**: 앱번들의 내용을 자동으로 삽입합니다. 필요에 따라 변경하세요.
1. **Installer Pages**: 인스톨러 각 단계에 표시할 화면을 선택하고, 내용을 변경할 수 있습니다.
    1. Welcome: 인스톨러 실행시 처음 마주하게 되는 화면입니다.
       <div align="center"><img src="Docs/Screenshot-PKG-Welcome-01.png" alt="Welcome 화면" width="550"><br></div>
    1. Read Me: 읽어보아야 할 화면 내용 입니다.
    1. License: 고지할 라이센스와 동의를 받으려면 추가하세요.
    1. Conclusion: 인스톨러 설치가 끝난 마지막 화면 입니다.
    1. 각 화면은 `Edit` 버튼을 눌러 내용을 편집할수 있습니다.
    1. `Edit`화면은 Rich Text Format Directory (.rtfd)를 지원하는 편집창입니다. 포맷이 있는 텍스트 및 이미지를 붙여 넣을 수 있습니다. 손쉽게 .rtfd 문서를 생성하고 편집하는 방법은 macOS의 TextEdit.app 을 이용하는 것입니다. 문서를 꾸미고 복사해서 `Edit`화면에 붙여넣기 하세요.
1. **Installer Background**: .pkg 인스톨러는 배경화면을 지원합니다. `Edit PKG-Installer-BG-TEMP.psd in this project.`를 클릭하면 `.dnt` 프로젝트 안에 저장된 Photoshop (.PSD) 템플릿이 열립니다. 편집 내용을 PSD에 저장하면 빌드할 때 자동으로 PNG로 변환되어 사용됩니다. 별도의 PNG를 사용하려면 `Choose...` 버튼으로 불러올 수도 있습니다.
1. **After Installation**: 인스톨러가 설치를 완료했을 때 사용자에게 표시되는 버튼의 유형입니다.
    1. No Action: 가장 일반적인 유형입니다. 사용자는 설치를 완료하고 닫기 버튼으로 인스톨러를 종료할 수 있습니다.
    1. Require Logout: 설치가 완료되면 사용자에게 제공되는 버튼은 로그아웃 버튼 뿐입니다. 인스톨러를 강제로 종료하지 않는 이상 사용자는 로그아웃 해야 합니다.
    1. Require Restart: 설치가 완료되면 사용자에게 제공되는 버튼은 재부팅 버튼 뿐입니다. 인스톨러를 강제로 종료하지 않는 이상 사용자는 재부팅 해야 합니다.
1. **Advanced Options**: 앱번들의 설치 위치가 `/Applications`가 아닌 경우 유용한 옵션입니다. 예를들면 입력기 같은 경우가 이에 해당합니다. System 또는 사용자 계정에서 `Install Location` 위치에 앱번들을 설치합니다.


## DMG로 배포하기
DKST macOS Notary Tool에서 간단하지만 빠르게 DMG 디스크를 사용자화 할 수 있습니다.

<div align="center"><img src="Docs/Screenshot-Main-Part-06.png" alt="메인화면" width="300"><br><br></div>

1. **Build Disk Image (.dmg)** 를 켜주세요.
1. **Put Installer Package in DMG** 를 체크하면, 선행으로 생성한 .PKG 파일을 .DMG 디스크 내용으로 사용할 수 있습니다.
1. **Volume Name** 마운트 된 DMG 디스크 볼륨의 이름입니다. 원하는 것으로 수정할 수 있습니다.
1. **Layout Preset**: 2가지 프리셋과 수동 레이아웃을 선택할수 있습니다.
    1. **Template 1**: 좌측에 앱 아이콘, 우측에 Applications 폴더가 위치한 레이아웃입니다.
    1. **Template 2**: 상단에 앱 아이콘, 하단에 Applications 폴더가 위차한 레이아웃입니다.
       <div align="center"><img src="Docs/Screenshot-DMG-Layout-01.png" alt="Template 2" width="550"><br></div>
    1. Template 을 선택하면 `Edit DMG-BG-TEMP.psd in this project.`와 같이 해당 레이아웃의 배경 PSD를 여는 안내문이 표시됩니다. PSD는 `.dnt` 프로젝트 안에 저장되며, 편집 내용을 저장하면 빌드할 때 자동으로 PNG로 변환되어 사용됩니다.
    1. 만약, `Put Installer Package in DMG` 을 선택하거나, `Add Applications Shortcut` 선택을 하지 않았을 경우 중앙에 앱 또는 .PKG 아이콘이 있는 별도의 레이아웃이 선택됩니다. 이 경우에도 배경 편집에 도움이 되는 Photoshop (.PSD)파일을 열수 있습니다.
       <div align="center"><img src="Docs/Screenshot-DMG-Layout-02.png" alt="Template 2" width="550"><br></div>
1. **Add Applications Shortcut**: Applications 폴더를 보일지 선택합니다.


## ZIP으로 배포하기
서명 및 공증이 완료된 앱의 서명이나 공증은 압축 과정에서 쉽게 손상되지 않지만, 혹시 모를 손상을 방지하기 위해 Apple은 ditto를 이용한 압축을 권장합니다.  

**Build Zip Archive (.zip)** 를 활성화하면 앱 번들이 ditto를 사용하여 압축된 .ZIP 파일로 압축됩니다.


## 자동 저장과 불러오기에 관하여
DKST macOS Notary Tool은 불러온 앱번들 폴더에 `.DNT` 프로젝트 패키지를 자동으로 생성합니다. Finder에서는 하나의 문서처럼 보이지만, 내부에는 프로젝트 설정과 편집 가능한 PSD 템플릿 및 에셋이 폴더 구조로 저장됩니다.

앱번들이 `/Applications` 또는 사용자 홈의 `Applications` 폴더에 있으면 앱 옆에 프로젝트를 생성하지 않고 `.DNT` 저장 위치를 묻습니다. 선택을 취소하면 실제 프로젝트 저장이나 빌드가 필요할 때 다시 묻습니다.

#### 이 파일이 담고 있는 내용
- 작업하는 앱번들의 이름
- 각종 옵션 선택 상태
- .PKG 페이지들의 .RTFD 내용
- .PKG 백그라운드 이미지
- .DMG 백그라운드 이미지 등
- 편집 가능한 네 개의 Photoshop (.PSD) 템플릿
- 작업 전반적인 내용

이 파일에는 앱 번들의 위치가 사용자 홈 폴더 기준 상대경로로 저장되므로 `.DNT` 파일은 어느 위치에 보관해도 됩니다. `.DNT` 파일을 열었을 때 저장된 위치에 앱 번들이 없으면 파일 선택 창이 열립니다. 새 앱 번들을 선택하면 해당 위치가 현재 `.DNT` 파일에 저장되며, 선택을 취소하면 앱 번들이 선택되지 않은 초기 화면으로 돌아갑니다.


## 응원과 후원


<p align="center">
  <a href="https://github.com/sponsors/DINKIssTyle">
    <img src="https://img.shields.io/badge/Sponsor-EA4AAA?style=for-the-badge&logo=github-sponsors&logoColor=white" alt="Sponsor">
  </a>
  <br> 이 프로젝트가 아내 눈치 안보고 지속되길 바라신다면 위 버튼을 눌러주세요!
</p><br>


<div align="center">
  <a href="https://github.com/DINKIssTyle/DINKIssTyle-Markdown-Browser" target="_blank"><img src="https://github.com/DINKIssTyle/DINKIssTyle-Markdown-Browser/blob/main/DKST-Markdown.png?raw=true" width="150"></a><br>
이 README.md 파일은 DKST Markdown으로 작성되었습니다.<br>AI가 어시스트 하는 마크다운 에디터에 관심있으시다면 배지를 클릭하세요.<br><br>
</div>
