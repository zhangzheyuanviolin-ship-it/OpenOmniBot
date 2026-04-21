// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '小万';

  @override
  String get brandName => '小万';

  @override
  String get brandNameEnglish => 'Omnibot';

  @override
  String get commonLoading => '加载中';

  @override
  String get homeDrawerSearchHint => '搜索全部对话';

  @override
  String get homeDrawerClearSearch => '清空搜索';

  @override
  String get themeModeTitle => '主题模式';

  @override
  String get themeModeSubtitle => '切换浅色、深色或跟随系统外观';

  @override
  String get themeModeLight => '浅色';

  @override
  String get themeModeDark => '深色';

  @override
  String get themeModeSystem => '系统';

  @override
  String get languageTitle => '语言';

  @override
  String get languageSubtitle => '设置应用界面、Agent 提示词与工具文案的显示语言';

  @override
  String get languageFollowSystem => '跟随系统';

  @override
  String get languageZhHans => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionModelMemory => '模型与记忆';

  @override
  String get settingsSectionServiceEnvironment => '服务与环境';

  @override
  String get settingsSectionExperienceAppearance => '体验与外观';

  @override
  String get settingsSectionPermissionInfo => '权限与信息';

  @override
  String get settingsModelProviderTitle => '模型提供商';

  @override
  String get settingsModelProviderSubtitle => '配置模型地址、密钥与模型列表';

  @override
  String get settingsSceneModelTitle => '场景模型配置';

  @override
  String get settingsSceneModelSubtitle => '按场景绑定模型，未绑定场景使用默认模型';

  @override
  String get settingsLocalModelsTitle => '本地模型服务';

  @override
  String get settingsLocalModelsSubtitle => '管理本地模型、推理、API 服务与语音模型';

  @override
  String get settingsWorkspaceMemoryTitle => 'Workspace 记忆配置';

  @override
  String get settingsWorkspaceMemoryLoading => '加载中...';

  @override
  String get settingsWorkspaceMemoryEnabled => '已启用 workspace 记忆（嵌入检索可用）';

  @override
  String get settingsWorkspaceMemoryLexical => '使用 workspace 记忆（当前为词法检索）';

  @override
  String get settingsMcpToolsTitle => 'MCP 工具';

  @override
  String get settingsMcpToolsSubtitle => '添加、启停和管理远端 MCP 服务';

  @override
  String get settingsLocalServiceTitle => '本机服务';

  @override
  String get settingsLocalServiceSubtitle => '在局域网内访问小万 MCP 和 webchat 服务';

  @override
  String get settingsAlpineTitle => 'Alpine 环境';

  @override
  String get settingsAlpineSubtitle => '查看与打开应用内 Alpine 终端环境';

  @override
  String get settingsHideRecentsTitle => '后台隐藏';

  @override
  String get settingsHideRecentsSubtitle => '开启后应用将从最近任务列表中隐藏';

  @override
  String get settingsAlarmTitle => '闹钟设置';

  @override
  String get settingsAlarmSubtitle => '配置默认铃声、本地 mp3 或 mp3 直链';

  @override
  String get settingsAppearanceTitle => '外观设置';

  @override
  String get settingsAppearanceSubtitle => '配置主题模式、语言、共享背景图、聊天字号和文本颜色';

  @override
  String get settingsVibrationTitle => '振动反馈';

  @override
  String get settingsVibrationSubtitle => '执行任务时，通过振动进行操作提醒';

  @override
  String get settingsAutoBackTitle => '任务完成后自动回聊天';

  @override
  String get settingsAutoBackSubtitle => '关闭后，任务结束将停留在当前完成页面';

  @override
  String get settingsCompanionPermissionTitle => '陪伴权限授权';

  @override
  String get settingsCompanionPermissionSubtitle => '仅访问您授权的 App，隐私安全更有保障';

  @override
  String get settingsAboutTitle => '关于小万';

  @override
  String get settingsHideRecentsFailed => '设置后台隐藏失败';

  @override
  String get settingsSaveFailed => '设置失败';

  @override
  String get settingsAutoBackEnabledToast => '任务完成后将自动返回聊天';

  @override
  String get settingsAutoBackDisabledToast => '任务完成后将停留在当前页面';

  @override
  String settingsMcpEnabledToast(Object endpoint) {
    return 'MCP 已开启：$endpoint';
  }

  @override
  String get settingsMcpDisabledToast => 'MCP 已关闭';

  @override
  String get settingsMcpToggleFailed => 'MCP 开关失败';

  @override
  String get settingsCopiedAddress => '已复制访问地址';

  @override
  String get settingsCopiedToken => '已复制 Token';

  @override
  String get settingsTokenRefreshed => '已刷新 Token';

  @override
  String get settingsTokenRefreshFailed => '刷新 Token 失败';

  @override
  String get settingsMcpLocalService => '本机服务';

  @override
  String get settingsMcpAddress => '地址';

  @override
  String get settingsMcpToken => 'Token';

  @override
  String get settingsNotGenerated => '未生成';

  @override
  String get settingsCopyAddress => '复制地址';

  @override
  String get settingsCopyToken => '复制 Token';

  @override
  String get settingsRefreshToken => '刷新 Token';

  @override
  String get settingsMcpSecurityNotice =>
      '请在同一局域网内使用 Authorization: Bearer <Token> 调用 /mcp/v1/task/vlm，避免将地址或 Token 暴露到公网。';

  @override
  String get settingsInstalledAppsPermissionFailed => '请求应用列表权限失败';

  @override
  String get appearanceTitle => '外观设置';

  @override
  String get appearanceAutoSaving => '正在自动保存…';

  @override
  String get appearanceAutosaveHint => '更改会自动保存';

  @override
  String get appearanceBackgroundSource => '背景来源';

  @override
  String get appearancePreview => '效果预览';

  @override
  String get appearanceAdjustments => '效果调整';

  @override
  String get appearancePreviewChat => '聊天';

  @override
  String get appearancePreviewWorkspace => '工作区';

  @override
  String get appearanceEnableBackground => '启用背景图';

  @override
  String get appearanceEnableBackgroundSubtitle =>
      '同时作用于聊天页和 Workspace 页面，并自动保存';

  @override
  String get appearanceSourceLocal => '本地图片';

  @override
  String get appearanceSourceRemote => '图片直链';

  @override
  String get appearanceNoLocalImage => '尚未选择本地图片';

  @override
  String get appearancePickImage => '选择图片';

  @override
  String get appearanceRepickImage => '重新选择';

  @override
  String get appearanceRemoteImageUrl => '图片直链';

  @override
  String get appearanceRemoteImageUrlHint =>
      'https://example.com/background.jpg';

  @override
  String get appearanceBackgroundBlur => '背景柔化';

  @override
  String get appearanceBackgroundBlurSubtitle => '调节图片上方蒙版的柔化程度';

  @override
  String get appearanceOverlayIntensity => '蒙版强度';

  @override
  String get appearanceOverlayIntensitySubtitle => '增强统一蒙版，让页面元素更干净';

  @override
  String get appearanceOverlayBrightness => '蒙版明暗';

  @override
  String get appearanceOverlayBrightnessSubtitle => '提亮或压暗蒙版，不会直接修改原图';

  @override
  String get appearanceChatTextSize => '聊天文本大小';

  @override
  String get appearanceChatTextSizeSubtitle => '仅调整用户消息、AI 回复与思考区字号';

  @override
  String get appearanceTextColorTitle => '聊天文本颜色';

  @override
  String get appearanceTextColorSubtitle => '默认会自动跟随背景明暗，也可以改成固定颜色';

  @override
  String get appearanceTextColorAuto => '自动';

  @override
  String get appearanceCustomColorLabel => '自定义色号';

  @override
  String get appearanceCustomColorHint => '#FFFFFF 或 #FF112233';

  @override
  String get appearancePreviewTip => '图片可直接在上方预览里拖动和双指缩放，预览会尽量贴近实际效果。';

  @override
  String get appearanceColorWhite => '白';

  @override
  String get appearanceColorDarkGray => '深灰';

  @override
  String get appearanceColorLightBlue => '浅蓝';

  @override
  String get appearanceColorNavy => '藏蓝';

  @override
  String get appearanceColorTeal => '青绿';

  @override
  String get appearanceColorWarmYellow => '暖黄';

  @override
  String get appearanceInvalidHttpUrl => '请输入有效的 http(s) 图片直链';

  @override
  String get appearanceInvalidHexColor => '请输入 #RRGGBB 或 #AARRGGBB';

  @override
  String get appearanceInvalidHexColorFormat => '色号格式不正确';

  @override
  String appearancePickImageFailed(Object error) {
    return '选择图片失败：$error';
  }

  @override
  String get appearancePickLocalImageFirst => '请先选择本地图片';

  @override
  String get appearanceLocalImageMissing => '本地图片不存在，请重新选择';

  @override
  String appearanceAutosaveFailed(Object error) {
    return '自动保存失败：$error';
  }

  @override
  String get chatToolCalling => '正在调用工具';

  @override
  String get chatFallbackReply => '暂时无法生成回复，请重试。';

  @override
  String get chatPermissionRequired => '执行任务前需要先开启权限';

  @override
  String chatPermissionRequiredWithNames(Object names) {
    return '执行任务前，请先开启：$names';
  }

  @override
  String get chatRecentTerminalOutputNotice => '[只显示最近的部分终端输出]\n';

  @override
  String chatUserPrefix(Object text) {
    return '用户: $text\n';
  }

  @override
  String get permissionAccessibility => '无障碍权限';

  @override
  String get permissionOverlay => '悬浮窗权限';

  @override
  String get permissionInstalledApps => '应用列表读取权限';

  @override
  String get permissionPublicStorage => '公共文件访问';

  @override
  String get browserOverlayTitle => 'Agent Browser';

  @override
  String get browserOverlayClose => '关闭浏览器窗口';

  @override
  String get browserOverlayUnsupported => '当前平台暂不支持浏览器工具视图';

  @override
  String get networkErrorMessage => '抱歉，刚刚网络开小差了。再发一次试试？';

  @override
  String get rateLimitErrorMessage => '小万忙不过来了，等会儿再试试吧';

  @override
  String get chatHistoryArchivedTitle => '归档对话';

  @override
  String get chatHistoryTitle => '聊天记录';

  @override
  String get chatHistoryNoArchived => '暂无归档对话';

  @override
  String get chatHistoryEmpty => '暂无聊天记录';

  @override
  String get homeDrawerArchive => '归档对话';

  @override
  String get homeDrawerNewChat => '新对话';

  @override
  String get webchatNoChats => '开始一个新的对话吧';

  @override
  String get memoryCenterTitle => '记忆中心';

  @override
  String get memoryNoShortTerm => '还没有短期记忆';

  @override
  String get memoryNoShortTermDesc => '会话中的过程性信息会沉淀到短期记忆，并在后续整理后转入长期记忆。';

  @override
  String get memoryFilteredNoShortTerm => '当前筛选下还没有短期记忆';

  @override
  String get memoryFilteredNoShortTermDesc => '稍后再来看看，新的短期记忆会逐步出现。';

  @override
  String get memoryNoLongTerm => '长期记忆还未初始化';

  @override
  String get memoryNoLongTermDesc => '记忆能力启用后，你的跨会话长期记忆会在这里持续沉淀。';

  @override
  String get memoryDeleteConfirmTitle => '确定删除吗？';

  @override
  String get memoryDeleteWarning => '删除后该内容将不可找回';

  @override
  String get memoryEditDisabled => '短期记忆暂不支持编辑';

  @override
  String get memoryDeleteDisabled => '短期记忆暂不支持删除';

  @override
  String get memoryGreeting => '你好呀，\n小万会在这里收集你的记忆！';

  @override
  String memorySelectedCount(Object n) {
    return '已选择$n项';
  }

  @override
  String get memoryDeselectAll => '全不选';

  @override
  String get memoryEditTitle => '编辑记忆';

  @override
  String get memoryIdLabel => '记忆 ID';

  @override
  String get memoryMatchScore => '匹配度';

  @override
  String get memoryAdditionalInfo => '附加信息';

  @override
  String get memoryAddLongTerm => '新增长期记忆';

  @override
  String get memorySaveToLongTerm => '保存到长期记忆';

  @override
  String get memoryLongTermAdded => '长期记忆已新增';

  @override
  String get memoryEditLongTerm => '编辑长期记忆';

  @override
  String get memorySaveChanges => '保存修改';

  @override
  String get memoryDeleteLongTermConfirm => '删除这条长期记忆？';

  @override
  String get memoryLongTermDeleted => '长期记忆已删除';

  @override
  String memoryLongTermFailed(Object error) {
    return '长期记忆操作失败：$error';
  }

  @override
  String get memoryNoMemories => '暂无记忆';

  @override
  String get memoryNoMemoriesDesc => '快去探索，添加喜欢的内容吧';

  @override
  String get skillStoreTitle => '技能仓库';

  @override
  String get skillBuiltin => '内置';

  @override
  String get skillUser => '用户';

  @override
  String get skillInstalled => '已安装';

  @override
  String get skillNotInstalled => '未安装';

  @override
  String get skillEnabled => '启用中';

  @override
  String get skillDisabled => '已禁用';

  @override
  String get skillInstall => '安装';

  @override
  String get skillDelete => '删除';

  @override
  String get skillEmpty => '暂无已接入的技能';

  @override
  String get skillNoDescription => '暂无描述';

  @override
  String get skillBuiltinRemovedDesc => '该内置技能已从工作区移除，可随时重新安装。';

  @override
  String get skillDeleteTitle => '删除技能';

  @override
  String skillDeleteConfirmMsg(Object name) {
    return '确认删除\"$name\"？';
  }

  @override
  String get skillDeleted => '已删除';

  @override
  String get skillDeleteFailed => '删除失败';

  @override
  String skillInstalledMsg(Object name) {
    return '已安装 $name';
  }

  @override
  String get skillInstallFailed => '安装失败';

  @override
  String skillEnabledMsg(Object name) {
    return '已启用 $name';
  }

  @override
  String skillDisabledMsg(Object name) {
    return '已禁用 $name';
  }

  @override
  String get skillToggleFailed => '切换失败';

  @override
  String get skillLoadFailed => '加载技能仓库失败';

  @override
  String get trajectoryTitle => '轨迹';

  @override
  String get trajectoryNoRecords => '暂无执行记录';

  @override
  String get trajectoryNoRecordsDesc => '小万为你执行的视觉任务，都会在此展示';

  @override
  String get trajectoryAll => '全部';

  @override
  String get trajectoryTaskRecords => '任务记录';

  @override
  String trajectorySelectedCount(Object n) {
    return '已选择$n项';
  }

  @override
  String get trajectoryUnknownDate => '未知日期';

  @override
  String get trajectoryThreeDaysAgo => '三天前';

  @override
  String get executionHistoryTitle => '执行历史';

  @override
  String get executionHistorySubtitle => '近3次任务执行历史';

  @override
  String get executionHistoryEmpty => '暂无执行历史';

  @override
  String executionHistoryTaskLabel(Object option) {
    return '$option任务';
  }

  @override
  String get modelProviderConfigTitle => 'Provider 配置';

  @override
  String get modelProviderConfigDesc => '新增、切换并维护模型服务提供商的名称、地址与密钥。';

  @override
  String get modelProviderName => 'Provider 名称';

  @override
  String get modelProviderNameHint => '例如：DeepSeek';

  @override
  String get modelProviderBaseUrlHint => '末尾加 # 可禁用自动补全请求路径';

  @override
  String get modelProviderApiKeyHint => '未填写 API Key 时，会以无鉴权方式请求 Provider。';

  @override
  String get modelListTitle => '模型列表';

  @override
  String get modelListDesc => '支持手动补充模型，也可从当前 Provider 拉取远端模型清单。';

  @override
  String modelListCount(Object count) {
    return '共 $count 个模型';
  }

  @override
  String get modelAddPrompt => '请添加模型！';

  @override
  String get modelBuiltinProvider => '内置 Provider';

  @override
  String get modelIdEmpty => '模型 ID 不能为空且不能以 scene. 开头';

  @override
  String get modelAlreadyExists => '模型已存在';

  @override
  String get modelAdded => '已添加模型';

  @override
  String get modelDeleted => '已删除模型';

  @override
  String get modelDeleteFailed => '删除模型失败';

  @override
  String get modelIdHint => '请输入模型 ID';

  @override
  String get modelAddProviderTitle => '新增 Provider';

  @override
  String get modelAddButton => '新增';

  @override
  String get modelProviderAdded => '已新增 Provider';

  @override
  String modelProviderAddFailed(Object error) {
    return '新增 Provider 失败：$error';
  }

  @override
  String get modelDeleteProviderTitle => '删除 Provider';

  @override
  String modelDeleteProviderMsg(Object name) {
    return '确定删除\"$name\"吗？场景绑定会保留，但需要重新选择可用 Provider。';
  }

  @override
  String get modelProviderDeleted => '已删除 Provider';

  @override
  String modelProviderDeleteFailed(Object error) {
    return '删除 Provider 失败：$error';
  }

  @override
  String get sceneModelMapping => '场景映射';

  @override
  String get sceneModelMappingDesc => '按场景绑定 Provider 与模型，未绑定的场景会继续使用默认模型。';

  @override
  String get sceneModelRefreshList => '刷新模型列表';

  @override
  String get sceneModelSearchHint =>
      '点击右侧按钮后，可按 Provider 搜索、折叠并选择模型；顶部搜索框固定不随列表滚动。';

  @override
  String get sceneModelNoScenes => '暂无可配置场景';

  @override
  String get localModelsTitle => '本地模型';

  @override
  String get localModelsAutoPreheat => '打开 App 时自动预热';

  @override
  String get localModelsAutoPreheatDesc => '进入应用后自动启动本地服务，并直接加载当前模型。';

  @override
  String get localModelsInstalled => '已安装模型';

  @override
  String get localModelsInstalledDesc => '搜索、切换默认模型或删除当前设备上的模型。';

  @override
  String get localModelsSearchHint => '搜索模型名称、ID 或标签';

  @override
  String get localModelsEmpty => '还没有可用的本地模型';

  @override
  String get localModelsEmptyDesc => '先去模型市场下载一个模型，或者手动放置 MNN 模型目录。';

  @override
  String get alarmSaved => '闹钟设置已保存';

  @override
  String get alarmRingtoneSource => '铃声来源';

  @override
  String get alarmSystemDefault => '系统默认铃声';

  @override
  String get alarmSystemDefaultDesc => '无需额外配置，兼容性最好';

  @override
  String get alarmLocalMp3 => '本地 mp3';

  @override
  String get alarmLocalMp3Desc => '选择手机内 mp3 作为闹钟铃声';

  @override
  String get alarmMp3Url => 'mp3 直链';

  @override
  String get alarmMp3UrlDesc => '使用 http(s) 直链播放在线 mp3';

  @override
  String get alarmAudioPermissionDenied => '读取音频权限未授予';

  @override
  String get alarmInvalidFilePath => '文件路径无效，请重新选择';

  @override
  String get alarmSelectLocalFirst => '请先选择本地 mp3 文件';

  @override
  String get alarmEnterHttpsUrl => '请输入 http(s) 开头的 mp3 直链';

  @override
  String get alarmLocalFile => '本地文件';

  @override
  String get alarmSelectMp3 => '选择 mp3 文件';

  @override
  String get authorizePageTitle => '应用权限授权';

  @override
  String get authorizeReceiveNotifications => '接收消息通知';

  @override
  String get authorizeNotificationsDesc => '打开后可以及时了解任务进展';

  @override
  String get companionPermissionManagement => '陪伴权限管理';

  @override
  String get companionPermissionDesc => '关闭对应的授权后，小万仍会显示，但不会展示任务执行内容';

  @override
  String get companionPermissionNote => '权限说明';

  @override
  String get companionAuthorizedApps => '授权应用';

  @override
  String get storageUsageTitle => '存储占用';

  @override
  String get storageUsageSubtitle => '查看空间占用明细，支持分项清理';

  @override
  String get storageAnalyzeFailed => '存储分析失败，请重试';

  @override
  String storageCategoryCleaned(Object name, Object size) {
    return '已清理$name，释放 $size';
  }

  @override
  String get storageCleanFailed => '清理失败，请稍后重试';

  @override
  String storageCleanCategory(Object name) {
    return '清理$name';
  }

  @override
  String get storageCleanConfirmMsg => '确认清理该分类数据吗？';

  @override
  String get storageCleanScope => '清理范围';

  @override
  String get storageCleanAll => '全部';

  @override
  String get storageClean7Days => '7天前';

  @override
  String get storageClean30Days => '30天前';

  @override
  String storageStrategyName(Object name) {
    return '执行策略：$name';
  }

  @override
  String storageStrategyDone(Object size) {
    return '策略执行完成，释放 $size';
  }

  @override
  String storageStrategyPartialDone(Object count, Object size) {
    return '策略完成，释放 $size，$count 项未完全成功';
  }

  @override
  String get storageStrategyFailed => '策略执行失败，请稍后重试';

  @override
  String get storageLoadFailed => '加载失败';

  @override
  String get storageReanalyze => '重新分析';

  @override
  String get storageTotalUsage => '总占用';

  @override
  String get storageAppSize => '应用大小';

  @override
  String get storageUserData => '用户数据';

  @override
  String get storageCleanable => '可清理';

  @override
  String storageStatsSource(Object source) {
    return '统计口径：$source';
  }

  @override
  String storagePackageName(Object name) {
    return '当前包名：$name';
  }

  @override
  String get storageTrendFirst => '这是首次分析，后续将展示占用变化趋势';

  @override
  String get storageSmartCleanup => '智能清理策略';

  @override
  String get storageExecute => '执行';

  @override
  String get storageUsageAnalysis => '占用分析';

  @override
  String get storageClean => '清理';

  @override
  String get storageRiskLow => '低风险';

  @override
  String get storageRiskCaution => '谨慎';

  @override
  String get storageRiskHigh => '高风险';

  @override
  String get storageReadOnly => '只读';

  @override
  String get storageSystemStats => '系统统计（与系统设置更接近）';

  @override
  String get storageDirectoryScan => '目录扫描估算';

  @override
  String get storageAdditionalInfo => '附加信息';

  @override
  String get aboutDescription =>
      '小万，是一款以智能对话为核心的手机AI助\n手，通过语义理解与持续学习能力，协助用户\n完成信息处理、决策辅助和日常管理。';

  @override
  String get workspaceMemoryLoadFailed => '加载 workspace 记忆配置失败';

  @override
  String get workspaceSoulSaved => 'SOUL.md 已保存';

  @override
  String get workspaceSoulSaveFailed => 'SOUL.md 保存失败';

  @override
  String get workspaceChatSaved => 'CHAT.md 已保存';

  @override
  String get workspaceChatSaveFailed => 'CHAT.md 保存失败';

  @override
  String get workspaceMemorySaved => 'MEMORY.md 已保存';

  @override
  String get workspaceMemorySaveFailed => 'MEMORY.md 保存失败';

  @override
  String get workspaceEmbeddingToggleFailed => '记忆嵌入开关更新失败';

  @override
  String get workspaceRollupToggleFailed => '夜间整理开关更新失败';

  @override
  String get workspaceRollupDone => '整理完成';

  @override
  String get workspaceRollupFailed => '立即整理失败';

  @override
  String get workspaceNone => '暂无';

  @override
  String get workspaceMemoryTitle => 'Workspace 记忆';

  @override
  String get workspaceMemoryCapability => '记忆能力';

  @override
  String get workspaceEmbeddingReady => '已配置，可使用向量检索';

  @override
  String get workspaceEmbeddingNotReady => '未配置，将自动降级为词法检索';

  @override
  String get workspaceGoToConfig => '去场景模型配置记忆嵌入模型';

  @override
  String get workspaceNightlyRollup => '夜间记忆整理（22:00）';

  @override
  String workspaceLastRun(Object time) {
    return '最近运行：$time';
  }

  @override
  String workspaceNextRun(Object time) {
    return '下次运行：$time';
  }

  @override
  String get workspaceRollupNow => '立即整理一次';

  @override
  String get workspaceDocContent => '文档内容';

  @override
  String get workspaceSoulMd => 'SOUL.md（Agent 灵魂）';

  @override
  String get workspaceChatMd => 'CHAT.md（纯聊天系统提示词）';

  @override
  String get workspaceMemoryMd => 'MEMORY.md（长期记忆）';

  @override
  String get alpineNodeJs => 'Node.js 运行时';

  @override
  String get alpineNpm => 'Node.js 包管理器';

  @override
  String get alpineGit => 'Git 版本控制';

  @override
  String get alpinePython => 'Python 解释器';

  @override
  String get alpinePip => 'Python 项目与包工具';

  @override
  String get alpinePipInstall => 'Python 包安装器';

  @override
  String get alpineSshClient => 'SSH 客户端';

  @override
  String get alpineSshpass => 'SSH 密码辅助工具';

  @override
  String get alpineOpenSshServer => 'OpenSSH 服务器';

  @override
  String get alpineDetectFailed => '检测 Alpine 环境失败';

  @override
  String get alpineBootTasksLoadFailed => '读取自启动任务失败';

  @override
  String get alpineConfigOpenFailed => '打开终端环境配置失败';

  @override
  String get alpineBootTaskAdded => '已新增自启动任务';

  @override
  String get alpineBootTaskUpdated => '已更新自启动任务';

  @override
  String get alpineBootTaskSaveFailed => '保存自启动任务失败';

  @override
  String get alpineBootEnabled => '已开启应用启动时自启动';

  @override
  String get alpineBootDisabled => '已关闭自动启动';

  @override
  String get alpineBootTaskUpdateFailed => '更新任务失败';

  @override
  String get alpineDeleteBootTask => '删除自启动任务';

  @override
  String alpineDeleteBootTaskMsg(Object name) {
    return '确认删除\"$name\"吗？';
  }

  @override
  String get alpineBootTaskDeleted => '已删除自启动任务';

  @override
  String get alpineBootTaskDeleteFailed => '删除任务失败';

  @override
  String get alpineCommandSent => '启动命令已发送';

  @override
  String get alpineStartFailed => '启动任务失败';

  @override
  String get alpineDetecting => '正在检测环境';

  @override
  String alpineStartConfig(Object count) {
    return '开始配置（$count 项）';
  }

  @override
  String get alpineAllReady => '全部已就绪';

  @override
  String get alpineDetectingDesc => '正在后台检测 Alpine 内常见开发环境的版本信息。';

  @override
  String alpineReadyCount(Object ready, Object total) {
    return '已就绪 $ready/$total 项，可直接勾选缺失项并进入 ReTerminal 自动配置。';
  }

  @override
  String get alpineBootTasks => '自启动任务';

  @override
  String get alpineBootTasksDesc =>
      '打开 Omnibot 时会在后台检查已启用的任务，并在对应 ReTerminal 会话内启动命令，适合常驻服务。';

  @override
  String get alpineAddTask => '新增任务';

  @override
  String get alpineOpenTerminal => '打开终端';

  @override
  String get alpineNoTasksDesc =>
      '暂无任务。你可以添加例如 `python app.py`、`node server.js`、`./start.sh` 之类的常驻命令。';

  @override
  String get alpineBootOnAppOpen => '开机打开 app 后启动';

  @override
  String get alpineNotEnabled => '未启用';

  @override
  String get alpineRunning => '已在运行';

  @override
  String get alpineStartNow => '立即启动';

  @override
  String get alpineEdit => '编辑';

  @override
  String get alpineVersionDetected => '已检测到可用版本';

  @override
  String get alpineVersionNotFound => '未检测到';

  @override
  String get alpineTaskNameHint => '请输入任务名称';

  @override
  String get alpineCommandHint => '请输入启动命令';

  @override
  String get alpineEditBootTask => '编辑自启动任务';

  @override
  String get alpineAddBootTask => '新增自启动任务';

  @override
  String get alpineTaskName => '任务名称';

  @override
  String get alpineTaskNameExample => '例如：本地 API 服务';

  @override
  String get alpineStartCommand => '启动命令';

  @override
  String get alpineCommandExample => '例如：python app.py 或 pnpm start';

  @override
  String get alpineWorkDir => '工作目录';

  @override
  String get alpineBootAutoStart => '打开小万时自动启动';

  @override
  String get omniflowPanelTitle => 'OmniFlow 轨迹面板';

  @override
  String get omniflowPanelDesc => '管理 OmniFlow Function：查看、执行或删除 Function 资产。';

  @override
  String get omniflowFunctionList => 'Function 列表';

  @override
  String get omniflowFunctionSearch => '搜索 Function';

  @override
  String get omniflowFunctionSearchHint => '按名称、描述等关键字过滤';

  @override
  String get omniflowSettings => 'OmniFlow 设置';

  @override
  String get omniflowSettingsSubtitle => '记录高频可复用操作段，加速任务执行';

  @override
  String get omniflowEnablePreHook => '启用 OmniFlow 执行加速';

  @override
  String get omniflowAutoStartProvider => 'OmniFlow 自启动';

  @override
  String get omniflowRefresh => '刷新';

  @override
  String get omniflowProviderStart => '启动';

  @override
  String get omniflowProviderStop => '停止';

  @override
  String get omniflowProviderRestart => '重启';

  @override
  String get omniflowSaveConfig => '保存';

  @override
  String get omniflowConfigSaved => 'OmniFlow 配置已保存';

  @override
  String get omniflowConfigSaveFailed => '保存 OmniFlow 配置失败';

  @override
  String get omniflowConfigLoadFailed => '加载 OmniFlow 配置失败';

  @override
  String get omniflowFunctionsLoadFailed => '加载 Function 列表失败';

  @override
  String get omniflowTempFunctions => '临时 Function';

  @override
  String get omniflowReadyFunctions => '可用 Function';

  @override
  String get omniflowServiceAddressNotConfigured => '服务地址未配置';

  @override
  String get omniflowSkillLibrary => 'OmniFlow 技能库';

  @override
  String get omniflowServiceStatus => '服务状态';

  @override
  String get omniflowServiceStatusRunning => '运行中';

  @override
  String get omniflowServiceStatusStopped => '未运行';

  @override
  String get omniflowServiceAddress => '服务地址';

  @override
  String get omniflowDataDirectory => '数据目录';

  @override
  String get omniflowNotSet => '未设置';

  @override
  String get omniflowEnableAccelerationDesc => '执行任务前优先匹配已学习的技能';

  @override
  String get omniflowAutoStartDesc => '打开应用时自动启动技能服务';

  @override
  String get omniflowStarting => '启动中...';

  @override
  String get omniflowRestarting => '重启中...';

  @override
  String get omniflowStopping => '停止中...';

  @override
  String get omniflowViewSkillLibrary => '查看技能库';

  @override
  String get omniflowViewFunctionLibrary => '查看功能库';

  @override
  String get omniflowClearAllData => '清空所有数据';

  @override
  String get omniflowClearAllDataTitle => '清空所有数据';

  @override
  String get omniflowClearAllDataConfirm =>
      '确认清空所有 OmniFlow 数据？\n\n这将删除：\n• 所有 Functions\n• 所有 Run Logs\n• 所有 Shared Pages\n\n此操作不可恢复！';

  @override
  String get omniflowCancel => '取消';

  @override
  String get omniflowClear => '清空';

  @override
  String omniflowClearSuccess(Object functions, Object runLogs) {
    return '已清空: $functions functions, $runLogs run_logs';
  }

  @override
  String get omniflowClearFailed => '清空失败';

  @override
  String omniflowProviderActionSuccess(Object action) {
    return 'provider $action 成功';
  }

  @override
  String omniflowProviderActionFailed(Object action) {
    return 'provider $action 失败';
  }

  @override
  String get functionLibraryTitle => '功能库';

  @override
  String get functionLibrarySearchHint => '搜索功能名称或应用';

  @override
  String get functionLibraryEmpty => '暂无已学习的功能';

  @override
  String get functionLibraryEmptyDesc => '执行任务后，高频操作会自动沉淀到这里';

  @override
  String get functionLibrarySteps => '步';

  @override
  String get functionLibraryHasParams => '有参数';

  @override
  String get functionLibraryRunCount => '执行';

  @override
  String get functionLibraryId => 'ID';

  @override
  String get functionLibraryParams => '参数';

  @override
  String get functionLibrarySource => '来源';

  @override
  String get functionLibraryCreatedAt => '创建时间';

  @override
  String get functionLibraryEdit => '编辑';

  @override
  String get functionLibraryEditTitle => '编辑功能';

  @override
  String get functionLibraryEditHint => '修改功能的描述名称';

  @override
  String get functionLibraryEditPlaceholder => '输入新的描述';

  @override
  String get functionLibraryEditSuccess => '已更新';

  @override
  String get functionLibraryEditFailed => '更新失败';

  @override
  String get functionLibraryDelete => '删除';

  @override
  String get functionLibraryDeleteTitle => '删除功能';

  @override
  String functionLibraryDeleteConfirm(Object name) {
    return '确认删除「$name」？';
  }

  @override
  String get functionLibraryDeleted => '已删除';

  @override
  String get functionLibraryDeleteFailed => '删除失败';

  @override
  String get functionLibraryUpload => '上传';

  @override
  String get functionLibraryUploadTitle => '上传到云端';

  @override
  String get functionLibraryUploadSuccess => '上传成功';

  @override
  String get functionLibraryUploadFailed => '上传失败';

  @override
  String get functionLibraryDownload => '从云端下载';

  @override
  String get functionLibraryDownloadTitle => '从云端下载';

  @override
  String get functionLibraryDownloadSuccess => '下载成功';

  @override
  String get functionLibraryDownloadFailed => '下载失败';

  @override
  String get functionLibraryCloudUrlHint => '输入云端服务地址';

  @override
  String get functionLibraryConfirm => '确定';

  @override
  String get functionLibrarySyncStatus => '同步状态';

  @override
  String get functionLibrarySynced => '已同步';

  @override
  String get functionLibraryLocalOnly => '仅本地';

  @override
  String get functionLibraryCloudOnly => '仅云端';

  @override
  String get functionLibraryStartNode => '起始页面';

  @override
  String get functionLibraryEndNode => '结束页面';

  @override
  String get functionLibraryLastRun => '最近执行';

  @override
  String get functionLibraryLastRunSuccess => '成功';

  @override
  String get functionLibraryLastRunFailed => '失败';

  @override
  String get functionLibraryLastRunGoal => '任务';

  @override
  String get functionLibraryNoDescription => '无描述';
}
