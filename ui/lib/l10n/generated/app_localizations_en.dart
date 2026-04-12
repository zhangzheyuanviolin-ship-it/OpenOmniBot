// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Omnibot';

  @override
  String get brandName => 'Omnibot';

  @override
  String get brandNameEnglish => 'Omnibot';

  @override
  String get commonLoading => 'Loading';

  @override
  String get homeDrawerSearchHint => 'Search';

  @override
  String get homeDrawerClearSearch => 'Clear search';

  @override
  String get themeModeTitle => 'Theme Mode';

  @override
  String get themeModeSubtitle =>
      'Switch between light, dark, or system appearance';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get themeModeSystem => 'System';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSubtitle =>
      'Choose the display language for the app UI, agent prompts, and tool text';

  @override
  String get languageFollowSystem => 'Follow System';

  @override
  String get languageZhHans => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionModelMemory => 'Models & Memory';

  @override
  String get settingsSectionServiceEnvironment => 'Services & Environment';

  @override
  String get settingsSectionExperienceAppearance => 'Experience & Appearance';

  @override
  String get settingsSectionPermissionInfo => 'Permissions & Info';

  @override
  String get settingsModelProviderTitle => 'Model Providers';

  @override
  String get settingsModelProviderSubtitle =>
      'Configure model endpoints, API keys, and model lists';

  @override
  String get settingsSceneModelTitle => 'Scene Model Config';

  @override
  String get settingsSceneModelSubtitle =>
      'Bind models by scene and use the default model for unbound scenes';

  @override
  String get settingsLocalModelsTitle => 'Local Model Service';

  @override
  String get settingsLocalModelsSubtitle =>
      'Manage local models, inference, API services, and speech models';

  @override
  String get settingsWorkspaceMemoryTitle => 'Workspace Memory';

  @override
  String get settingsWorkspaceMemoryLoading => 'Loading...';

  @override
  String get settingsWorkspaceMemoryEnabled =>
      'Workspace memory enabled (embedding retrieval available)';

  @override
  String get settingsWorkspaceMemoryLexical =>
      'Use workspace memory (currently lexical retrieval)';

  @override
  String get settingsMcpToolsTitle => 'MCP Tools';

  @override
  String get settingsMcpToolsSubtitle =>
      'Add, enable, and manage remote MCP services';

  @override
  String get settingsLocalServiceTitle => 'Local Service';

  @override
  String get settingsLocalServiceSubtitle =>
      'Access Omnibot MCP and webchat over your local network';

  @override
  String get settingsAlpineTitle => 'Alpine Environment';

  @override
  String get settingsAlpineSubtitle =>
      'View and open the built-in Alpine terminal environment';

  @override
  String get settingsHideRecentsTitle => 'Hide from Recents';

  @override
  String get settingsHideRecentsSubtitle =>
      'Hide the app from the recent tasks list when enabled';

  @override
  String get settingsAlarmTitle => 'Alarm Settings';

  @override
  String get settingsAlarmSubtitle =>
      'Configure the default ringtone, a local mp3, or an mp3 URL';

  @override
  String get settingsAppearanceTitle => 'Appearance';

  @override
  String get settingsAppearanceSubtitle =>
      'Configure theme mode, language, shared background, chat font size, and text color';

  @override
  String get settingsVibrationTitle => 'Vibration Feedback';

  @override
  String get settingsVibrationSubtitle =>
      'Use vibration to signal task progress while executing';

  @override
  String get settingsAutoBackTitle => 'Return to Chat After Tasks';

  @override
  String get settingsAutoBackSubtitle =>
      'When disabled, the task result page stays open after completion';

  @override
  String get settingsCompanionPermissionTitle => 'Companion App Permissions';

  @override
  String get settingsCompanionPermissionSubtitle =>
      'Only access apps you authorize for better privacy and safety';

  @override
  String get settingsAboutTitle => 'About Omnibot';

  @override
  String get settingsHideRecentsFailed => 'Failed to update hide-from-recents';

  @override
  String get settingsSaveFailed => 'Failed to save settings';

  @override
  String get settingsAutoBackEnabledToast =>
      'The app will return to chat after tasks finish';

  @override
  String get settingsAutoBackDisabledToast =>
      'The app will stay on the current page after tasks finish';

  @override
  String settingsMcpEnabledToast(Object endpoint) {
    return 'MCP enabled: $endpoint';
  }

  @override
  String get settingsMcpDisabledToast => 'MCP disabled';

  @override
  String get settingsMcpToggleFailed => 'Failed to toggle MCP';

  @override
  String get settingsCopiedAddress => 'Address copied';

  @override
  String get settingsCopiedToken => 'Token copied';

  @override
  String get settingsTokenRefreshed => 'Token refreshed';

  @override
  String get settingsTokenRefreshFailed => 'Failed to refresh token';

  @override
  String get settingsMcpLocalService => 'Local Service';

  @override
  String get settingsMcpAddress => 'Address';

  @override
  String get settingsMcpToken => 'Token';

  @override
  String get settingsNotGenerated => 'Not generated';

  @override
  String get settingsCopyAddress => 'Copy Address';

  @override
  String get settingsCopyToken => 'Copy Token';

  @override
  String get settingsRefreshToken => 'Refresh Token';

  @override
  String get settingsMcpSecurityNotice =>
      'Call /mcp/v1/task/vlm on the same LAN with Authorization: Bearer <Token>, and avoid exposing the address or token to the public internet.';

  @override
  String get settingsInstalledAppsPermissionFailed =>
      'Failed to request installed apps permission';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get appearanceAutoSaving => 'Saving changes…';

  @override
  String get appearanceAutosaveHint => 'Changes are saved automatically';

  @override
  String get appearanceBackgroundSource => 'Background Source';

  @override
  String get appearancePreview => 'Preview';

  @override
  String get appearanceAdjustments => 'Adjustments';

  @override
  String get appearancePreviewChat => 'Chat';

  @override
  String get appearancePreviewWorkspace => 'Workspace';

  @override
  String get appearanceEnableBackground => 'Enable background image';

  @override
  String get appearanceEnableBackgroundSubtitle =>
      'Apply it to both Chat and Workspace pages and save automatically';

  @override
  String get appearanceSourceLocal => 'Local Image';

  @override
  String get appearanceSourceRemote => 'Image URL';

  @override
  String get appearanceNoLocalImage => 'No local image selected yet';

  @override
  String get appearancePickImage => 'Choose Image';

  @override
  String get appearanceRepickImage => 'Choose Again';

  @override
  String get appearanceRemoteImageUrl => 'Image URL';

  @override
  String get appearanceRemoteImageUrlHint =>
      'https://example.com/background.jpg';

  @override
  String get appearanceBackgroundBlur => 'Background Blur';

  @override
  String get appearanceBackgroundBlurSubtitle =>
      'Adjust the blur of the overlay above the image';

  @override
  String get appearanceOverlayIntensity => 'Overlay Strength';

  @override
  String get appearanceOverlayIntensitySubtitle =>
      'Increase the unified overlay to make the UI cleaner';

  @override
  String get appearanceOverlayBrightness => 'Overlay Brightness';

  @override
  String get appearanceOverlayBrightnessSubtitle =>
      'Brighten or darken the overlay without modifying the image itself';

  @override
  String get appearanceChatTextSize => 'Chat Text Size';

  @override
  String get appearanceChatTextSizeSubtitle =>
      'Only affects user messages, AI replies, and the thinking panel';

  @override
  String get appearanceTextColorTitle => 'Chat Text Color';

  @override
  String get appearanceTextColorSubtitle =>
      'By default it adapts to the background, or you can pin a custom color';

  @override
  String get appearanceTextColorAuto => 'Auto';

  @override
  String get appearanceCustomColorLabel => 'Custom Color';

  @override
  String get appearanceCustomColorHint => '#FFFFFF or #FF112233';

  @override
  String get appearancePreviewTip =>
      'You can drag the image and pinch to zoom in the preview above. The preview stays close to the actual effect.';

  @override
  String get appearanceColorWhite => 'White';

  @override
  String get appearanceColorDarkGray => 'Dark Gray';

  @override
  String get appearanceColorLightBlue => 'Light Blue';

  @override
  String get appearanceColorNavy => 'Navy';

  @override
  String get appearanceColorTeal => 'Teal';

  @override
  String get appearanceColorWarmYellow => 'Warm Yellow';

  @override
  String get appearanceInvalidHttpUrl => 'Enter a valid http(s) image URL';

  @override
  String get appearanceInvalidHexColor => 'Enter #RRGGBB or #AARRGGBB';

  @override
  String get appearanceInvalidHexColorFormat => 'Invalid color code';

  @override
  String appearancePickImageFailed(Object error) {
    return 'Failed to pick image: $error';
  }

  @override
  String get appearancePickLocalImageFirst => 'Select a local image first';

  @override
  String get appearanceLocalImageMissing =>
      'The local image no longer exists. Please choose it again';

  @override
  String appearanceAutosaveFailed(Object error) {
    return 'Auto-save failed: $error';
  }

  @override
  String get chatToolCalling => 'Calling tool';

  @override
  String get chatFallbackReply =>
      'I can\'t generate a reply right now. Please try again.';

  @override
  String get chatPermissionRequired =>
      'Permissions must be enabled before running tasks';

  @override
  String chatPermissionRequiredWithNames(Object names) {
    return 'Enable these permissions before running tasks: $names';
  }

  @override
  String get chatRecentTerminalOutputNotice =>
      '[Only the most recent terminal output is shown]\n';

  @override
  String chatUserPrefix(Object text) {
    return 'User: $text\n';
  }

  @override
  String get permissionAccessibility => 'Accessibility';

  @override
  String get permissionOverlay => 'Overlay';

  @override
  String get permissionInstalledApps => 'Installed Apps Access';

  @override
  String get permissionPublicStorage => 'Public Storage Access';

  @override
  String get browserOverlayTitle => 'Agent Browser';

  @override
  String get browserOverlayClose => 'Close browser window';

  @override
  String get browserOverlayUnsupported =>
      'Browser tool view is not supported on this platform yet';

  @override
  String get networkErrorMessage =>
      'Sorry, the network stumbled just now. Please try sending it again.';

  @override
  String get rateLimitErrorMessage =>
      'Omnibot is busy right now. Please try again in a moment.';
}
