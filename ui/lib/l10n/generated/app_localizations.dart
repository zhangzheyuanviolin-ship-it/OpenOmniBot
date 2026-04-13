import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'小万'**
  String get appName;

  /// No description provided for @brandName.
  ///
  /// In zh, this message translates to:
  /// **'小万'**
  String get brandName;

  /// No description provided for @brandNameEnglish.
  ///
  /// In zh, this message translates to:
  /// **'Omnibot'**
  String get brandNameEnglish;

  /// No description provided for @commonLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中'**
  String get commonLoading;

  /// No description provided for @homeDrawerSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索全部对话'**
  String get homeDrawerSearchHint;

  /// No description provided for @homeDrawerClearSearch.
  ///
  /// In zh, this message translates to:
  /// **'清空搜索'**
  String get homeDrawerClearSearch;

  /// No description provided for @themeModeTitle.
  ///
  /// In zh, this message translates to:
  /// **'主题模式'**
  String get themeModeTitle;

  /// No description provided for @themeModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换浅色、深色或跟随系统外观'**
  String get themeModeSubtitle;

  /// No description provided for @themeModeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeModeDark;

  /// No description provided for @themeModeSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get themeModeSystem;

  /// No description provided for @languageTitle.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get languageTitle;

  /// No description provided for @languageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'设置应用界面、Agent 提示词与工具文案的显示语言'**
  String get languageSubtitle;

  /// No description provided for @languageFollowSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageFollowSystem;

  /// No description provided for @languageZhHans.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageZhHans;

  /// No description provided for @languageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsSectionModelMemory.
  ///
  /// In zh, this message translates to:
  /// **'模型与记忆'**
  String get settingsSectionModelMemory;

  /// No description provided for @settingsSectionServiceEnvironment.
  ///
  /// In zh, this message translates to:
  /// **'服务与环境'**
  String get settingsSectionServiceEnvironment;

  /// No description provided for @settingsSectionExperienceAppearance.
  ///
  /// In zh, this message translates to:
  /// **'体验与外观'**
  String get settingsSectionExperienceAppearance;

  /// No description provided for @settingsSectionPermissionInfo.
  ///
  /// In zh, this message translates to:
  /// **'权限与信息'**
  String get settingsSectionPermissionInfo;

  /// No description provided for @settingsModelProviderTitle.
  ///
  /// In zh, this message translates to:
  /// **'模型提供商'**
  String get settingsModelProviderTitle;

  /// No description provided for @settingsModelProviderSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'配置模型地址、密钥与模型列表'**
  String get settingsModelProviderSubtitle;

  /// No description provided for @settingsSceneModelTitle.
  ///
  /// In zh, this message translates to:
  /// **'场景模型配置'**
  String get settingsSceneModelTitle;

  /// No description provided for @settingsSceneModelSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按场景绑定模型，未绑定场景使用默认模型'**
  String get settingsSceneModelSubtitle;

  /// No description provided for @settingsLocalModelsTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地模型服务'**
  String get settingsLocalModelsTitle;

  /// No description provided for @settingsLocalModelsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理本地模型、推理、API 服务与语音模型'**
  String get settingsLocalModelsSubtitle;

  /// No description provided for @settingsWorkspaceMemoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'Workspace 记忆配置'**
  String get settingsWorkspaceMemoryTitle;

  /// No description provided for @settingsWorkspaceMemoryLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get settingsWorkspaceMemoryLoading;

  /// No description provided for @settingsWorkspaceMemoryEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用 workspace 记忆（嵌入检索可用）'**
  String get settingsWorkspaceMemoryEnabled;

  /// No description provided for @settingsWorkspaceMemoryLexical.
  ///
  /// In zh, this message translates to:
  /// **'使用 workspace 记忆（当前为词法检索）'**
  String get settingsWorkspaceMemoryLexical;

  /// No description provided for @settingsMcpToolsTitle.
  ///
  /// In zh, this message translates to:
  /// **'MCP 工具'**
  String get settingsMcpToolsTitle;

  /// No description provided for @settingsMcpToolsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'添加、启停和管理远端 MCP 服务'**
  String get settingsMcpToolsSubtitle;

  /// No description provided for @settingsLocalServiceTitle.
  ///
  /// In zh, this message translates to:
  /// **'本机服务'**
  String get settingsLocalServiceTitle;

  /// No description provided for @settingsLocalServiceSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在局域网内访问小万 MCP 和 webchat 服务'**
  String get settingsLocalServiceSubtitle;

  /// No description provided for @settingsAlpineTitle.
  ///
  /// In zh, this message translates to:
  /// **'Alpine 环境'**
  String get settingsAlpineTitle;

  /// No description provided for @settingsAlpineSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看与打开应用内 Alpine 终端环境'**
  String get settingsAlpineSubtitle;

  /// No description provided for @settingsHideRecentsTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台隐藏'**
  String get settingsHideRecentsTitle;

  /// No description provided for @settingsHideRecentsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'开启后应用将从最近任务列表中隐藏'**
  String get settingsHideRecentsSubtitle;

  /// No description provided for @settingsAlarmTitle.
  ///
  /// In zh, this message translates to:
  /// **'闹钟设置'**
  String get settingsAlarmTitle;

  /// No description provided for @settingsAlarmSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'配置默认铃声、本地 mp3 或 mp3 直链'**
  String get settingsAlarmSubtitle;

  /// No description provided for @settingsAppearanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'外观设置'**
  String get settingsAppearanceTitle;

  /// No description provided for @settingsAppearanceSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'配置主题模式、语言、共享背景图、聊天字号和文本颜色'**
  String get settingsAppearanceSubtitle;

  /// No description provided for @settingsVibrationTitle.
  ///
  /// In zh, this message translates to:
  /// **'振动反馈'**
  String get settingsVibrationTitle;

  /// No description provided for @settingsVibrationSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'执行任务时，通过振动进行操作提醒'**
  String get settingsVibrationSubtitle;

  /// No description provided for @settingsAutoBackTitle.
  ///
  /// In zh, this message translates to:
  /// **'任务完成后自动回聊天'**
  String get settingsAutoBackTitle;

  /// No description provided for @settingsAutoBackSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭后，任务结束将停留在当前完成页面'**
  String get settingsAutoBackSubtitle;

  /// No description provided for @settingsCompanionPermissionTitle.
  ///
  /// In zh, this message translates to:
  /// **'陪伴权限授权'**
  String get settingsCompanionPermissionTitle;

  /// No description provided for @settingsCompanionPermissionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'仅访问您授权的 App，隐私安全更有保障'**
  String get settingsCompanionPermissionSubtitle;

  /// No description provided for @settingsAboutTitle.
  ///
  /// In zh, this message translates to:
  /// **'关于小万'**
  String get settingsAboutTitle;

  /// No description provided for @settingsHideRecentsFailed.
  ///
  /// In zh, this message translates to:
  /// **'设置后台隐藏失败'**
  String get settingsHideRecentsFailed;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'设置失败'**
  String get settingsSaveFailed;

  /// No description provided for @settingsAutoBackEnabledToast.
  ///
  /// In zh, this message translates to:
  /// **'任务完成后将自动返回聊天'**
  String get settingsAutoBackEnabledToast;

  /// No description provided for @settingsAutoBackDisabledToast.
  ///
  /// In zh, this message translates to:
  /// **'任务完成后将停留在当前页面'**
  String get settingsAutoBackDisabledToast;

  /// No description provided for @settingsMcpEnabledToast.
  ///
  /// In zh, this message translates to:
  /// **'MCP 已开启：{endpoint}'**
  String settingsMcpEnabledToast(Object endpoint);

  /// No description provided for @settingsMcpDisabledToast.
  ///
  /// In zh, this message translates to:
  /// **'MCP 已关闭'**
  String get settingsMcpDisabledToast;

  /// No description provided for @settingsMcpToggleFailed.
  ///
  /// In zh, this message translates to:
  /// **'MCP 开关失败'**
  String get settingsMcpToggleFailed;

  /// No description provided for @settingsCopiedAddress.
  ///
  /// In zh, this message translates to:
  /// **'已复制访问地址'**
  String get settingsCopiedAddress;

  /// No description provided for @settingsCopiedToken.
  ///
  /// In zh, this message translates to:
  /// **'已复制 Token'**
  String get settingsCopiedToken;

  /// No description provided for @settingsTokenRefreshed.
  ///
  /// In zh, this message translates to:
  /// **'已刷新 Token'**
  String get settingsTokenRefreshed;

  /// No description provided for @settingsTokenRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'刷新 Token 失败'**
  String get settingsTokenRefreshFailed;

  /// No description provided for @settingsMcpLocalService.
  ///
  /// In zh, this message translates to:
  /// **'本机服务'**
  String get settingsMcpLocalService;

  /// No description provided for @settingsMcpAddress.
  ///
  /// In zh, this message translates to:
  /// **'地址'**
  String get settingsMcpAddress;

  /// No description provided for @settingsMcpToken.
  ///
  /// In zh, this message translates to:
  /// **'Token'**
  String get settingsMcpToken;

  /// No description provided for @settingsNotGenerated.
  ///
  /// In zh, this message translates to:
  /// **'未生成'**
  String get settingsNotGenerated;

  /// No description provided for @settingsCopyAddress.
  ///
  /// In zh, this message translates to:
  /// **'复制地址'**
  String get settingsCopyAddress;

  /// No description provided for @settingsCopyToken.
  ///
  /// In zh, this message translates to:
  /// **'复制 Token'**
  String get settingsCopyToken;

  /// No description provided for @settingsRefreshToken.
  ///
  /// In zh, this message translates to:
  /// **'刷新 Token'**
  String get settingsRefreshToken;

  /// No description provided for @settingsMcpSecurityNotice.
  ///
  /// In zh, this message translates to:
  /// **'请在同一局域网内使用 Authorization: Bearer <Token> 调用 /mcp/v1/task/vlm，避免将地址或 Token 暴露到公网。'**
  String get settingsMcpSecurityNotice;

  /// No description provided for @settingsInstalledAppsPermissionFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求应用列表权限失败'**
  String get settingsInstalledAppsPermissionFailed;

  /// No description provided for @appearanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'外观设置'**
  String get appearanceTitle;

  /// No description provided for @appearanceAutoSaving.
  ///
  /// In zh, this message translates to:
  /// **'正在自动保存…'**
  String get appearanceAutoSaving;

  /// No description provided for @appearanceAutosaveHint.
  ///
  /// In zh, this message translates to:
  /// **'更改会自动保存'**
  String get appearanceAutosaveHint;

  /// No description provided for @appearanceBackgroundSource.
  ///
  /// In zh, this message translates to:
  /// **'背景来源'**
  String get appearanceBackgroundSource;

  /// No description provided for @appearancePreview.
  ///
  /// In zh, this message translates to:
  /// **'效果预览'**
  String get appearancePreview;

  /// No description provided for @appearanceAdjustments.
  ///
  /// In zh, this message translates to:
  /// **'效果调整'**
  String get appearanceAdjustments;

  /// No description provided for @appearancePreviewChat.
  ///
  /// In zh, this message translates to:
  /// **'聊天'**
  String get appearancePreviewChat;

  /// No description provided for @appearancePreviewWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'工作区'**
  String get appearancePreviewWorkspace;

  /// No description provided for @appearanceEnableBackground.
  ///
  /// In zh, this message translates to:
  /// **'启用背景图'**
  String get appearanceEnableBackground;

  /// No description provided for @appearanceEnableBackgroundSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'同时作用于聊天页和 Workspace 页面，并自动保存'**
  String get appearanceEnableBackgroundSubtitle;

  /// No description provided for @appearanceSourceLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地图片'**
  String get appearanceSourceLocal;

  /// No description provided for @appearanceSourceRemote.
  ///
  /// In zh, this message translates to:
  /// **'图片直链'**
  String get appearanceSourceRemote;

  /// No description provided for @appearanceNoLocalImage.
  ///
  /// In zh, this message translates to:
  /// **'尚未选择本地图片'**
  String get appearanceNoLocalImage;

  /// No description provided for @appearancePickImage.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get appearancePickImage;

  /// No description provided for @appearanceRepickImage.
  ///
  /// In zh, this message translates to:
  /// **'重新选择'**
  String get appearanceRepickImage;

  /// No description provided for @appearanceRemoteImageUrl.
  ///
  /// In zh, this message translates to:
  /// **'图片直链'**
  String get appearanceRemoteImageUrl;

  /// No description provided for @appearanceRemoteImageUrlHint.
  ///
  /// In zh, this message translates to:
  /// **'https://example.com/background.jpg'**
  String get appearanceRemoteImageUrlHint;

  /// No description provided for @appearanceBackgroundBlur.
  ///
  /// In zh, this message translates to:
  /// **'背景柔化'**
  String get appearanceBackgroundBlur;

  /// No description provided for @appearanceBackgroundBlurSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'调节图片上方蒙版的柔化程度'**
  String get appearanceBackgroundBlurSubtitle;

  /// No description provided for @appearanceOverlayIntensity.
  ///
  /// In zh, this message translates to:
  /// **'蒙版强度'**
  String get appearanceOverlayIntensity;

  /// No description provided for @appearanceOverlayIntensitySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'增强统一蒙版，让页面元素更干净'**
  String get appearanceOverlayIntensitySubtitle;

  /// No description provided for @appearanceOverlayBrightness.
  ///
  /// In zh, this message translates to:
  /// **'蒙版明暗'**
  String get appearanceOverlayBrightness;

  /// No description provided for @appearanceOverlayBrightnessSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提亮或压暗蒙版，不会直接修改原图'**
  String get appearanceOverlayBrightnessSubtitle;

  /// No description provided for @appearanceChatTextSize.
  ///
  /// In zh, this message translates to:
  /// **'聊天文本大小'**
  String get appearanceChatTextSize;

  /// No description provided for @appearanceChatTextSizeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'仅调整用户消息、AI 回复与思考区字号'**
  String get appearanceChatTextSizeSubtitle;

  /// No description provided for @appearanceTextColorTitle.
  ///
  /// In zh, this message translates to:
  /// **'聊天文本颜色'**
  String get appearanceTextColorTitle;

  /// No description provided for @appearanceTextColorSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'默认会自动跟随背景明暗，也可以改成固定颜色'**
  String get appearanceTextColorSubtitle;

  /// No description provided for @appearanceTextColorAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get appearanceTextColorAuto;

  /// No description provided for @appearanceCustomColorLabel.
  ///
  /// In zh, this message translates to:
  /// **'自定义色号'**
  String get appearanceCustomColorLabel;

  /// No description provided for @appearanceCustomColorHint.
  ///
  /// In zh, this message translates to:
  /// **'#FFFFFF 或 #FF112233'**
  String get appearanceCustomColorHint;

  /// No description provided for @appearancePreviewTip.
  ///
  /// In zh, this message translates to:
  /// **'图片可直接在上方预览里拖动和双指缩放，预览会尽量贴近实际效果。'**
  String get appearancePreviewTip;

  /// No description provided for @appearanceColorWhite.
  ///
  /// In zh, this message translates to:
  /// **'白'**
  String get appearanceColorWhite;

  /// No description provided for @appearanceColorDarkGray.
  ///
  /// In zh, this message translates to:
  /// **'深灰'**
  String get appearanceColorDarkGray;

  /// No description provided for @appearanceColorLightBlue.
  ///
  /// In zh, this message translates to:
  /// **'浅蓝'**
  String get appearanceColorLightBlue;

  /// No description provided for @appearanceColorNavy.
  ///
  /// In zh, this message translates to:
  /// **'藏蓝'**
  String get appearanceColorNavy;

  /// No description provided for @appearanceColorTeal.
  ///
  /// In zh, this message translates to:
  /// **'青绿'**
  String get appearanceColorTeal;

  /// No description provided for @appearanceColorWarmYellow.
  ///
  /// In zh, this message translates to:
  /// **'暖黄'**
  String get appearanceColorWarmYellow;

  /// No description provided for @appearanceInvalidHttpUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 http(s) 图片直链'**
  String get appearanceInvalidHttpUrl;

  /// No description provided for @appearanceInvalidHexColor.
  ///
  /// In zh, this message translates to:
  /// **'请输入 #RRGGBB 或 #AARRGGBB'**
  String get appearanceInvalidHexColor;

  /// No description provided for @appearanceInvalidHexColorFormat.
  ///
  /// In zh, this message translates to:
  /// **'色号格式不正确'**
  String get appearanceInvalidHexColorFormat;

  /// No description provided for @appearancePickImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'选择图片失败：{error}'**
  String appearancePickImageFailed(Object error);

  /// No description provided for @appearancePickLocalImageFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先选择本地图片'**
  String get appearancePickLocalImageFirst;

  /// No description provided for @appearanceLocalImageMissing.
  ///
  /// In zh, this message translates to:
  /// **'本地图片不存在，请重新选择'**
  String get appearanceLocalImageMissing;

  /// No description provided for @appearanceAutosaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'自动保存失败：{error}'**
  String appearanceAutosaveFailed(Object error);

  /// No description provided for @chatToolCalling.
  ///
  /// In zh, this message translates to:
  /// **'正在调用工具'**
  String get chatToolCalling;

  /// No description provided for @chatFallbackReply.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法生成回复，请重试。'**
  String get chatFallbackReply;

  /// No description provided for @chatPermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'执行任务前需要先开启权限'**
  String get chatPermissionRequired;

  /// No description provided for @chatPermissionRequiredWithNames.
  ///
  /// In zh, this message translates to:
  /// **'执行任务前，请先开启：{names}'**
  String chatPermissionRequiredWithNames(Object names);

  /// No description provided for @chatRecentTerminalOutputNotice.
  ///
  /// In zh, this message translates to:
  /// **'[只显示最近的部分终端输出]\n'**
  String get chatRecentTerminalOutputNotice;

  /// No description provided for @chatUserPrefix.
  ///
  /// In zh, this message translates to:
  /// **'用户: {text}\n'**
  String chatUserPrefix(Object text);

  /// No description provided for @permissionAccessibility.
  ///
  /// In zh, this message translates to:
  /// **'无障碍权限'**
  String get permissionAccessibility;

  /// No description provided for @permissionOverlay.
  ///
  /// In zh, this message translates to:
  /// **'悬浮窗权限'**
  String get permissionOverlay;

  /// No description provided for @permissionInstalledApps.
  ///
  /// In zh, this message translates to:
  /// **'应用列表读取权限'**
  String get permissionInstalledApps;

  /// No description provided for @permissionPublicStorage.
  ///
  /// In zh, this message translates to:
  /// **'公共文件访问'**
  String get permissionPublicStorage;

  /// No description provided for @browserOverlayTitle.
  ///
  /// In zh, this message translates to:
  /// **'Agent Browser'**
  String get browserOverlayTitle;

  /// No description provided for @browserOverlayClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭浏览器窗口'**
  String get browserOverlayClose;

  /// No description provided for @browserOverlayUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持浏览器工具视图'**
  String get browserOverlayUnsupported;

  /// No description provided for @networkErrorMessage.
  ///
  /// In zh, this message translates to:
  /// **'抱歉，刚刚网络开小差了。再发一次试试？'**
  String get networkErrorMessage;

  /// No description provided for @rateLimitErrorMessage.
  ///
  /// In zh, this message translates to:
  /// **'小万忙不过来了，等会儿再试试吧'**
  String get rateLimitErrorMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
