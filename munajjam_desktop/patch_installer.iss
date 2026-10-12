; =====================================================================
; Inno Setup Patch Script for Munajjam Quran Alignment Desktop
; مثبت التحديث السريع لمنصة منجم للتزمين القرآني
; =====================================================================

#define MyAppName "منجم - تحديث سريع (Patch)"
#define MyAppNameEn "Munajjam Quran Alignment"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "علي ملص (Itqan Projects)"
#define MyAppURL "https://github.com/alinice1998/colabwis"
#define MyAppExeName "munajjam_desktop.exe"

[Setup]
; App Identity - نفس المعرّف للتعرف على التثبيت السابق تلقائياً
AppId={{D37F881A-6A34-4C21-B4B2-12499FFB4391}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; تثبيت فوق المجلد السابق مباشرة دون إرباك المستخدم
DefaultDirName={autopf}\{#MyAppNameEn}
UsePreviousAppDir=yes
DirExistsWarning=no
DisableDirPage=yes
DisableProgramGroupPage=yes

; أيقونة وشكل المعالج
SetupIconFile=windows\runner\resources\app_icon.ico
Uninstallable=no

; إعدادات حزمة الإخراج
OutputDir=..\installer_output
OutputBaseFilename=Munajjam_Desktop_Patch_v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; معلومات النسخة
VersionInfoVersion=1.0.1.0
VersionInfoCompany=علي ملص - Itqan Projects
VersionInfoDescription=تحديث باتش منصة منجم للتزمين القرآني الذكي
VersionInfoCopyright=Copyright (C) 2026 Ali Mallas (علي ملص). All rights reserved.
VersionInfoProductName=منجم - التزمين القرآني الذكي
VersionInfoProductVersion=1.0.1

; الصلاحيات والتوافق
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
CloseApplications=yes

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
arabic.WelcomeLabel1=مرحباً بك في تحديث منجم للتزمين القرآني
arabic.WelcomeLabel2=يقوم هذا البرنامج بتطبيق آخر التحسينات وتحديث محرك التزمين والموجات الصوتية تلقائياً على نسختك الحالية دون الحاجة لإعادة تنزيل نماذج الذكاء الاصطناعي.
english.WelcomeLabel1=Welcome to Munajjam Update Patch
english.WelcomeLabel2=This patch will update your existing Munajjam installation with the latest waveform timing fixes and enhancements without re-downloading AI models.

[Files]
; 1. ملفات واجهة البرنامج المحدثة (Flutter Release)
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 2. سكربتات محرك التزمين المحدثة (Hybrid Aligner)
Source: "..\hybrid_aligner\*"; DestDir: "{app}\hybrid_aligner"; Excludes: "__pycache__, *.pyc"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
