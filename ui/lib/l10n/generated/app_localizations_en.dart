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
  String get languageFollowSystem => 'System';

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

  @override
  String get chatHistoryArchivedTitle => 'Archived Conversations';

  @override
  String get chatHistoryTitle => 'Chat History';

  @override
  String get chatHistoryNoArchived => 'No archived conversations';

  @override
  String get chatHistoryEmpty => 'No conversations yet';

  @override
  String get homeDrawerArchive => 'Archive';

  @override
  String get homeDrawerNewChat => 'New conversation';

  @override
  String get webchatNoChats => 'Start a new conversation';

  @override
  String get memoryCenterTitle => 'Memory Center';

  @override
  String get memoryNoShortTerm => 'No short-term memory yet';

  @override
  String get memoryNoShortTermDesc =>
      'Process information from conversations settles into short-term memory and later gets organized into long-term memory.';

  @override
  String get memoryFilteredNoShortTerm =>
      'No short-term memory under current filter';

  @override
  String get memoryFilteredNoShortTermDesc =>
      'Check back later, new short-term memories will appear gradually.';

  @override
  String get memoryNoLongTerm => 'Long-term memory not yet initialized';

  @override
  String get memoryNoLongTermDesc =>
      'Once memory capability is enabled, your cross-session long-term memories will accumulate here.';

  @override
  String get memoryDeleteConfirmTitle => 'Are you sure you want to delete?';

  @override
  String get memoryDeleteWarning => 'This action cannot be undone';

  @override
  String get memoryEditDisabled => 'Editing short-term memory is not supported';

  @override
  String get memoryDeleteDisabled =>
      'Deleting short-term memory is not supported';

  @override
  String get memoryGreeting =>
      'Hello!\nOmnibot will collect your memories here!';

  @override
  String memorySelectedCount(Object n) {
    return '$n selected';
  }

  @override
  String get memoryDeselectAll => 'Deselect all';

  @override
  String get memoryEditTitle => 'Edit Memory';

  @override
  String get memoryIdLabel => 'Memory ID';

  @override
  String get memoryMatchScore => 'Match Score';

  @override
  String get memoryAdditionalInfo => 'Additional Info';

  @override
  String get memoryAddLongTerm => 'Add Long-term Memory';

  @override
  String get memorySaveToLongTerm => 'Save to Long-term Memory';

  @override
  String get memoryLongTermAdded => 'Long-term memory added';

  @override
  String get memoryEditLongTerm => 'Edit Long-term Memory';

  @override
  String get memorySaveChanges => 'Save changes';

  @override
  String get memoryDeleteLongTermConfirm => 'Delete this long-term memory?';

  @override
  String get memoryLongTermDeleted => 'Long-term memory deleted';

  @override
  String memoryLongTermFailed(Object error) {
    return 'Long-term memory operation failed: $error';
  }

  @override
  String get memoryNoMemories => 'No memories';

  @override
  String get memoryNoMemoriesDesc => 'Start exploring and add content you like';

  @override
  String get skillStoreTitle => 'Skill Store';

  @override
  String get skillBuiltin => 'Built-in';

  @override
  String get skillUser => 'User';

  @override
  String get skillInstalled => 'Installed';

  @override
  String get skillNotInstalled => 'Not installed';

  @override
  String get skillEnabled => 'Enabled';

  @override
  String get skillDisabled => 'Disabled';

  @override
  String get skillInstall => 'Install';

  @override
  String get skillDelete => 'Delete';

  @override
  String get skillEmpty => 'No skills available';

  @override
  String get skillNoDescription => 'No description';

  @override
  String get skillBuiltinRemovedDesc =>
      'This built-in skill has been removed from the workspace. You can reinstall it anytime.';

  @override
  String get skillDeleteTitle => 'Delete Skill';

  @override
  String skillDeleteConfirmMsg(Object name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get skillDeleted => 'Deleted';

  @override
  String get skillDeleteFailed => 'Failed to delete';

  @override
  String skillInstalledMsg(Object name) {
    return 'Installed $name';
  }

  @override
  String get skillInstallFailed => 'Failed to install';

  @override
  String skillEnabledMsg(Object name) {
    return 'Enabled $name';
  }

  @override
  String skillDisabledMsg(Object name) {
    return 'Disabled $name';
  }

  @override
  String get skillToggleFailed => 'Failed to toggle';

  @override
  String get skillLoadFailed => 'Failed to load skills';

  @override
  String get trajectoryTitle => 'Trajectory';

  @override
  String get trajectoryNoRecords => 'No execution records';

  @override
  String get trajectoryNoRecordsDesc => 'VLM tasks will be displayed here';

  @override
  String get trajectoryAll => 'All';

  @override
  String get trajectoryTaskRecords => 'Task Records';

  @override
  String trajectorySelectedCount(Object n) {
    return '$n selected';
  }

  @override
  String get trajectoryUnknownDate => 'Unknown date';

  @override
  String get trajectoryThreeDaysAgo => '3 days ago';

  @override
  String get executionHistoryTitle => 'Execution History';

  @override
  String get executionHistorySubtitle => 'Recent 3 task executions';

  @override
  String get executionHistoryEmpty => 'No execution history';

  @override
  String executionHistoryTaskLabel(Object option) {
    return '$option Tasks';
  }

  @override
  String get modelProviderConfigTitle => 'Provider Configuration';

  @override
  String get modelProviderConfigDesc =>
      'Add, switch, and maintain model service provider names, addresses, and keys.';

  @override
  String get modelProviderName => 'Provider Name';

  @override
  String get modelProviderNameHint => 'e.g., DeepSeek';

  @override
  String get modelProviderBaseUrlHint =>
      'Append # to disable auto-complete request path';

  @override
  String get modelProviderApiKeyHint =>
      'Requests will be made without authentication when API Key is not filled in.';

  @override
  String get modelListTitle => 'Model List';

  @override
  String get modelListDesc =>
      'Supports manually adding models or fetching the remote model list from the current Provider.';

  @override
  String modelListCount(Object count) {
    return '$count models in total';
  }

  @override
  String get modelAddPrompt => 'Please add a model!';

  @override
  String get modelBuiltinProvider => 'Built-in Provider';

  @override
  String get modelIdEmpty =>
      'Model ID cannot be empty and cannot start with \'scene.\'';

  @override
  String get modelAlreadyExists => 'Model already exists';

  @override
  String get modelAdded => 'Model added';

  @override
  String get modelDeleted => 'Model deleted';

  @override
  String get modelDeleteFailed => 'Failed to delete model';

  @override
  String get modelIdHint => 'Enter model ID';

  @override
  String get modelAddProviderTitle => 'Add Provider';

  @override
  String get modelAddButton => 'Add';

  @override
  String get modelProviderAdded => 'Provider added';

  @override
  String modelProviderAddFailed(Object error) {
    return 'Failed to add Provider: $error';
  }

  @override
  String get modelDeleteProviderTitle => 'Delete Provider';

  @override
  String modelDeleteProviderMsg(Object name) {
    return 'Delete \"$name\"? Scene bindings will be preserved, but you need to reselect an available Provider.';
  }

  @override
  String get modelProviderDeleted => 'Provider deleted';

  @override
  String modelProviderDeleteFailed(Object error) {
    return 'Failed to delete Provider: $error';
  }

  @override
  String get sceneModelMapping => 'Scene Mapping';

  @override
  String get sceneModelMappingDesc =>
      'Bind Providers and models by scene. Unbound scenes will continue using the default model.';

  @override
  String get sceneModelRefreshList => 'Refresh model list';

  @override
  String get sceneModelSearchHint =>
      'Click the button on the right to search, collapse, and select models by Provider; the top search bar stays fixed.';

  @override
  String get sceneModelNoScenes => 'No configurable scenes';

  @override
  String get localModelsTitle => 'Local Models';

  @override
  String get localModelsAutoPreheat => 'Auto preheat on app open';

  @override
  String get localModelsAutoPreheatDesc =>
      'Automatically start local service and load the current model when entering the app.';

  @override
  String get localModelsInstalled => 'Installed Models';

  @override
  String get localModelsInstalledDesc =>
      'Search, switch default model, or delete models on the current device.';

  @override
  String get localModelsSearchHint => 'Search model name, ID, or tag';

  @override
  String get localModelsEmpty => 'No local models available';

  @override
  String get localModelsEmptyDesc =>
      'Download a model from the market, or manually place an MNN model directory.';

  @override
  String get alarmSaved => 'Alarm settings saved';

  @override
  String get alarmRingtoneSource => 'Ringtone Source';

  @override
  String get alarmSystemDefault => 'System Default';

  @override
  String get alarmSystemDefaultDesc =>
      'No extra configuration needed, best compatibility';

  @override
  String get alarmLocalMp3 => 'Local MP3';

  @override
  String get alarmLocalMp3Desc =>
      'Select an MP3 file on your phone as the alarm ringtone';

  @override
  String get alarmMp3Url => 'MP3 URL';

  @override
  String get alarmMp3UrlDesc => 'Use an HTTP(S) URL to play an online MP3';

  @override
  String get alarmAudioPermissionDenied => 'Audio read permission not granted';

  @override
  String get alarmInvalidFilePath => 'Invalid file path, please select again';

  @override
  String get alarmSelectLocalFirst => 'Please select a local MP3 file first';

  @override
  String get alarmEnterHttpsUrl => 'Please enter an HTTP(S) MP3 URL';

  @override
  String get alarmLocalFile => 'Local File';

  @override
  String get alarmSelectMp3 => 'Select MP3 File';

  @override
  String get authorizePageTitle => 'App Permission Authorization';

  @override
  String get authorizeReceiveNotifications => 'Receive message notifications';

  @override
  String get authorizeNotificationsDesc =>
      'Enable this to get task progress updates in time';

  @override
  String get companionPermissionManagement => 'Companion Permission Management';

  @override
  String get companionPermissionDesc =>
      'After revoking authorization, Omnibot will still be displayed but task execution content will be hidden';

  @override
  String get companionPermissionNote => 'Permission Notes';

  @override
  String get companionAuthorizedApps => 'Authorized Apps';

  @override
  String get storageUsageTitle => 'Storage Usage';

  @override
  String get storageUsageSubtitle =>
      'View storage usage details and clean up by category';

  @override
  String get storageAnalyzeFailed =>
      'Storage analysis failed, please try again';

  @override
  String storageCategoryCleaned(Object name, Object size) {
    return 'Cleaned $name, freed $size';
  }

  @override
  String get storageCleanFailed => 'Cleanup failed, please try again later';

  @override
  String storageCleanCategory(Object name) {
    return 'Clean $name';
  }

  @override
  String get storageCleanConfirmMsg => 'Confirm cleanup of this category?';

  @override
  String get storageCleanScope => 'Cleanup Scope';

  @override
  String get storageCleanAll => 'All';

  @override
  String get storageClean7Days => '7 days ago';

  @override
  String get storageClean30Days => '30 days ago';

  @override
  String storageStrategyName(Object name) {
    return 'Strategy: $name';
  }

  @override
  String storageStrategyDone(Object size) {
    return 'Strategy completed, freed $size';
  }

  @override
  String storageStrategyPartialDone(Object count, Object size) {
    return 'Strategy completed, freed $size, $count items not fully successful';
  }

  @override
  String get storageStrategyFailed => 'Strategy failed, please try again later';

  @override
  String get storageLoadFailed => 'Failed to load';

  @override
  String get storageReanalyze => 'Reanalyze';

  @override
  String get storageTotalUsage => 'Total Usage';

  @override
  String get storageAppSize => 'App Size';

  @override
  String get storageUserData => 'User Data';

  @override
  String get storageCleanable => 'Cleanable';

  @override
  String storageStatsSource(Object source) {
    return 'Statistics source: $source';
  }

  @override
  String storagePackageName(Object name) {
    return 'Current package: $name';
  }

  @override
  String get storageTrendFirst =>
      'This is the first analysis. Usage trends will be shown in future analyses.';

  @override
  String get storageSmartCleanup => 'Smart Cleanup';

  @override
  String get storageExecute => 'Execute';

  @override
  String get storageUsageAnalysis => 'Usage Analysis';

  @override
  String get storageClean => 'Clean';

  @override
  String get storageRiskLow => 'Low Risk';

  @override
  String get storageRiskCaution => 'Caution';

  @override
  String get storageRiskHigh => 'High Risk';

  @override
  String get storageReadOnly => 'Read Only';

  @override
  String get storageSystemStats =>
      'System statistics (closer to system settings)';

  @override
  String get storageDirectoryScan => 'Directory scan estimate';

  @override
  String get storageAdditionalInfo => 'Additional Info';

  @override
  String get aboutDescription =>
      'Omnibot is an AI assistant app centered on\nintelligent conversation, using semantic understanding\nand continuous learning to help with information\nprocessing, decision support, and daily management.';

  @override
  String get workspaceMemoryLoadFailed =>
      'Failed to load workspace memory config';

  @override
  String get workspaceSoulSaved => 'SOUL.md saved';

  @override
  String get workspaceSoulSaveFailed => 'Failed to save SOUL.md';

  @override
  String get workspaceChatSaved => 'CHAT.md saved';

  @override
  String get workspaceChatSaveFailed => 'Failed to save CHAT.md';

  @override
  String get workspaceMemorySaved => 'MEMORY.md saved';

  @override
  String get workspaceMemorySaveFailed => 'Failed to save MEMORY.md';

  @override
  String get workspaceEmbeddingToggleFailed =>
      'Failed to update memory embedding toggle';

  @override
  String get workspaceRollupToggleFailed =>
      'Failed to update nightly rollup toggle';

  @override
  String get workspaceRollupDone => 'Rollup completed';

  @override
  String get workspaceRollupFailed => 'Rollup failed';

  @override
  String get workspaceNone => 'None';

  @override
  String get workspaceMemoryTitle => 'Workspace Memory';

  @override
  String get workspaceMemoryCapability => 'Memory Capability';

  @override
  String get workspaceEmbeddingReady =>
      'Configured, vector retrieval available';

  @override
  String get workspaceEmbeddingNotReady =>
      'Not configured, will fall back to lexical retrieval';

  @override
  String get workspaceGoToConfig =>
      'Go to scene model config to set up embedding model';

  @override
  String get workspaceNightlyRollup => 'Nightly Memory Rollup (22:00)';

  @override
  String workspaceLastRun(Object time) {
    return 'Last run: $time';
  }

  @override
  String workspaceNextRun(Object time) {
    return 'Next run: $time';
  }

  @override
  String get workspaceRollupNow => 'Rollup now';

  @override
  String get workspaceDocContent => 'Document Content';

  @override
  String get workspaceSoulMd => 'SOUL.md (Agent Soul)';

  @override
  String get workspaceChatMd => 'CHAT.md (Chat-only system prompt)';

  @override
  String get workspaceMemoryMd => 'MEMORY.md (Long-term Memory)';

  @override
  String get alpineNodeJs => 'Node.js Runtime';

  @override
  String get alpineNpm => 'Node.js Package Manager';

  @override
  String get alpineGit => 'Git Version Control';

  @override
  String get alpinePython => 'Python Interpreter';

  @override
  String get alpinePip => 'Python Projects & Packages';

  @override
  String get alpinePipInstall => 'Python Package Installer';

  @override
  String get alpineSshClient => 'SSH Client';

  @override
  String get alpineSshpass => 'SSH Password Helper';

  @override
  String get alpineOpenSshServer => 'OpenSSH Server';

  @override
  String get alpineDetectFailed => 'Failed to detect Alpine environment';

  @override
  String get alpineBootTasksLoadFailed => 'Failed to load boot tasks';

  @override
  String get alpineConfigOpenFailed =>
      'Failed to open terminal environment config';

  @override
  String get alpineBootTaskAdded => 'Boot task added';

  @override
  String get alpineBootTaskUpdated => 'Boot task updated';

  @override
  String get alpineBootTaskSaveFailed => 'Failed to save boot task';

  @override
  String get alpineBootEnabled => 'Enabled auto-start on app launch';

  @override
  String get alpineBootDisabled => 'Disabled auto-start';

  @override
  String get alpineBootTaskUpdateFailed => 'Failed to update task';

  @override
  String get alpineDeleteBootTask => 'Delete Boot Task';

  @override
  String alpineDeleteBootTaskMsg(Object name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get alpineBootTaskDeleted => 'Boot task deleted';

  @override
  String get alpineBootTaskDeleteFailed => 'Failed to delete task';

  @override
  String get alpineCommandSent => 'Start command sent';

  @override
  String get alpineStartFailed => 'Failed to start task';

  @override
  String get alpineDetecting => 'Detecting environment';

  @override
  String alpineStartConfig(Object count) {
    return 'Start configuration ($count items)';
  }

  @override
  String get alpineAllReady => 'All ready';

  @override
  String get alpineDetectingDesc =>
      'Detecting version info of common development tools in Alpine in the background.';

  @override
  String alpineReadyCount(Object ready, Object total) {
    return '$ready/$total items ready. Check missing items and auto-configure in ReTerminal.';
  }

  @override
  String get alpineBootTasks => 'Boot Tasks';

  @override
  String get alpineBootTasksDesc =>
      'When Omnibot opens, enabled tasks are checked in the background and commands are started in the corresponding ReTerminal session. Suitable for persistent services.';

  @override
  String get alpineAddTask => 'Add Task';

  @override
  String get alpineOpenTerminal => 'Open Terminal';

  @override
  String get alpineNoTasksDesc =>
      'No tasks. You can add persistent commands like `python app.py`, `node server.js`, or `./start.sh`.';

  @override
  String get alpineBootOnAppOpen => 'Start after app opens on boot';

  @override
  String get alpineNotEnabled => 'Not enabled';

  @override
  String get alpineRunning => 'Running';

  @override
  String get alpineStartNow => 'Start Now';

  @override
  String get alpineEdit => 'Edit';

  @override
  String get alpineVersionDetected => 'Version detected';

  @override
  String get alpineVersionNotFound => 'Not detected';

  @override
  String get alpineTaskNameHint => 'Enter task name';

  @override
  String get alpineCommandHint => 'Enter start command';

  @override
  String get alpineEditBootTask => 'Edit Boot Task';

  @override
  String get alpineAddBootTask => 'Add Boot Task';

  @override
  String get alpineTaskName => 'Task Name';

  @override
  String get alpineTaskNameExample => 'e.g., Local API service';

  @override
  String get alpineStartCommand => 'Start Command';

  @override
  String get alpineCommandExample => 'e.g., python app.py or pnpm start';

  @override
  String get alpineWorkDir => 'Working Directory';

  @override
  String get alpineBootAutoStart => 'Auto-start when Omnibot opens';

  @override
  String get omniflowPanelTitle => 'OmniFlow Trajectory Panel';

  @override
  String get omniflowPanelDesc =>
      'Manage OmniFlow Functions: view, execute, or delete Function assets.';

  @override
  String get omniflowFunctionList => 'Function List';

  @override
  String get omniflowFunctionSearch => 'Search Functions';

  @override
  String get omniflowFunctionSearchHint => 'Filter by name, description, etc.';

  @override
  String get omniflowSettings => 'OmniFlow Settings';

  @override
  String get omniflowSettingsSubtitle =>
      'Record reusable action sequences to accelerate tasks';

  @override
  String get omniflowEnablePreHook => 'Enable OmniFlow Acceleration';

  @override
  String get omniflowAutoStartProvider => 'OmniFlow Auto-start';

  @override
  String get omniflowRefresh => 'Refresh';

  @override
  String get omniflowProviderStart => 'Start';

  @override
  String get omniflowProviderStop => 'Stop';

  @override
  String get omniflowProviderRestart => 'Restart';

  @override
  String get omniflowSaveConfig => 'Save';

  @override
  String get omniflowConfigSaved => 'OmniFlow config saved';

  @override
  String get omniflowConfigSaveFailed => 'Failed to save OmniFlow config';

  @override
  String get omniflowConfigLoadFailed => 'Failed to load OmniFlow config';

  @override
  String get omniflowFunctionsLoadFailed => 'Failed to load Functions';

  @override
  String get omniflowTempFunctions => 'Temporary Functions';

  @override
  String get omniflowReadyFunctions => 'Ready Functions';

  @override
  String get omniflowServiceAddressNotConfigured =>
      'Service address not configured';

  @override
  String get omniflowSkillLibrary => 'OmniFlow Skill Library';

  @override
  String get omniflowServiceStatus => 'Service Status';

  @override
  String get omniflowServiceStatusRunning => 'Running';

  @override
  String get omniflowServiceStatusStopped => 'Not Running';

  @override
  String get omniflowServiceAddress => 'Service Address';

  @override
  String get omniflowDataDirectory => 'Data Directory';

  @override
  String get omniflowNotSet => 'Not set';

  @override
  String get omniflowEnableAccelerationDesc =>
      'Match learned skills before executing tasks';

  @override
  String get omniflowAutoStartDesc => 'Auto-start skill service when app opens';

  @override
  String get omniflowStarting => 'Starting...';

  @override
  String get omniflowRestarting => 'Restarting...';

  @override
  String get omniflowStopping => 'Stopping...';

  @override
  String get omniflowViewSkillLibrary => 'View Skill Library';

  @override
  String get omniflowViewFunctionLibrary => 'View Functions';

  @override
  String get omniflowClearAllData => 'Clear All Data';

  @override
  String get omniflowClearAllDataTitle => 'Clear All Data';

  @override
  String get omniflowClearAllDataConfirm =>
      'Confirm clear all OmniFlow data?\n\nThis will delete:\n• All Functions\n• All Run Logs\n• All Shared Pages\n\nThis action cannot be undone!';

  @override
  String get omniflowCancel => 'Cancel';

  @override
  String get omniflowClear => 'Clear';

  @override
  String omniflowClearSuccess(Object functions, Object runLogs) {
    return 'Cleared: $functions functions, $runLogs run_logs';
  }

  @override
  String get omniflowClearFailed => 'Clear failed';

  @override
  String omniflowProviderActionSuccess(Object action) {
    return 'provider $action success';
  }

  @override
  String omniflowProviderActionFailed(Object action) {
    return 'provider $action failed';
  }

  @override
  String get functionLibraryTitle => 'Functions';

  @override
  String get functionLibrarySearchHint => 'Search functions or apps';

  @override
  String get functionLibraryEmpty => 'No learned functions yet';

  @override
  String get functionLibraryEmptyDesc =>
      'Frequently used actions will be saved here after task execution';

  @override
  String get functionLibrarySteps => 'steps';

  @override
  String get functionLibraryHasParams => 'has params';

  @override
  String get functionLibraryRunCount => 'runs';

  @override
  String get functionLibraryId => 'ID';

  @override
  String get functionLibraryParams => 'Params';

  @override
  String get functionLibrarySource => 'Source';

  @override
  String get functionLibraryCreatedAt => 'Created';

  @override
  String get functionLibraryDelete => 'Delete';

  @override
  String get functionLibraryDeleteTitle => 'Delete Function';

  @override
  String functionLibraryDeleteConfirm(Object name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get functionLibraryDeleted => 'Deleted';

  @override
  String get functionLibraryDeleteFailed => 'Delete failed';

  @override
  String get functionLibraryUpload => 'Upload';

  @override
  String get functionLibraryUploadTitle => 'Upload to Cloud';

  @override
  String get functionLibraryUploadSuccess => 'Upload successful';

  @override
  String get functionLibraryUploadFailed => 'Upload failed';

  @override
  String get functionLibraryDownload => 'Download from Cloud';

  @override
  String get functionLibraryDownloadTitle => 'Download from Cloud';

  @override
  String get functionLibraryDownloadSuccess => 'Download successful';

  @override
  String get functionLibraryDownloadFailed => 'Download failed';

  @override
  String get functionLibraryCloudUrlHint => 'Enter cloud service URL';

  @override
  String get functionLibraryConfirm => 'Confirm';

  @override
  String get functionLibrarySyncStatus => 'Sync Status';

  @override
  String get functionLibrarySynced => 'Synced';

  @override
  String get functionLibraryLocalOnly => 'Local Only';

  @override
  String get functionLibraryCloudOnly => 'Cloud Only';
}
