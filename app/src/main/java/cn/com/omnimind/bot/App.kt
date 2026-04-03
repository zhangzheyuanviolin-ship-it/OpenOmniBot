package cn.com.omnimind.bot

import BaseApplication
import cn.com.omnimind.baselib.database.DatabaseHelper
import cn.com.omnimind.baselib.llm.LocalModelProviderBridge
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.agent.AgentWorkspaceManager
import cn.com.omnimind.bot.agent.AgentAiCapabilityConfigSync
import cn.com.omnimind.bot.agent.SkillIndexService
import cn.com.omnimind.bot.agent.WorkspaceMemoryRollupScheduler
import cn.com.omnimind.bot.agent.WorkspaceScheduledTaskScheduler
import cn.com.omnimind.bot.mcp.McpServerManager
import cn.com.omnimind.bot.mnnlocal.MnnLocalInitializer
import cn.com.omnimind.bot.terminal.EmbeddedTerminalRuntime
import cn.com.omnimind.bot.update.AppUpdateManager
import cn.com.omnimind.bot.util.NestedBackgroundStateUtil
import com.rk.resources.Res
import com.tencent.mmkv.MMKV
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch


class App : BaseApplication() {
    companion object {
        lateinit var instance: App

        // FlutterEngineGroup 用于管理多个共享资源的引擎
        private var flutterEngineGroup: FlutterEngineGroup? = null

        // 主引擎缓存
        private var cachedMainEngine: FlutterEngine? = null

        /**
         * 获取 FlutterEngineGroup 实例
         */
        fun getFlutterEngineGroup(): FlutterEngineGroup {
            if (flutterEngineGroup == null) {
                flutterEngineGroup = FlutterEngineGroup(instance)
                OmniLog.d("AppStartup", "FlutterEngineGroup created")
            }
            return flutterEngineGroup!!
        }

        /**
         * 获取缓存的主引擎，如果不存在则创建
         */
        fun getCachedMainEngine(): FlutterEngine {
            if (cachedMainEngine == null) {
                val engineStart = System.currentTimeMillis()
                OmniLog.d("AppStartup", "Creating main engine from FlutterEngineGroup")

                cachedMainEngine = getFlutterEngineGroup().createAndRunDefaultEngine(instance)

                OmniLog.d(
                    "AppStartup",
                    "Main engine created, cost: ${System.currentTimeMillis() - engineStart}ms"
                )
            }
            return cachedMainEngine!!
        }

        /**
         * 从 FlutterEngineGroup 创建一个新的引擎（用于半屏等场景）
         * 这个引擎会共享主引擎的大部分资源，创建速度很快
         */
        fun createEngineFromGroup(): FlutterEngine {
            val engineStart = System.currentTimeMillis()
            OmniLog.d(
                "AppStartup",
                "Creating secondary engine from FlutterEngineGroup with subEngineMain entry point"
            )

            val dartEntrypoint = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "subEngineMain"
            )

            val options = FlutterEngineGroup.Options(instance)
                .setDartEntrypoint(dartEntrypoint)

            val engine = getFlutterEngineGroup().createAndRunEngine(options)

            OmniLog.d(
                "AppStartup",
                "Secondary engine created with subEngineMain, cost: ${System.currentTimeMillis() - engineStart}ms"
            )
            return engine
        }
    }


    @OptIn(DelicateCoroutinesApi::class)
    override fun onCreate() {
        val appStartTime = System.currentTimeMillis()
        OmniLog.d("AppStartup", "App onCreate start")
        super.onCreate()
        OmniLog.d(
            "AppStartup",
            "App super.onCreate cost: ${System.currentTimeMillis() - appStartTime}ms"
        )
        instance = this
        com.rk.libcommons.application = this
        Res.application = this

        // MMKV 必须最先初始化，用于检查隐私政策状态
        MMKV.initialize(this)

        // OSS 版本统一使用固定本地数据库，不依赖历史账号分库
        DatabaseHelper.init(this)
        MnnLocalInitializer.initialize(this)
        LocalModelProviderBridge.setDelegate(
            object : LocalModelProviderBridge.Delegate {
                override suspend fun prepareForRequest(
                    profileId: String?,
                    apiBase: String?,
                    modelId: String
                ): Boolean {
                    return runCatching {
                        MnnLocalInitializer.initialize(this@App)
                        cn.com.omnimind.bot.mnnlocal.MnnLocalModelsManager.ensureApiServiceForModel(
                            modelId = modelId
                        )
                    }.getOrDefault(false)
                }
            }
        )

        val nestedStart = System.currentTimeMillis()
        NestedBackgroundStateUtil.init(this)
        OmniLog.d(
            "AppStartup",
            "NestedBackgroundStateUtil.init cost: ${System.currentTimeMillis() - nestedStart}ms"
        )

        // 初始化 ModelSceneRegistry（必须在 Application.onCreate 中调用）
        val registryStart = System.currentTimeMillis()
        cn.com.omnimind.baselib.llm.ModelSceneRegistry.init(this)
        OmniLog.d(
            "AppStartup",
            "ModelSceneRegistry.init cost: ${System.currentTimeMillis() - registryStart}ms"
        )
        runCatching {
            val workspaceManager = AgentWorkspaceManager(this)
            workspaceManager.ensureRuntimeDirectories()
            SkillIndexService(this, workspaceManager).seedBuiltinSkillsIfNeeded()
        }
        runCatching {
            AgentAiCapabilityConfigSync.get(this).initialize()
        }
        runCatching {
            WorkspaceMemoryRollupScheduler(this).ensureScheduledIfEnabled()
        }
        runCatching {
            WorkspaceScheduledTaskScheduler(this).rescheduleAllEnabled()
        }

        // 如果用户已同意隐私政策，初始化需要隐私授权的能力并检查更新
        initSDKsAfterPrivacyConsent()
        // 恢复 MCP 服务（如果之前已启用）
        McpServerManager.restoreIfEnabled(this)
        CoroutineScope(Dispatchers.IO).launch {
            runCatching {
                EmbeddedTerminalRuntime.warmup(this@App)
            }
        }
        OmniLog.d(
            "AppStartup",
            "App onCreate total cost: ${System.currentTimeMillis() - appStartTime}ms"
        )
    }

    /**
     * 隐私政策同意后初始化需要网络访问的能力
     */
    fun initSDKsAfterPrivacyConsent() {
        OmniLog.d("AppStartup", "initSDKsAfterPrivacyConsent start")
        AppUpdateManager.requestSilentCheckIfDue(this)
        OmniLog.d("AppStartup", "initSDKsAfterPrivacyConsent completed")
    }
}
