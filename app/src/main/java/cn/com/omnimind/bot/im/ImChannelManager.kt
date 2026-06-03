package cn.com.omnimind.bot.im

import android.content.Context
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.webchat.RealtimeEvent
import cn.com.omnimind.bot.webchat.RealtimeHub
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

object ImChannelManager {
    private const val TAG = "[ImChannelManager]"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val pendingRuns = ConcurrentHashMap<String, PendingImRun>()
    private val telegramConnector = TelegramImConnector()
    private val wechatConnector = OpenILinkWechatConnector { token, baseUrl, botId ->
        appContext?.let { context ->
            ImChannelStore(context).saveWechatCredentials(token, baseUrl)
            ImChannelForegroundService.ensureState(context)
        }
        if (!botId.isNullOrBlank()) {
            OmniLog.d(TAG, "OpeniLink QR login connected: $botId")
        }
    }
    private val connectors: Map<ImChannelType, ImConnector> = mapOf(
        ImChannelType.TELEGRAM to telegramConnector,
        ImChannelType.WECHAT to wechatConnector
    )

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var store: ImChannelStore? = null

    @Volatile
    private var processor: ImCommandProcessor? = null

    private var realtimeJob: Job? = null

    fun restoreIfEnabled(context: Context) {
        val settings = ImChannelStore(context).loadSettings()
        if (settings.anyEnabled()) {
            ImChannelForegroundService.ensureState(context)
        }
    }

    fun start(context: Context) {
        scope.launch {
            reload(context)
        }
    }

    fun stop() {
        scope.launch {
            connectors.values.forEach { connector ->
                runCatching { connector.stop() }
            }
            pendingRuns.clear()
            realtimeJob?.cancel()
            realtimeJob = null
        }
    }

    suspend fun currentState(context: Context): Map<String, Any?> {
        ensureInitialized(context)
        return buildState()
    }

    suspend fun reload(context: Context): Map<String, Any?> {
        ensureInitialized(context)
        val settings = requireStore().loadSettings()
        connectors.values.forEach { connector ->
            runCatching {
                connector.start(settings, ::handleInboundMessage)
            }.onFailure { error ->
                OmniLog.e(TAG, "connector ${connector.channel.id} start failed: ${error.message}")
            }
        }
        return buildState()
    }

    suspend fun saveTelegram(context: Context, config: TelegramImConfig): Map<String, Any?> {
        ensureInitialized(context)
        requireStore().saveTelegram(config)
        val state = reload(context)
        ImChannelForegroundService.ensureState(context)
        return state
    }

    suspend fun saveWechat(context: Context, config: WechatImConfig): Map<String, Any?> {
        ensureInitialized(context)
        requireStore().saveWechat(config)
        val state = reload(context)
        ImChannelForegroundService.ensureState(context)
        return state
    }

    suspend fun setChannelEnabled(
        context: Context,
        channel: ImChannelType,
        enabled: Boolean
    ): Map<String, Any?> {
        ensureInitialized(context)
        requireStore().setChannelEnabled(channel, enabled)
        val state = reload(context)
        ImChannelForegroundService.ensureState(context)
        return state
    }

    suspend fun requestWechatQr(context: Context): Map<String, Any?> {
        ensureInitialized(context)
        val result = wechatConnector.requestQr()
        return result + mapOf("state" to buildState())
    }

    suspend fun clearPeerSessions(context: Context): Map<String, Any?> {
        ensureInitialized(context)
        requireStore().clearPeerSessions()
        return buildState()
    }

    private fun ensureInitialized(context: Context) {
        if (appContext == null) {
            synchronized(this) {
                if (appContext == null) {
                    val applicationContext = context.applicationContext
                    appContext = applicationContext
                    store = ImChannelStore(applicationContext)
                    processor = ImCommandProcessor(
                        applicationContext,
                        requireStore(),
                        ::buildStatusText
                    )
                    ensureRealtimeCollection()
                }
            }
        } else {
            ensureRealtimeCollection()
        }
    }

    private fun ensureRealtimeCollection() {
        if (realtimeJob?.isActive == true) return
        realtimeJob = scope.launch {
            RealtimeHub.stream().collect { event ->
                handleRealtimeEvent(event)
            }
        }
    }

    private suspend fun handleInboundMessage(inbound: ImInboundMessage) {
        val activeProcessor = processor ?: return
        runCatching {
            if (!inbound.text.trimStart().startsWith("/")) {
                connectors[inbound.channel]?.sendTyping(inbound.peerId)
            }
        }
        val result = runCatching { activeProcessor.handle(inbound) }
            .getOrElse { error ->
                ImProcessorResult(
                    replies = listOf("处理 IM 消息失败：${error.message ?: error.javaClass.simpleName}")
                )
            }
        result.pendingRun?.let { pendingRuns[it.taskId] = it }
        result.replies.forEach { reply ->
            sendChunked(inbound.channel, inbound.peerId, reply)
        }
    }

    private suspend fun handleRealtimeEvent(event: RealtimeEvent) {
        if (event.event != "agent_stream_event") return
        val taskId = event.data["taskId"]?.toString()?.takeIf { it.isNotBlank() } ?: return
        val pending = pendingRuns[taskId] ?: return
        val kind = event.data["kind"]?.toString().orEmpty()
        val isFinal = event.data["isFinal"] == true
        when {
            kind == "text_snapshot" && isFinal -> {
                val text = event.data["text"]?.toString()?.trim().orEmpty()
                sendChunked(
                    pending.channel,
                    pending.peerId,
                    text.ifEmpty { "任务已完成，但没有产生文本输出。" }
                )
                finishPendingRun(taskId)
            }

            kind == "clarify_required" -> {
                val question = sequenceOf(
                    event.data["question"]?.toString(),
                    event.data["text"]?.toString()
                ).firstOrNull { !it.isNullOrBlank() } ?: "需要补充信息，请直接回复。"
                requireStore().markAwaitingInput(taskId, awaitingInput = true)
                sendChunked(
                    pending.channel,
                    pending.peerId,
                    "$question\n\n请直接回复补充信息，或发送 /cancel 取消。"
                )
            }

            kind == "permission_required" -> {
                val text = sequenceOf(
                    event.data["text"]?.toString(),
                    event.data["error"]?.toString()
                ).firstOrNull { !it.isNullOrBlank() } ?: "执行前需要回到 App 开启相关权限。"
                sendChunked(pending.channel, pending.peerId, text)
                finishPendingRun(taskId)
            }

            kind == "error" -> {
                val text = sequenceOf(
                    event.data["error"]?.toString(),
                    event.data["text"]?.toString()
                ).firstOrNull { !it.isNullOrBlank() } ?: "任务执行失败。"
                sendChunked(pending.channel, pending.peerId, "任务失败：$text")
                finishPendingRun(taskId)
            }

            kind == "completed" -> {
                finishPendingRun(taskId)
            }
        }
    }

    private fun finishPendingRun(taskId: String) {
        pendingRuns.remove(taskId)
        requireStore().clearActiveTask(taskId)
    }

    private suspend fun sendChunked(
        channel: ImChannelType,
        peerId: String,
        text: String
    ) {
        val connector = connectors[channel] ?: return
        val chunkSize = requireStore().loadSettings().chunkSizeFor(channel)
        val chunks = splitForIm(text, chunkSize)
        chunks.forEachIndexed { index, chunk ->
            runCatching {
                connector.sendText(peerId, chunk)
            }.onFailure { error ->
                OmniLog.e(TAG, "send ${channel.id} chunk failed: ${error.message}")
            }
            if (index < chunks.lastIndex) {
                delay(250)
            }
        }
    }

    private fun splitForIm(text: String, maxChars: Int): List<String> {
        val normalized = text.ifBlank { " " }
        val chunks = mutableListOf<String>()
        var start = 0
        while (start < normalized.length) {
            var end = (start + maxChars).coerceAtMost(normalized.length)
            if (end < normalized.length && Character.isHighSurrogate(normalized[end - 1])) {
                end -= 1
            }
            if (end <= start) {
                end = (start + maxChars).coerceAtMost(normalized.length)
            }
            chunks += normalized.substring(start, end)
            start = end
        }
        return chunks.ifEmpty { listOf(" ") }
    }

    private fun buildState(): Map<String, Any?> {
        val activeStore = requireStore()
        val settings = activeStore.loadSettings()
        val connectorStatuses = connectors.values.map { it.currentStatus() }
        return linkedMapOf(
            "settings" to settings.toMap(),
            "status" to linkedMapOf(
                "running" to connectorStatuses.any { it.running },
                "pendingRunCount" to pendingRuns.size,
                "sessionCount" to activeStore.listSessions().size,
                "connectors" to connectorStatuses.map { it.toMap() }
            ),
            "sessions" to activeStore.listSessions().map { it.toMap() }
        )
    }

    private fun buildStatusText(
        inbound: ImInboundMessage,
        session: ImPeerSession?
    ): String {
        val activeStore = requireStore()
        val connectorText = connectors.values.joinToString("\n") { connector ->
            val state = connector.currentStatus()
            val connected = if (state.connected) "connected" else "disconnected"
            val running = if (state.running) "running" else "stopped"
            val error = state.lastError.takeIf { it.isNotBlank() }?.let { " error=$it" }.orEmpty()
            "${state.channel.title}: $running/$connected$error"
        }
        val current = session?.let {
            "session: mode=${imModeLabel(it.mode)} conversationId=${it.conversationId}" +
                it.activeTaskId?.let { taskId -> " activeTask=$taskId" }.orEmpty()
        } ?: "session: none"
        return """
            IM 状态
            peer: ${inbound.channel.id}/${inbound.peerId}
            $current
            pendingRuns: ${pendingRuns.size}
            savedSessions: ${activeStore.listSessions().size}
            $connectorText
        """.trimIndent()
    }

    private fun requireStore(): ImChannelStore {
        return store ?: throw IllegalStateException("IM channel store not initialized")
    }
}
