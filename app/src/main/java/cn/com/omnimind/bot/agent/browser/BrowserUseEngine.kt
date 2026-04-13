package cn.com.omnimind.bot.agent

import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.util.Locale
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private const val DEFAULT_BROWSER_SCROLL_AMOUNT = 500
private const val DEFAULT_BROWSER_SCROLL_COUNT = 10
private const val MAX_BROWSER_SCROLL_COUNT = 20
private const val DEFAULT_BROWSER_MAX_DEPTH = 5
private const val MAX_BROWSER_TABS = 3
private const val NAVIGATION_TIMEOUT_MS = 30_000L
private const val ACTION_SETTLE_DELAY_MS = 250L
private const val LOAD_SETTLE_DELAY_MS = 600L
private const val DESKTOP_VIEWPORT_WIDTH = 1280
private const val DESKTOP_VIEWPORT_HEIGHT = 800
private const val SCREENSHOT_JPEG_QUALITY = 85
private const val READ_IMAGE_JPEG_QUALITY = 75
private const val READ_IMAGE_MAX_WIDTH = 1280
private const val LARGE_TEXT_THRESHOLD = 12_000
private const val FIND_ELEMENTS_LIMIT = 60

enum class BrowserUserAgentProfile(
    val wireName: String,
    val userAgentString: String
) {
    DESKTOP_SAFARI(
        wireName = "desktop_safari",
        userAgentString = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    ),
    MOBILE_SAFARI(
        wireName = "mobile_safari",
        userAgentString = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
    );

    companion object {
        fun fromWire(value: String?): BrowserUserAgentProfile? {
            val normalized = value?.trim()?.lowercase(Locale.ROOT).orEmpty()
            return entries.firstOrNull { it.wireName == normalized }
        }

        fun defaultProfile(): BrowserUserAgentProfile = DESKTOP_SAFARI
    }
}

enum class BrowserUseAction(val wireName: String) {
    NAVIGATE("navigate"),
    SCREENSHOT("screenshot"),
    CLICK("click"),
    TYPE("type"),
    GET_TEXT("get_text"),
    SCROLL("scroll"),
    GET_PAGE_INFO("get_page_info"),
    EXECUTE_JS("execute_js"),
    FIND_ELEMENTS("find_elements"),
    HOVER("hover"),
    GET_READABLE("get_readable"),
    SET_USER_AGENT("set_user_agent"),
    GET_BACKBONE("get_backbone"),
    FETCH("fetch"),
    NEW_TAB("new_tab"),
    CLOSE_TAB("close_tab"),
    LIST_TABS("list_tabs"),
    GET_COOKIES("get_cookies"),
    SCROLL_AND_COLLECT("scroll_and_collect"),
    GO_BACK("go_back"),
    GO_FORWARD("go_forward"),
    PRESS_KEY("press_key"),
    WAIT_FOR_SELECTOR("wait_for_selector");

    companion object {
        fun fromWire(value: String?): BrowserUseAction? {
            val normalized = value?.trim()?.lowercase(Locale.ROOT).orEmpty()
            return entries.firstOrNull { it.wireName == normalized }
        }
    }
}

data class BrowserUseRequest(
    val toolTitle: String,
    val action: BrowserUseAction,
    val text: String? = null,
    val url: String? = null,
    val userAgent: BrowserUserAgentProfile? = null,
    val script: String? = null,
    val coordinateX: Int? = null,
    val coordinateY: Int? = null,
    val amount: Int = DEFAULT_BROWSER_SCROLL_AMOUNT,
    val keywords: List<String> = emptyList(),
    val itemSelector: String? = null,
    val direction: String? = null,
    val tabId: Int? = null,
    val selector: String? = null,
    val fuzzy: Boolean = true,
    val readImage: Boolean = false,
    val key: String? = null,
    val timeoutMs: Long = 5000L,
    val maxDepth: Int = DEFAULT_BROWSER_MAX_DEPTH,
    val scrollCount: Int = DEFAULT_BROWSER_SCROLL_COUNT
) {
    companion object {
        fun fromJson(args: JsonObject): BrowserUseRequest {
            val toolTitle = args["tool_title"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
            require(toolTitle.isNotEmpty()) { "browser_use 缺少 tool_title" }

            val action = BrowserUseAction.fromWire(
                args["action"]?.jsonPrimitive?.contentOrNull
            ) ?: throw IllegalArgumentException("browser_use action 非法或缺失")

            val coordinateX = args["coordinate_x"]?.jsonPrimitive?.intOrNull
            val coordinateY = args["coordinate_y"]?.jsonPrimitive?.intOrNull
            if ((coordinateX == null) != (coordinateY == null)) {
                throw IllegalArgumentException("coordinate_x 和 coordinate_y 必须同时提供")
            }

            val amount = args["amount"]?.jsonPrimitive?.intOrNull
                ?.coerceIn(1, 20_000)
                ?: DEFAULT_BROWSER_SCROLL_AMOUNT
            val maxDepth = args["max_depth"]?.jsonPrimitive?.intOrNull
                ?.coerceIn(1, 8)
                ?: DEFAULT_BROWSER_MAX_DEPTH
            val scrollCount = args["scroll_count"]?.jsonPrimitive?.intOrNull
                ?.coerceIn(1, MAX_BROWSER_SCROLL_COUNT)
                ?: DEFAULT_BROWSER_SCROLL_COUNT
            val fuzzy = args["fuzzy"]?.jsonPrimitive?.booleanOrNull ?: true
            val readImage = args["read_image"]?.jsonPrimitive?.booleanOrNull ?: false
            val key = args["key"]?.jsonPrimitive?.contentOrNull
            val timeoutMs = args["timeout_ms"]?.jsonPrimitive?.intOrNull
                ?.toLong()?.coerceIn(500, 30_000)
                ?: 5000L

            val request = BrowserUseRequest(
                toolTitle = toolTitle,
                action = action,
                text = args["text"]?.jsonPrimitive?.contentOrNull,
                url = args["url"]?.jsonPrimitive?.contentOrNull,
                userAgent = BrowserUserAgentProfile.fromWire(
                    args["user_agent"]?.jsonPrimitive?.contentOrNull
                ),
                script = args["script"]?.jsonPrimitive?.contentOrNull,
                coordinateX = coordinateX,
                coordinateY = coordinateY,
                amount = amount,
                keywords = BrowserUseSupport.normalizeKeywords(args["keywords"]),
                itemSelector = args["item_selector"]?.jsonPrimitive?.contentOrNull,
                direction = args["direction"]?.jsonPrimitive?.contentOrNull,
                tabId = args["tab_id"]?.jsonPrimitive?.intOrNull,
                selector = args["selector"]?.jsonPrimitive?.contentOrNull,
                fuzzy = fuzzy,
                readImage = readImage,
                key = key,
                timeoutMs = timeoutMs,
                maxDepth = maxDepth,
                scrollCount = scrollCount
            )
            request.validate()
            return request
        }
    }

    private fun validate() {
        when (action) {
            BrowserUseAction.NAVIGATE -> require(!url.isNullOrBlank()) { "navigate 缺少 url" }
            BrowserUseAction.CLICK,
            BrowserUseAction.HOVER -> require(hasSelectorOrCoordinates()) {
                "${action.wireName} 需要 selector 或 coordinate_x/coordinate_y"
            }
            BrowserUseAction.TYPE -> {
                require(!text.isNullOrBlank()) { "type 缺少 text" }
                require(hasSelectorOrCoordinates()) {
                    "type 需要 selector 或 coordinate_x/coordinate_y"
                }
            }
            BrowserUseAction.EXECUTE_JS -> require(!script.isNullOrBlank()) { "execute_js 缺少 script" }
            BrowserUseAction.SET_USER_AGENT -> require(userAgent != null) { "set_user_agent 缺少 user_agent" }
            BrowserUseAction.FETCH -> require(!url.isNullOrBlank()) { "fetch 缺少 url" }
            BrowserUseAction.PRESS_KEY -> require(!key.isNullOrBlank()) { "press_key 缺少 key" }
            BrowserUseAction.WAIT_FOR_SELECTOR -> require(!selector.isNullOrBlank()) { "wait_for_selector 缺少 selector" }
            else -> Unit
        }
    }

    fun hasCoordinates(): Boolean = coordinateX != null && coordinateY != null

    fun hasSelectorOrCoordinates(): Boolean {
        return !selector.isNullOrBlank() || hasCoordinates()
    }
}

data class BrowserUseOutcome(
    val summaryText: String,
    val payload: Map<String, Any?>,
    val artifacts: List<ArtifactRef> = emptyList(),
    val actions: List<ArtifactAction> = emptyList(),
    val imageDataUrl: String? = null
)

object BrowserUseSupport {
    fun normalizeKeywords(element: JsonElement?): List<String> {
        return when (element) {
            null,
            JsonNull -> emptyList()
            is JsonArray -> element.mapNotNull { entry ->
                (entry as? JsonPrimitive)?.contentOrNull
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
            }
            is JsonPrimitive -> element.contentOrNull
                ?.trim()
                ?.split(Regex("\\s+"))
                ?.mapNotNull { value -> value.trim().takeIf { it.isNotEmpty() } }
                ?: emptyList()
            else -> emptyList()
        }
    }

    fun filterCookieNames(
        names: Collection<String>,
        keywords: List<String>,
        fuzzy: Boolean
    ): List<String> {
        if (keywords.isEmpty()) return names.sortedBy { it.lowercase(Locale.ROOT) }
        val normalizedKeywords = keywords.map { it.lowercase(Locale.ROOT) }
        return names.filter { name ->
            val normalizedName = name.lowercase(Locale.ROOT)
            if (fuzzy) {
                normalizedKeywords.all { keyword -> normalizedName.contains(keyword) }
            } else {
                normalizedKeywords.any { keyword -> normalizedName == keyword }
            }
        }.sortedBy { it.lowercase(Locale.ROOT) }
    }

    fun sanitizeCookieEnvName(cookieName: String): String {
        val normalized = cookieName.uppercase(Locale.ROOT)
            .replace(Regex("[^A-Z0-9_]"), "_")
            .trim('_')
        return if (normalized.isBlank()) {
            "COOKIE_VALUE"
        } else {
            "COOKIE_$normalized"
        }
    }

    fun escapeShellValue(value: String): String {
        return value.replace("'", "'\"'\"'")
    }
}

class BrowserUseEngine(
    private val context: Context,
    private val workspaceManager: AgentWorkspaceManager,
    agentRunId: String,
    workspace: AgentWorkspaceDescriptor
) : AgentBrowserLiveSessionHandle {
    private data class LoadSnapshot(
        val url: String?,
        val title: String?,
        val errorMessage: String? = null
    )

    private data class BrowserTab(
        val tabId: Int,
        val contextWrapper: MutableContextWrapper,
        val webView: WebView,
        var userAgentProfile: BrowserUserAgentProfile,
        var currentUrl: String? = null,
        var title: String? = null,
        var lastError: String? = null,
        var isLoading: Boolean = false,
        var loadWaiter: CompletableDeferred<LoadSnapshot>? = null,
        var helpersInjected: Boolean = false
    )

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
        prettyPrint = true
    }
    companion object {
        fun unavailableSnapshot(workspaceId: String = ""): Map<String, Any?> {
            return linkedMapOf(
                "available" to false,
                "workspaceId" to workspaceId,
                "activeTabId" to null,
                "currentUrl" to "",
                "title" to "",
                "userAgentProfile" to null
            )
        }

        private const val JS_HELPERS_FULL = """
                function normalizeText(value) {
                    return String(value || '').replace(/\s+/g, ' ').trim();
                }
                function isVisible(node) {
                    if (!node || !(node instanceof Element)) return false;
                    const style = window.getComputedStyle(node);
                    if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
                    const rect = node.getBoundingClientRect();
                    return rect.width > 0 && rect.height > 0;
                }
                function isInteractive(node) {
                    if (!node || !(node instanceof Element)) return false;
                    const tag = (node.tagName || '').toLowerCase();
                    return ['a', 'button', 'input', 'textarea', 'select', 'summary'].includes(tag) ||
                        !!node.getAttribute('onclick') ||
                        !!node.getAttribute('role') && ['button', 'link', 'textbox', 'tab'].includes(node.getAttribute('role'));
                }
                function selectorForElement(node) {
                    if (!node || !(node instanceof Element)) return null;
                    if (node.id) return '#' + node.id;
                    const classes = Array.from(node.classList || []).slice(0, 2).join('.');
                    return node.tagName.toLowerCase() + (classes ? '.' + classes : '');
                }
                function describeElement(node) {
                    if (!node || !(node instanceof Element)) return null;
                    const rect = node.getBoundingClientRect();
                    return {
                        tag: (node.tagName || '').toLowerCase(),
                        id: node.id || null,
                        classes: Array.from(node.classList || []).slice(0, 4),
                        text: normalizeText((node.innerText || node.textContent || '').slice(0, 240)),
                        href: node.getAttribute('href'),
                        role: node.getAttribute('role'),
                        visible: isVisible(node),
                        selector: selectorForElement(node),
                        bounds: {
                            x: Math.round(rect.left),
                            y: Math.round(rect.top),
                            width: Math.round(rect.width),
                            height: Math.round(rect.height)
                        }
                    };
                }
                function resolveTarget(selector, coordinateX, coordinateY) {
                    if (selector) {
                        return Array.from(document.querySelectorAll(selector)).find(isVisible) || document.querySelector(selector);
                    }
                    if (coordinateX !== null && coordinateY !== null) {
                        return document.elementFromPoint(coordinateX, coordinateY);
                    }
                    return null;
                }
                function resolveScrollable(explicitNode, explicitSelector) {
                    if (explicitNode) {
                        if (!(explicitNode instanceof Element)) {
                            throw new Error('Scrollable target not found: ' + explicitSelector);
                        }
                        return explicitNode;
                    }
                    const scrollingElement = document.scrollingElement || document.documentElement || document.body;
                    const candidates = Array.from(document.querySelectorAll('*'))
                        .filter(function(el) {
                            const style = window.getComputedStyle(el);
                            const overflowY = style.overflowY || '';
                            return isVisible(el) &&
                                el.scrollHeight > el.clientHeight + 40 &&
                                (overflowY.includes('auto') || overflowY.includes('scroll'));
                        })
                        .sort(function(a, b) { return (b.scrollHeight * Math.max(b.clientWidth, 1)) - (a.scrollHeight * Math.max(a.clientWidth, 1)); });
                    return candidates[0] || scrollingElement;
                }
                function scrollTopOf(target) {
                    if (target === document.body || target === document.documentElement || target === document.scrollingElement) {
                        return window.scrollY || 0;
                    }
                    return target.scrollTop || 0;
                }
                function scrollTarget(target, delta) {
                    if (target === document.body || target === document.documentElement || target === document.scrollingElement) {
                        window.scrollBy(0, delta);
                        return;
                    }
                    target.scrollBy(0, delta);
                }
                function detectCollectionSelector() {
                    var candidates = ['article','[role="article"]','[role="listitem"]','[data-testid]','li','.item','.card','main article','main li'];
                    var best = null;
                    var bestCount = 0;
                    candidates.forEach(function(sel) {
                        var count = Array.from(document.querySelectorAll(sel)).filter(isVisible).length;
                        if (count > bestCount) { best = sel; bestCount = count; }
                    });
                    if (bestCount >= 3) return best;
                    return 'body > *';
                }
                function safeSerialize(value, depth) {
                    if (depth > 4) return '[MaxDepth]';
                    if (value === null || value === undefined) return null;
                    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return value;
                    if (value instanceof Element) return describeElement(value);
                    if (Array.isArray(value)) return value.slice(0, 80).map(function(item) { return safeSerialize(item, depth + 1); });
                    if (typeof value === 'object') {
                        var result = {};
                        Object.keys(value).slice(0, 60).forEach(function(key) {
                            try { result[key] = safeSerialize(value[key], depth + 1); } catch(_) {}
                        });
                        return result;
                    }
                    return String(value);
                }
                if (!window.__omni) {
                    window.__omni = {
                        normalizeText: normalizeText,
                        isVisible: isVisible,
                        isInteractive: isInteractive,
                        selectorForElement: selectorForElement,
                        describeElement: describeElement,
                        resolveTarget: resolveTarget,
                        resolveScrollable: resolveScrollable,
                        scrollTopOf: scrollTopOf,
                        scrollTarget: scrollTarget,
                        detectCollectionSelector: detectCollectionSelector,
                        safeSerialize: safeSerialize
                    };
                }
        """
    }
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val tabs = linkedMapOf<Int, BrowserTab>()
    private var nextTabId = 0
    private var activeTabId: Int? = null
    private val appContext = context.applicationContext
    private val viewportWidth = appContext.resources.displayMetrics.widthPixels.coerceAtLeast(1080)
    private val viewportHeight = appContext.resources.displayMetrics.heightPixels.coerceAtLeast(1920)
    private val density = appContext.resources.displayMetrics.density
    private var currentAgentRunId: String = agentRunId
    private var currentWorkspace: AgentWorkspaceDescriptor = workspace

    override val workspaceId: String
        get() = currentWorkspace.id

    suspend fun execute(request: BrowserUseRequest): BrowserUseOutcome {
        return when (request.action) {
            BrowserUseAction.NEW_TAB -> executeNewTab(request)
            BrowserUseAction.LIST_TABS -> simpleOutcome(request, listTabsPayload())
            BrowserUseAction.CLOSE_TAB -> executeCloseTab(request)
            BrowserUseAction.NAVIGATE -> executeNavigate(request)
            BrowserUseAction.SCREENSHOT -> executeScreenshot(request)
            BrowserUseAction.CLICK -> executeClick(request)
            BrowserUseAction.HOVER -> executeHover(request)
            BrowserUseAction.TYPE -> executeType(request)
            BrowserUseAction.GET_TEXT -> executeGetText(request)
            BrowserUseAction.GET_READABLE -> executeGetReadable(request)
            BrowserUseAction.SCROLL -> executeScroll(request)
            BrowserUseAction.SCROLL_AND_COLLECT -> executeScrollAndCollect(request)
            BrowserUseAction.FIND_ELEMENTS -> executeFindElements(request)
            BrowserUseAction.GET_PAGE_INFO -> executeGetPageInfo(request)
            BrowserUseAction.GET_BACKBONE -> executeGetBackbone(request)
            BrowserUseAction.EXECUTE_JS -> executeCustomScript(request)
            BrowserUseAction.SET_USER_AGENT -> executeSetUserAgent(request)
            BrowserUseAction.FETCH -> executeFetch(request)
            BrowserUseAction.GET_COOKIES -> executeGetCookies(request)
            BrowserUseAction.GO_BACK -> executeGoBack(request)
            BrowserUseAction.GO_FORWARD -> executeGoForward(request)
            BrowserUseAction.PRESS_KEY -> executePressKey(request)
            BrowserUseAction.WAIT_FOR_SELECTOR -> executeWaitForSelector(request)
        }
    }

    fun bindRunContext(
        agentRunId: String,
        workspace: AgentWorkspaceDescriptor
    ) {
        currentAgentRunId = agentRunId
        currentWorkspace = workspace
    }

    fun liveSessionSnapshot(): Map<String, Any?> {
        val tab = activeTabId?.let { tabs[it] } ?: tabs.values.lastOrNull()
        if (tab == null) {
            return unavailableSnapshot(workspaceId = workspaceId)
        }
        activeTabId = tab.tabId
        return linkedMapOf(
            "available" to true,
            "workspaceId" to workspaceId,
            "activeTabId" to tab.tabId,
            "currentUrl" to (tab.currentUrl ?: ""),
            "title" to (tab.title ?: ""),
            "userAgentProfile" to tab.userAgentProfile.wireName
        )
    }

    suspend fun requestInterruptCurrentAction() {
        withContext(Dispatchers.Main.immediate) {
            tabs.values.forEach { tab ->
                runCatching { tab.webView.stopLoading() }
                tab.isLoading = false
                tab.loadWaiter?.cancel(ManualToolStopCancellationException())
                tab.loadWaiter = null
            }
        }
    }

    suspend fun captureActiveFramePng(): ByteArray? {
        val tab = activeTabId?.let { tabs[it] } ?: tabs.values.lastOrNull() ?: return null
        activeTabId = tab.tabId
        val (vpWidth, vpHeight) = viewportDimensionsForProfile(tab.userAgentProfile)
        return withContext(Dispatchers.Main.immediate) {
            layoutWebView(tab.webView, vpWidth, vpHeight)
            if (tab.webView.windowToken == null) {
                tab.webView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
            }
            val bitmap = Bitmap.createBitmap(
                vpWidth,
                vpHeight,
                Bitmap.Config.ARGB_8888
            )
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            tab.webView.draw(canvas)
            val bytes = ByteArrayOutputStream().use { stream ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                stream.toByteArray()
            }
            bitmap.recycle()
            bytes
        }
    }

    fun attachActiveTabTo(
        container: ViewGroup,
        hostContext: Context
    ): Boolean {
        val tab = activeTabId?.let { tabs[it] } ?: tabs.values.lastOrNull() ?: return false
        activeTabId = tab.tabId
        tab.contextWrapper.baseContext = hostContext
        val currentParent = tab.webView.parent as? ViewGroup
        if (currentParent !== container) {
            currentParent?.removeView(tab.webView)
            container.removeAllViews()
            container.addView(
                tab.webView,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
        }
        tab.webView.post { layoutWebView(tab.webView) }
        return true
    }

    fun detachActiveTabFrom(container: ViewGroup? = null) {
        val tab = activeTabId?.let { tabs[it] } ?: tabs.values.lastOrNull() ?: return
        val parent = tab.webView.parent as? ViewGroup ?: return
        if (container == null || parent === container) {
            parent.removeView(tab.webView)
        }
        tab.contextWrapper.baseContext = appContext
    }

    override fun closeSession() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            destroyOnMain()
            return
        }
        runBlocking(Dispatchers.Main.immediate) {
            destroyOnMain()
        }
    }

    private fun destroyOnMain() {
        tabs.values.forEach { tab ->
            runCatching {
                (tab.webView.parent as? ViewGroup)?.removeView(tab.webView)
                tab.webView.stopLoading()
                tab.webView.destroy()
            }
        }
        tabs.clear()
        activeTabId = null
        mainScope.cancel()
    }

    private suspend fun executeNewTab(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = createTab()
        if (!request.url.isNullOrBlank()) {
            navigateTab(tab, request.url)
        }
        return simpleOutcome(
            request,
            mapOf(
                "tabId" to tab.tabId,
                "currentUrl" to tab.currentUrl,
                "pageTitle" to tab.title,
                "tabs" to listTabsPayload()["tabs"],
                "activeTabId" to activeTabId
            )
        )
    }

    private suspend fun executeCloseTab(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requireTabForMutation(request)
        withContext(Dispatchers.Main.immediate) {
            tabs.remove(tab.tabId)
            if (activeTabId == tab.tabId) {
                activeTabId = tabs.keys.lastOrNull()
            }
            runCatching {
                (tab.webView.parent as? ViewGroup)?.removeView(tab.webView)
                tab.webView.stopLoading()
                tab.webView.destroy()
            }
        }
        return simpleOutcome(
            request,
            mapOf(
                "closedTabId" to tab.tabId,
                "activeTabId" to activeTabId,
                "tabs" to listTabsPayload()["tabs"]
            )
        )
    }

    private suspend fun executeNavigate(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = request.tabId?.let { requireExistingTab(it) } ?: tabs[activeTabId]
            ?: createTab()
        val snapshot = navigateTab(tab, request.url)
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf(
                    "finalUrl" to snapshot.url,
                    "pageTitle" to snapshot.title,
                    "pageInfo" to pageInfoMap(tab)
                )
            )
        )
    }

    private suspend fun executeScreenshot(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val (vpWidth, vpHeight) = viewportDimensionsForProfile(tab.userAgentProfile)
        val screenshotFile = workspaceManager.newBrowserFile(
            agentRunId = currentAgentRunId,
            prefix = "screenshot_tab_${tab.tabId}",
            extension = "jpg"
        )
        var imageDataUrl: String? = null
        withContext(Dispatchers.Main.immediate) {
            layoutWebView(tab.webView, vpWidth, vpHeight)
            if (tab.webView.windowToken == null) {
                tab.webView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
            }
            val bitmap = Bitmap.createBitmap(vpWidth, vpHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)
            tab.webView.draw(canvas)
            FileOutputStream(screenshotFile).use { stream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, SCREENSHOT_JPEG_QUALITY, stream)
            }
            if (request.readImage) {
                imageDataUrl = bitmapToDataUrl(bitmap, READ_IMAGE_MAX_WIDTH, READ_IMAGE_JPEG_QUALITY)
            }
            bitmap.recycle()
        }
        val artifact = workspaceManager.buildArtifactForFile(screenshotFile, "browser_use")
        return BrowserUseOutcome(
            summaryText = request.toolTitle,
            payload = buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf(
                    "artifactUri" to artifact.uri,
                    "pageTitle" to tab.title,
                    "imageWidth" to vpWidth,
                    "imageHeight" to vpHeight
                )
            ),
            artifacts = listOf(artifact),
            imageDataUrl = imageDataUrl
        )
    }

    private suspend fun executeClick(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val value = evaluateValue(
            tab,
            buildTargetedScript(
                request = request,
                command = """
                    target.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: centerX, clientY: centerY }));
                    target.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, clientX: centerX, clientY: centerY }));
                    target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, clientX: centerX, clientY: centerY }));
                    target.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, clientX: centerX, clientY: centerY }));
                    target.click();
                    return describeElement(target);
                """.trimIndent()
            )
        )
        waitForPostActionSettle(tab)
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf("matchedElement" to jsonElementToAny(value))
            )
        )
    }

    private suspend fun executeHover(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val value = evaluateValue(
            tab,
            buildTargetedScript(
                request = request,
                command = """
                    target.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: centerX, clientY: centerY }));
                    target.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, clientX: centerX, clientY: centerY }));
                    target.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, clientX: centerX, clientY: centerY }));
                    return describeElement(target);
                """.trimIndent()
            )
        )
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf("matchedElement" to jsonElementToAny(value))
            )
        )
    }

    private suspend fun executeType(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val textLiteral = JSONObject.quote(request.text)
        val value = evaluateValue(
            tab,
            buildTargetedScript(
                request = request,
                command = """
                    target.focus();
                    if (target.isContentEditable) {
                        target.textContent = $textLiteral;
                    } else if ('value' in target) {
                        var nativeSetter = Object.getOwnPropertyDescriptor(
                            window.HTMLInputElement.prototype, 'value'
                        );
                        if (!nativeSetter || !nativeSetter.set) {
                            nativeSetter = Object.getOwnPropertyDescriptor(
                                window.HTMLTextAreaElement.prototype, 'value'
                            );
                        }
                        if (nativeSetter && nativeSetter.set) {
                            nativeSetter.set.call(target, $textLiteral);
                        } else {
                            target.value = $textLiteral;
                        }
                    } else {
                        throw new Error('Target element is not editable');
                    }
                    target.dispatchEvent(new Event('input', { bubbles: true }));
                    target.dispatchEvent(new Event('change', { bubbles: true }));
                    return describeElement(target);
                """.trimIndent()
            )
        )
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf(
                    "typedTextLength" to request.text?.length,
                    "matchedElement" to jsonElementToAny(value)
                )
            )
        )
    }

    private suspend fun executeGetText(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val value = evaluateValue(
            tab,
            """
                const selector = ${request.selector?.let { JSONObject.quote(it) } ?: "null"};
                let target = null;
                if (selector) {
                    target = Array.from(document.querySelectorAll(selector)).find(isVisible) || document.querySelector(selector);
                    if (!target) {
                        throw new Error('Element not found for selector: ' + selector);
                    }
                }
                const text = normalizeText((target ? (target.innerText || target.textContent) : document.body.innerText) || '');
                return {
                    selectorUsed: selector,
                    text: text,
                    textLength: text.length
                };
            """.trimIndent()
        ).jsonObject
        return buildTextOutcome(
            request = request,
            tab = tab,
            text = value["text"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            extra = mapOf("selectorUsed" to value["selectorUsed"]?.jsonPrimitive?.contentOrNull)
        )
    }

    private suspend fun executeGetReadable(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val value = evaluateValue(
            tab,
            """
                const candidates = Array.from(document.querySelectorAll('main, article, [role="main"], .article, .content, .post, .entry-content'))
                    .filter(isVisible);
                const target = candidates.sort((a, b) => normalizeText((b.innerText || b.textContent || '')).length - normalizeText((a.innerText || a.textContent || '')).length)[0] || document.body;
                const text = normalizeText((target.innerText || target.textContent || ''));
                return {
                    selectorUsed: selectorForElement(target),
                    text: text,
                    textLength: text.length
                };
            """.trimIndent()
        ).jsonObject
        return buildTextOutcome(
            request = request,
            tab = tab,
            text = value["text"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            extra = mapOf("selectorUsed" to value["selectorUsed"]?.jsonPrimitive?.contentOrNull)
        )
    }

    private suspend fun executeScroll(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val direction = request.direction?.takeIf { it == "up" || it == "down" } ?: "down"
        val selectorLiteral = request.selector?.let { JSONObject.quote(it) } ?: "null"
        val value = evaluateValue(
            tab,
            """
                const selector = $selectorLiteral;
                const amount = ${request.amount};
                const direction = ${JSONObject.quote(direction)};
                const delta = direction === 'up' ? -amount : amount;
                const target = selector ? resolveScrollable(document.querySelector(selector), selector) : resolveScrollable(null, null);
                const beforeTop = scrollTopOf(target);
                scrollTarget(target, delta);
                const afterTop = scrollTopOf(target);
                return {
                    selectorUsed: selector || selectorForElement(target),
                    beforeTop: beforeTop,
                    afterTop: afterTop,
                    direction: direction,
                    amount: amount
                };
            """.trimIndent()
        )
        delay(ACTION_SETTLE_DELAY_MS)
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf("scroll" to jsonElementToAny(value))
            )
        )
    }

    private suspend fun executeScrollAndCollect(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val seen = linkedSetOf<String>()
        var selectorUsed: String? = request.itemSelector
        repeat(request.scrollCount) { index ->
            val value = evaluateValue(
                tab,
                """
                    const explicitSelector = ${request.itemSelector?.let { JSONObject.quote(it) } ?: "null"};
                    const selector = explicitSelector || detectCollectionSelector();
                    const nodes = selector ? Array.from(document.querySelectorAll(selector)).filter(isVisible) : [];
                    const items = nodes.map(node => normalizeText((node.innerText || node.textContent || '').slice(0, 800)))
                        .filter(Boolean);
                    return {
                        selectorUsed: selector,
                        items: items.slice(0, 80)
                    };
                """.trimIndent()
            ).jsonObject
            selectorUsed = value["selectorUsed"]?.jsonPrimitive?.contentOrNull ?: selectorUsed
            value["items"]?.jsonArray?.forEach { item ->
                item.jsonPrimitive.contentOrNull
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { seen.add(it) }
            }
            if (index != request.scrollCount - 1) {
                executeScroll(
                    request.copy(
                        direction = request.direction ?: "down",
                        selector = request.selector,
                        toolTitle = request.toolTitle
                    )
                )
                delay(ACTION_SETTLE_DELAY_MS)
            }
        }
        return buildCollectionOutcome(
            request = request,
            tab = tab,
            selectorUsed = selectorUsed,
            items = seen.toList()
        )
    }

    private suspend fun executeFindElements(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val selectorLiteral = request.selector?.let { JSONObject.quote(it) }
            ?: JSONObject.quote("a, button, input, textarea, select, [role=\"button\"], [onclick], [tabindex]")
        val value = evaluateValue(
            tab,
            """
                const selector = $selectorLiteral;
                const nodes = Array.from(document.querySelectorAll(selector)).filter(isVisible).slice(0, $FIND_ELEMENTS_LIMIT);
                return nodes.map(node => describeElement(node));
            """.trimIndent()
        )
        val elements = (jsonElementToAny(value) as? List<*>) ?: emptyList<Any?>()
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf(
                    "selectorUsed" to (request.selector ?: "interactive_default"),
                    "elementCount" to elements.size,
                    "elements" to elements
                )
            )
        )
    }

    private suspend fun executeGetPageInfo(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf("pageInfo" to pageInfoMap(tab))
            )
        )
    }

    private suspend fun executeGetBackbone(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val value = evaluateValue(
            tab,
            """
                function buildBackbone(node, depth) {
                    if (!node || depth > ${request.maxDepth}) return null;
                    const children = Array.from(node.children || [])
                        .slice(0, 12)
                        .map(child => buildBackbone(child, depth + 1))
                        .filter(Boolean);
                    return {
                        tag: (node.tagName || '').toLowerCase(),
                        id: node.id || null,
                        classes: Array.from(node.classList || []).slice(0, 3),
                        role: node.getAttribute ? node.getAttribute('role') : null,
                        text: normalizeText((node.innerText || node.textContent || '').slice(0, 120)),
                        interactive: isInteractive(node),
                        children: children
                    };
                }
                return buildBackbone(document.body, 0);
            """.trimIndent()
        )
        return buildStructuredOutcome(
            request = request,
            tab = tab,
            label = "backbone",
            value = value,
            extension = "json"
        )
    }

    private suspend fun executeCustomScript(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val value = evaluateValue(tab, request.script)
        return buildStructuredOutcome(
            request = request,
            tab = tab,
            label = "result",
            value = value,
            extension = "json"
        )
    }

    private suspend fun executeSetUserAgent(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = request.tabId?.let { requireExistingTab(it) } ?: tabs[activeTabId]
            ?: createTab()
        withContext(Dispatchers.Main.immediate) {
            tab.userAgentProfile = request.userAgent ?: BrowserUserAgentProfile.defaultProfile()
            tab.webView.settings.userAgentString = tab.userAgentProfile.userAgentString
        }
        if (!tab.currentUrl.isNullOrBlank() && tab.currentUrl != "about:blank") {
            navigateTab(tab, tab.currentUrl)
        }
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf("userAgentProfile" to tab.userAgentProfile.wireName)
            )
        )
    }

    private suspend fun executeFetch(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val targetUrl = request.url?.trim().orEmpty()
        require(targetUrl.startsWith("http://") || targetUrl.startsWith("https://")) {
            "fetch 仅支持 http(s) 资源"
        }
        val cookieHeader = CookieManager.getInstance().getCookie(targetUrl).orEmpty()
        val connection = withContext(Dispatchers.IO) {
            (URL(targetUrl).openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = true
                requestMethod = "GET"
                connectTimeout = 30_000
                readTimeout = 30_000
                setRequestProperty("User-Agent", tab.userAgentProfile.userAgentString)
                if (cookieHeader.isNotBlank()) {
                    setRequestProperty("Cookie", cookieHeader)
                }
                setRequestProperty("Accept", "*/*")
            }
        }
        val responseCode = withContext(Dispatchers.IO) { connection.responseCode }
        if (responseCode >= 400) {
            val message = withContext(Dispatchers.IO) {
                runCatching { connection.errorStream?.bufferedReader()?.use { it.readText() } }.getOrNull()
            }.orEmpty().take(400)
            connection.disconnect()
            throw IllegalStateException("fetch 失败：HTTP $responseCode ${message.ifBlank { "" }}".trim())
        }
        val fileName = resolveDownloadFileName(connection, targetUrl)
        val extension = fileName.substringAfterLast('.', "").ifBlank {
            extensionFromContentType(connection.contentType)
        }
        val targetFile = workspaceManager.newBrowserFile(
            agentRunId = currentAgentRunId,
            prefix = fileName.substringBeforeLast('.').ifBlank { "fetch" },
            extension = extension.ifBlank { "bin" }
        )
        withContext(Dispatchers.IO) {
            connection.inputStream.use { input ->
                targetFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            connection.disconnect()
        }
        val artifact = workspaceManager.buildArtifactForFile(targetFile, "browser_use")
        return BrowserUseOutcome(
            summaryText = request.toolTitle,
            payload = buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf(
                    "statusCode" to responseCode,
                    "artifactUri" to artifact.uri,
                    "mimeType" to workspaceManager.guessMimeType(targetFile),
                    "size" to targetFile.length()
                )
            ),
            artifacts = listOf(artifact)
        )
    }

    private suspend fun executeGetCookies(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val currentUrl = tab.currentUrl?.takeIf { it.isNotBlank() && it != "about:blank" }
            ?: throw IllegalStateException("当前标签页没有可用页面，无法读取 cookies")
        val cookiePairs = collectCookiesForUrl(currentUrl).toList()
        val matchedNames = BrowserUseSupport.filterCookieNames(
            names = cookiePairs.map { it.first },
            keywords = request.keywords,
            fuzzy = request.fuzzy
        )
        val fallbackToAllCookies =
            matchedNames.isEmpty() && request.keywords.isNotEmpty() && cookiePairs.isNotEmpty()
        val exportedPairs = if (fallbackToAllCookies) {
            cookiePairs
        } else {
            cookiePairs.filter { (name, _) -> matchedNames.contains(name) }
        }
        val exportedNames = exportedPairs.map { it.first }
        val envFile = workspaceManager.newOffloadFile(
            agentRunId = currentAgentRunId,
            prefix = "env_cookies",
            extension = "sh"
        )
        val filteredHeader = exportedPairs.joinToString("; ") { (name, value) -> "$name=$value" }
        val script = buildString {
            appendLine("#!/bin/sh")
            appendLine("export BROWSER_COOKIE_HEADER='${BrowserUseSupport.escapeShellValue(filteredHeader)}'")
            appendLine("export BROWSER_COOKIE_COUNT='${exportedPairs.size}'")
            exportedPairs.forEach { (name, value) ->
                appendLine(
                    "export ${BrowserUseSupport.sanitizeCookieEnvName(name)}='${BrowserUseSupport.escapeShellValue(value)}'"
                )
            }
        }
        envFile.writeText(script)
        val envShellPath = workspaceManager.shellPathForAndroid(envFile) ?: envFile.absolutePath
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf(
                    "siteRoot" to siteRootFromUrl(currentUrl),
                    "matchedCount" to exportedPairs.size,
                    "cookieNames" to matchedNames,
                    "availableCookieNames" to cookiePairs.map { it.first },
                    "exportedCookieNames" to exportedNames,
                    "envShellPath" to envShellPath,
                    "envAndroidPath" to envFile.absolutePath,
                    "cookieLookupUrls" to buildCookieLookupUrls(currentUrl),
                    "keywordFallbackToAll" to fallbackToAllCookies,
                    "fuzzy" to request.fuzzy,
                    "keywords" to request.keywords
                )
            )
        )
    }

    private suspend fun executeGoBack(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val canGoBack = withContext(Dispatchers.Main.immediate) { tab.webView.canGoBack() }
        if (!canGoBack) {
            throw IllegalStateException("当前页面无法后退")
        }
        val waiter = CompletableDeferred<LoadSnapshot>()
        tab.loadWaiter = waiter
        withContext(Dispatchers.Main.immediate) { tab.webView.goBack() }
        withTimeout(NAVIGATION_TIMEOUT_MS) { waiter.await() }
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf("pageTitle" to tab.title, "currentUrl" to tab.currentUrl)
            )
        )
    }

    private suspend fun executeGoForward(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val canGoForward = withContext(Dispatchers.Main.immediate) { tab.webView.canGoForward() }
        if (!canGoForward) {
            throw IllegalStateException("当前页面无法前进")
        }
        val waiter = CompletableDeferred<LoadSnapshot>()
        tab.loadWaiter = waiter
        withContext(Dispatchers.Main.immediate) { tab.webView.goForward() }
        withTimeout(NAVIGATION_TIMEOUT_MS) { waiter.await() }
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf("pageTitle" to tab.title, "currentUrl" to tab.currentUrl)
            )
        )
    }

    private suspend fun executePressKey(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val keyLiteral = JSONObject.quote(request.key)
        evaluateValue(
            tab,
            """
                const keyName = $keyLiteral;
                const target = document.activeElement || document.body;
                const opts = { key: keyName, code: keyName, bubbles: true, cancelable: true };
                target.dispatchEvent(new KeyboardEvent('keydown', opts));
                target.dispatchEvent(new KeyboardEvent('keypress', opts));
                target.dispatchEvent(new KeyboardEvent('keyup', opts));
                if (keyName === 'Enter') {
                    const form = target.closest && target.closest('form');
                    if (form) { form.requestSubmit ? form.requestSubmit() : form.submit(); }
                }
                return { key: keyName, targetTag: (target.tagName || '').toLowerCase() };
            """.trimIndent()
        )
        waitForPostActionSettle(tab)
        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf("key" to request.key)
            )
        )
    }

    private suspend fun executeWaitForSelector(request: BrowserUseRequest): BrowserUseOutcome {
        val tab = requirePageTab(request)
        val selectorLiteral = JSONObject.quote(request.selector)
        val deadline = System.currentTimeMillis() + request.timeoutMs
        val pollInterval = 250L
        var found = false
        var visible = false

        while (System.currentTimeMillis() < deadline) {
            val result = evaluateValue(
                tab,
                """
                    const el = document.querySelector($selectorLiteral);
                    return { found: !!el, visible: el ? isVisible(el) : false };
                """.trimIndent()
            ).jsonObject
            found = result["found"]?.jsonPrimitive?.booleanOrNull == true
            visible = result["visible"]?.jsonPrimitive?.booleanOrNull == true
            if (found) break
            delay(pollInterval)
        }

        return simpleOutcome(
            request,
            buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = mapOf(
                    "selector" to request.selector,
                    "found" to found,
                    "visible" to visible,
                    "timeoutMs" to request.timeoutMs
                )
            )
        )
    }

    private fun bitmapToDataUrl(
        bitmap: Bitmap,
        maxWidth: Int,
        quality: Int
    ): String {
        val finalBitmap = if (bitmap.width > maxWidth) {
            val scale = maxWidth.toFloat() / bitmap.width
            val scaledHeight = (bitmap.height * scale).toInt()
            Bitmap.createScaledBitmap(bitmap, maxWidth, scaledHeight, true)
        } else {
            bitmap
        }
        val bytes = ByteArrayOutputStream().use { stream ->
            finalBitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
            stream.toByteArray()
        }
        if (finalBitmap !== bitmap) {
            finalBitmap.recycle()
        }
        val encoded = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
        return "data:image/jpeg;base64,$encoded"
    }

    private suspend fun simpleOutcome(
        request: BrowserUseRequest,
        payload: Map<String, Any?>
    ): BrowserUseOutcome {
        return BrowserUseOutcome(
            summaryText = request.toolTitle,
            payload = payload
        )
    }

    private suspend fun buildTextOutcome(
        request: BrowserUseRequest,
        tab: BrowserTab,
        text: String,
        extra: Map<String, Any?> = emptyMap()
    ): BrowserUseOutcome {
        val artifacts = mutableListOf<ArtifactRef>()
        val payloadExtra = extra.toMutableMap()
        if (text.length > LARGE_TEXT_THRESHOLD) {
            val file = workspaceManager.newBrowserFile(
                agentRunId = currentAgentRunId,
                prefix = request.action.wireName,
                extension = "txt"
            )
            file.writeText(text)
            val artifact = workspaceManager.buildArtifactForFile(file, "browser_use")
            artifacts += artifact
            payloadExtra["textSnippet"] = text.take(4_000)
            payloadExtra["artifactUri"] = artifact.uri
            payloadExtra["textLength"] = text.length
        } else {
            payloadExtra["text"] = text
            payloadExtra["textLength"] = text.length
        }
        return BrowserUseOutcome(
            summaryText = request.toolTitle,
            payload = buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = payloadExtra
            ),
            artifacts = artifacts
        )
    }

    private suspend fun buildCollectionOutcome(
        request: BrowserUseRequest,
        tab: BrowserTab,
        selectorUsed: String?,
        items: List<String>
    ): BrowserUseOutcome {
        val extra = linkedMapOf<String, Any?>(
            "selectorUsed" to selectorUsed,
            "itemCount" to items.size
        )
        val artifacts = mutableListOf<ArtifactRef>()
        if (items.size > 20) {
            val file = workspaceManager.newBrowserFile(
                agentRunId = currentAgentRunId,
                prefix = "scroll_collect",
                extension = "json"
            )
            file.writeText(JSONObject(mapOf("items" to items)).toString(2))
            val artifact = workspaceManager.buildArtifactForFile(file, "browser_use")
            artifacts += artifact
            extra["itemsPreview"] = items.take(20)
            extra["artifactUri"] = artifact.uri
        } else {
            extra["items"] = items
        }
        return BrowserUseOutcome(
            summaryText = request.toolTitle,
            payload = buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = extra
            ),
            artifacts = artifacts
        )
    }

    private suspend fun buildStructuredOutcome(
        request: BrowserUseRequest,
        tab: BrowserTab,
        label: String,
        value: JsonElement,
        extension: String
    ): BrowserUseOutcome {
        val content = when (value) {
            JsonNull -> "null"
            else -> json.encodeToString(JsonElement.serializer(), value)
        }
        val artifacts = mutableListOf<ArtifactRef>()
        val extra = linkedMapOf<String, Any?>()
        if (content.length > LARGE_TEXT_THRESHOLD) {
            val file = workspaceManager.newBrowserFile(
                agentRunId = currentAgentRunId,
                prefix = request.action.wireName,
                extension = extension
            )
            file.writeText(content)
            val artifact = workspaceManager.buildArtifactForFile(file, "browser_use")
            artifacts += artifact
            extra[label] = when (value) {
                is JsonArray -> (jsonElementToAny(value) as? List<*>)?.take(10)
                is JsonObject -> mapOf("offloaded" to true)
                else -> content.take(4_000)
            }
            extra["artifactUri"] = artifact.uri
        } else {
            extra[label] = jsonElementToAny(value)
        }
        return BrowserUseOutcome(
            summaryText = request.toolTitle,
            payload = buildCommonPayload(
                tab = tab,
                action = request.action,
                extra = extra
            ),
            artifacts = artifacts
        )
    }

    private fun buildCommonPayload(
        tab: BrowserTab,
        action: BrowserUseAction,
        extra: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> {
        return linkedMapOf<String, Any?>(
            "workspaceId" to workspaceId,
            "action" to action.wireName,
            "tabId" to tab.tabId,
            "currentUrl" to tab.currentUrl,
            "pageTitle" to tab.title,
            "userAgentProfile" to tab.userAgentProfile.wireName,
            "activeTabId" to activeTabId
        ).apply {
            putAll(extra)
        }
    }

    private fun listTabsPayload(): Map<String, Any?> {
        return mapOf(
            "activeTabId" to activeTabId,
            "tabs" to tabs.values.map { tab ->
                mapOf(
                    "tabId" to tab.tabId,
                    "url" to tab.currentUrl,
                    "title" to tab.title,
                    "userAgentProfile" to tab.userAgentProfile.wireName,
                    "isActive" to (tab.tabId == activeTabId)
                )
            }
        )
    }

    @Suppress("DEPRECATION")
    private suspend fun createTab(
        profile: BrowserUserAgentProfile = BrowserUserAgentProfile.defaultProfile()
    ): BrowserTab {
        require(tabs.size < MAX_BROWSER_TABS) { "浏览器标签页上限为 $MAX_BROWSER_TABS" }
        return withContext(Dispatchers.Main.immediate) {
            val tabId = ++nextTabId
            val contextWrapper = MutableContextWrapper(appContext)
            val webView = WebView(contextWrapper).apply {
                setBackgroundColor(Color.WHITE)
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.useWideViewPort = true
                settings.loadWithOverviewMode = true
                settings.allowContentAccess = true
                settings.allowFileAccess = true
                settings.allowFileAccessFromFileURLs = true
                settings.userAgentString = profile.userAgentString
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    settings.safeBrowsingEnabled = true
                }
                webChromeClient = WebChromeClient()
            }
            val tab = BrowserTab(
                tabId = tabId,
                contextWrapper = contextWrapper,
                webView = webView,
                userAgentProfile = profile,
                currentUrl = "about:blank",
                title = "Blank"
            )
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
            webView.webViewClient = BrowserTabClient(tab)
            val (vpWidth, vpHeight) = viewportDimensionsForProfile(profile)
            layoutWebView(webView, vpWidth, vpHeight)
            tabs[tabId] = tab
            activeTabId = tabId
            tab
        }
    }

    private suspend fun requireExistingTab(tabId: Int): BrowserTab {
        return tabs[tabId] ?: throw IllegalArgumentException("未找到 tab_id=$tabId")
    }

    private suspend fun requireTabForMutation(request: BrowserUseRequest): BrowserTab {
        val tabId = request.tabId ?: activeTabId
        require(tabId != null) { "当前没有活动标签页" }
        return requireExistingTab(tabId)
    }

    private suspend fun requirePageTab(request: BrowserUseRequest): BrowserTab {
        val tab = requireTabForMutation(request)
        val currentUrl = tab.currentUrl.orEmpty()
        require(currentUrl.isNotBlank() && currentUrl != "about:blank") {
            "当前标签页没有已打开的页面，请先 navigate"
        }
        activeTabId = tab.tabId
        return tab
    }

    private suspend fun navigateTab(
        tab: BrowserTab,
        rawUrl: String?
    ): LoadSnapshot {
        val resolvedUrl = resolveNavigateUrl(rawUrl)
        activeTabId = tab.tabId
        val waiter = CompletableDeferred<LoadSnapshot>()
        tab.loadWaiter = waiter
        tab.lastError = null
        withContext(Dispatchers.Main.immediate) {
            layoutWebView(tab.webView)
            tab.webView.loadUrl(resolvedUrl)
        }
        val snapshot = withTimeout(NAVIGATION_TIMEOUT_MS) { waiter.await() }
        if (!snapshot.errorMessage.isNullOrBlank()) {
            throw IllegalStateException(snapshot.errorMessage)
        }
        return snapshot
    }

    private suspend fun waitForPostActionSettle(tab: BrowserTab) {
        delay(ACTION_SETTLE_DELAY_MS)
        val waiter = tab.loadWaiter
        if (tab.isLoading && waiter != null && !waiter.isCompleted) {
            withTimeout(NAVIGATION_TIMEOUT_MS) { waiter.await() }
        }
    }

    private fun resolveNavigateUrl(rawUrl: String?): String {
        val trimmed = rawUrl?.trim().orEmpty()
        require(trimmed.isNotEmpty()) { "url 不能为空" }
        return when {
            trimmed.startsWith("http://") || trimmed.startsWith("https://") -> trimmed
            trimmed.startsWith("omnibot://browser/") -> {
                val file = workspaceManager.resolvePath(
                    inputPath = trimmed,
                    workspace = currentWorkspace,
                    allowRootDirectories = true
                )
                require(file.exists()) { "本地浏览器资源不存在：$trimmed" }
                file.toURI().toString()
            }
            else -> throw IllegalArgumentException("browser_use 仅支持 http(s) 或 omnibot://browser/... 资源")
        }
    }

    private suspend fun pageInfoMap(tab: BrowserTab): Map<String, Any?> {
        val js = evaluateValue(
            tab,
            """
                return {
                    viewportWidth: window.innerWidth,
                    viewportHeight: window.innerHeight,
                    scrollX: window.scrollX || 0,
                    scrollY: window.scrollY || 0,
                    contentWidth: Math.max(document.body.scrollWidth, document.documentElement.scrollWidth),
                    contentHeight: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)
                };
            """.trimIndent()
        )
        val payload = (jsonElementToAny(js) as? Map<*, *>)?.mapKeys { it.key.toString() }?.toMutableMap()
            ?: linkedMapOf()
        payload["url"] = tab.currentUrl
        payload["title"] = tab.title
        payload["canGoBack"] = withContext(Dispatchers.Main.immediate) { tab.webView.canGoBack() }
        payload["canGoForward"] = withContext(Dispatchers.Main.immediate) { tab.webView.canGoForward() }
        payload["userAgentProfile"] = tab.userAgentProfile.wireName
        return payload
    }

    private suspend fun evaluateJavascriptRaw(
        tab: BrowserTab,
        script: String
    ): String {
        return withContext(Dispatchers.Main.immediate) {
            layoutWebView(tab.webView)
            suspendCancellableCoroutine { continuation ->
                val callback = ValueCallback<String> { value ->
                    if (continuation.isActive) {
                        continuation.resume(value ?: "null")
                    }
                }
                try {
                    tab.webView.evaluateJavascript(script, callback)
                } catch (error: Exception) {
                    continuation.resumeWithException(error)
                }
            }
        }
    }

    private suspend fun evaluateValue(
        tab: BrowserTab,
        body: String?
    ): JsonElement {
        val helpersBlock = if (tab.helpersInjected) {
            """
                const normalizeText = window.__omni.normalizeText;
                const isVisible = window.__omni.isVisible;
                const isInteractive = window.__omni.isInteractive;
                const selectorForElement = window.__omni.selectorForElement;
                const describeElement = window.__omni.describeElement;
                const resolveTarget = window.__omni.resolveTarget;
                const resolveScrollable = window.__omni.resolveScrollable;
                const scrollTopOf = window.__omni.scrollTopOf;
                const scrollTarget = window.__omni.scrollTarget;
                const detectCollectionSelector = window.__omni.detectCollectionSelector;
                const safeSerialize = window.__omni.safeSerialize;
            """.trimIndent()
        } else {
            JS_HELPERS_FULL
        }
        val wrappedScript = """
            (function() {
                $helpersBlock
                try {
                    const __result = (function() {
                        ${body.orEmpty()}
                    })();
                    return JSON.stringify({ ok: true, value: safeSerialize(__result, 0) });
                } catch (error) {
                    return JSON.stringify({
                        ok: false,
                        error: String(error && error.message ? error.message : error)
                    });
                }
            })();
        """.trimIndent()
        val raw = evaluateJavascriptRaw(tab, wrappedScript)
        tab.helpersInjected = true
        val decoded = decodeJavascriptString(raw)
        val envelope = json.parseToJsonElement(decoded).jsonObject
        val ok = envelope["ok"]?.jsonPrimitive?.booleanOrNull == true
        if (!ok) {
            val message = envelope["error"]?.jsonPrimitive?.contentOrNull ?: "JavaScript 执行失败"
            throw IllegalStateException(message)
        }
        return envelope["value"] ?: JsonNull
    }

    private fun viewportDimensionsForProfile(
        profile: BrowserUserAgentProfile
    ): Pair<Int, Int> {
        return when (profile) {
            BrowserUserAgentProfile.DESKTOP_SAFARI -> {
                val w = (DESKTOP_VIEWPORT_WIDTH * density).toInt().coerceAtLeast(DESKTOP_VIEWPORT_WIDTH)
                val h = (DESKTOP_VIEWPORT_HEIGHT * density).toInt().coerceAtLeast(DESKTOP_VIEWPORT_HEIGHT)
                w to h
            }
            BrowserUserAgentProfile.MOBILE_SAFARI -> {
                viewportWidth to viewportHeight
            }
        }
    }

    private fun layoutWebView(
        webView: WebView,
        targetWidth: Int = viewportWidth,
        targetHeight: Int = viewportHeight
    ) {
        val parent = webView.parent as? View
        val measuredWidth = listOf(webView.width, parent?.width ?: 0, targetWidth)
            .firstOrNull { it > 0 } ?: targetWidth
        val measuredHeight = listOf(webView.height, parent?.height ?: 0, targetHeight)
            .firstOrNull { it > 0 } ?: targetHeight
        val widthSpec = View.MeasureSpec.makeMeasureSpec(measuredWidth, View.MeasureSpec.EXACTLY)
        val heightSpec = View.MeasureSpec.makeMeasureSpec(measuredHeight, View.MeasureSpec.EXACTLY)
        webView.measure(widthSpec, heightSpec)
        webView.layout(0, 0, measuredWidth, measuredHeight)
    }

    private fun decodeJavascriptString(raw: String?): String {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return ""
        return try {
            when (val parsed = JSONTokener(text).nextValue()) {
                is String -> parsed
                else -> text
            }
        } catch (_: Exception) {
            text
        }
    }

    private fun jsonElementToAny(element: JsonElement): Any? {
        return when (element) {
            JsonNull -> null
            is JsonPrimitive -> {
                element.booleanOrNull
                    ?: element.intOrNull
                    ?: element.contentOrNull
            }
            is JsonArray -> element.map { jsonElementToAny(it) }
            is JsonObject -> element.entries.associate { (key, value) ->
                key to jsonElementToAny(value)
            }
        }
    }

    private fun resolveDownloadFileName(connection: HttpURLConnection, url: String): String {
        val disposition = connection.getHeaderField("Content-Disposition").orEmpty()
        Regex("filename\\*=UTF-8''([^;]+)").find(disposition)?.groupValues?.getOrNull(1)?.let { encoded ->
            return sanitizeFileName(URLDecoder.decode(encoded, "UTF-8"))
        }
        Regex("filename=\"?([^\";]+)\"?").find(disposition)?.groupValues?.getOrNull(1)?.let { fileName ->
            return sanitizeFileName(fileName)
        }
        val fromUrl = URL(url).path.substringAfterLast('/').substringBefore('?')
        if (fromUrl.isNotBlank()) {
            return sanitizeFileName(fromUrl)
        }
        val extension = extensionFromContentType(connection.contentType)
        return "fetch_${UUID.randomUUID().toString().take(8)}.${extension.ifBlank { "bin" }}"
    }

    private fun sanitizeFileName(value: String): String {
        return value.trim()
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifBlank { "download.bin" }
    }

    private fun extensionFromContentType(contentType: String?): String {
        return when (contentType?.substringBefore(';')?.trim()?.lowercase(Locale.ROOT)) {
            "text/html" -> "html"
            "application/json" -> "json"
            "text/plain" -> "txt"
            "image/png" -> "png"
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            "application/pdf" -> "pdf"
            else -> "bin"
        }
    }

    private fun siteRootFromUrl(rawUrl: String): String {
        val parsed = URL(rawUrl)
        val portPart = if (parsed.port > 0 && parsed.port != parsed.defaultPort) ":${parsed.port}" else ""
        return "${parsed.protocol}://${parsed.host}$portPart/"
    }

    private suspend fun collectCookiesForUrl(rawUrl: String): LinkedHashMap<String, String> {
        withContext(Dispatchers.Main.immediate) {
            CookieManager.getInstance().flush()
        }
        val cookieManager = CookieManager.getInstance()
        val cookies = linkedMapOf<String, String>()
        buildCookieLookupUrls(rawUrl).forEach { candidateUrl ->
            parseCookieHeader(cookieManager.getCookie(candidateUrl).orEmpty()).forEach { (name, value) ->
                if (!cookies.containsKey(name)) {
                    cookies[name] = value
                }
            }
        }
        return cookies
    }

    private fun buildCookieLookupUrls(rawUrl: String): List<String> {
        return runCatching {
            val parsed = URL(rawUrl)
            val normalizedUri = URI(rawUrl)
            val portPart =
                if (parsed.port > 0 && parsed.port != parsed.defaultPort) ":${parsed.port}" else ""
            val origin = "${parsed.protocol}://${parsed.host}$portPart"
            linkedSetOf(
                rawUrl,
                normalizedUri.run {
                    val path = path?.takeIf { it.isNotBlank() } ?: "/"
                    "$origin$path"
                },
                origin,
                "$origin/"
            ).toList()
        }.getOrElse {
            listOf(rawUrl)
        }
    }

    private fun parseCookieHeader(rawCookieHeader: String): List<Pair<String, String>> {
        return rawCookieHeader.split(';')
            .mapNotNull { pair ->
                val parts = pair.trim().split("=", limit = 2)
                if (parts.size != 2) {
                    null
                } else {
                    parts[0].trim() to parts[1]
                }
            }
    }

    private fun buildTargetedScript(
        request: BrowserUseRequest,
        command: String
    ): String {
        val selectorLiteral = request.selector?.let { JSONObject.quote(it) } ?: "null"
        val xLiteral = request.coordinateX?.toString() ?: "null"
        val yLiteral = request.coordinateY?.toString() ?: "null"
        return """
            const selector = $selectorLiteral;
            const coordinateX = $xLiteral;
            const coordinateY = $yLiteral;
            const target = resolveTarget(selector, coordinateX, coordinateY);
            if (!target) {
                throw new Error('Target element not found');
            }
            const rect = target.getBoundingClientRect();
            const centerX = Math.round(rect.left + rect.width / 2);
            const centerY = Math.round(rect.top + rect.height / 2);
            $command
        """.trimIndent()
    }

    private inner class BrowserTabClient(
        private val tab: BrowserTab
    ) : WebViewClient() {
        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
            tab.isLoading = true
            tab.currentUrl = url
            tab.title = view?.title ?: tab.title
            tab.lastError = null
            tab.helpersInjected = false
            if (tab.loadWaiter?.isActive != true) {
                tab.loadWaiter = CompletableDeferred()
            }
        }

        override fun onPageFinished(view: WebView?, url: String?) {
            tab.isLoading = false
            tab.currentUrl = url
            tab.title = view?.title ?: tab.title
            val waiter = tab.loadWaiter
            if (waiter?.isActive == true) {
                mainScope.launch {
                    delay(LOAD_SETTLE_DELAY_MS)
                    if (waiter.isActive) {
                        waiter.complete(
                            LoadSnapshot(
                                url = tab.currentUrl,
                                title = tab.title,
                                errorMessage = tab.lastError
                            )
                        )
                    }
                }
            }
        }

        override fun onReceivedError(
            view: WebView?,
            request: WebResourceRequest?,
            error: WebResourceError?
        ) {
            if (request?.isForMainFrame == false) return
            tab.isLoading = false
            tab.currentUrl = request?.url?.toString() ?: tab.currentUrl
            tab.lastError = error?.description?.toString() ?: "页面加载失败"
            tab.loadWaiter?.takeIf { it.isActive }?.complete(
                LoadSnapshot(
                    url = tab.currentUrl,
                    title = tab.title,
                    errorMessage = tab.lastError
                )
            )
        }
    }
}
