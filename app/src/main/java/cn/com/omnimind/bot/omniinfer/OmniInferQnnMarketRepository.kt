package cn.com.omnimind.bot.omniinfer

import android.content.Context
import android.os.Build
import cn.com.omnimind.baselib.util.OmniLog

/**
 * QNN model catalog for ExecuTorch QNN backend.
 * Models are pre-exported .pte files hosted on ModelScope (BiReRa/omniinfer-01001).
 * Filtered by device SoC — only models matching the current chip are shown.
 */
object OmniInferQnnMarketRepository {
    private const val TAG = "OmniInferQnnMarketRepository"

    private const val BASE_URL =
        "https://modelscope.cn/models/BiReRa/omniinfer-01001/resolve/master"

    /** Shared tokenizer for all Qwen3 models. */
    private const val TOKENIZER_URL =
        "$BASE_URL/SM8650_qwen3-0_6b/tokenizer.json"

    data class QnnModelEntry(
        val modelId: String,
        val modelName: String,
        val soc: String,
        val socLabel: String,
        val pteUrl: String,
        val tokenizerUrl: String,
        val fileSize: Long,
        val sizeGb: Double,
        val decoderModelVersion: String = "qwen3",
    )

    data class ResolvedQnnModel(
        val modelId: String,
        val entry: QnnModelEntry,
    )

    /** All known QNN models. */
    private val allEntries: List<QnnModelEntry> = listOf(
        // SM8650 (Snapdragon 8 Gen 3)
        QnnModelEntry(
            modelId = "SM8650_qwen3-0_6b",
            modelName = "Qwen3-0.6B",
            soc = "SM8650",
            socLabel = "8 Gen 3",
            pteUrl = "$BASE_URL/SM8650_qwen3-0_6b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 713_031_680L, // ~680 MB
            sizeGb = 0.68,
        ),
        QnnModelEntry(
            modelId = "SM8650_qwen3-1_7b",
            modelName = "Qwen3-1.7B",
            soc = "SM8650",
            socLabel = "8 Gen 3",
            pteUrl = "$BASE_URL/SM8650_qwen3-1_7b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 1_825_361_920L, // ~1.7 GB
            sizeGb = 1.7,
        ),
        QnnModelEntry(
            modelId = "SM8650_qwen3-4b",
            modelName = "Qwen3-4B",
            soc = "SM8650",
            socLabel = "8 Gen 3",
            pteUrl = "$BASE_URL/SM8650_qwen3-4b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 3_328_599_040L, // ~3.1 GB
            sizeGb = 3.1,
        ),
        // SM8750 (Snapdragon 8 Elite)
        QnnModelEntry(
            modelId = "SM8750_qwen3-0_6b",
            modelName = "Qwen3-0.6B",
            soc = "SM8750",
            socLabel = "8 Elite",
            pteUrl = "$BASE_URL/SM8750_qwen3-0_6b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 711_983_104L, // ~679 MB
            sizeGb = 0.68,
        ),
        QnnModelEntry(
            modelId = "SM8750_qwen3-1_7b",
            modelName = "Qwen3-1.7B",
            soc = "SM8750",
            socLabel = "8 Elite",
            pteUrl = "$BASE_URL/SM8750_qwen3-1_7b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 1_825_361_920L, // ~1.7 GB
            sizeGb = 1.7,
        ),
        QnnModelEntry(
            modelId = "SM8750_qwen3-4b",
            modelName = "Qwen3-4B",
            soc = "SM8750",
            socLabel = "8 Elite",
            pteUrl = "$BASE_URL/SM8750_qwen3-4b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 3_328_599_040L, // ~3.1 GB
            sizeGb = 3.1,
        ),
        // SM8850 (Snapdragon 8 Elite Gen 5)
        QnnModelEntry(
            modelId = "SM8850_qwen3-0_6b",
            modelName = "Qwen3-0.6B",
            soc = "SM8850",
            socLabel = "8 Elite Gen 5",
            pteUrl = "$BASE_URL/SM8850_qwen3-0_6b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 715_128_832L, // ~682 MB
            sizeGb = 0.68,
        ),
        QnnModelEntry(
            modelId = "SM8850_qwen3-1_7b",
            modelName = "Qwen3-1.7B",
            soc = "SM8850",
            socLabel = "8 Elite Gen 5",
            pteUrl = "$BASE_URL/SM8850_qwen3-1_7b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 1_825_361_920L, // ~1.7 GB
            sizeGb = 1.7,
        ),
        QnnModelEntry(
            modelId = "SM8850_qwen3-4b",
            modelName = "Qwen3-4B",
            soc = "SM8850",
            socLabel = "8 Elite Gen 5",
            pteUrl = "$BASE_URL/SM8850_qwen3-4b/hybrid_llama_qnn.pte",
            tokenizerUrl = TOKENIZER_URL,
            fileSize = 3_328_599_040L, // ~3.1 GB
            sizeGb = 3.1,
        ),
    )

    fun getDeviceSoc(): String {
        val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Build.SOC_MODEL.trim()
        } else {
            ""
        }
        OmniLog.i(TAG, "[getDeviceSoc] Build.SOC_MODEL='${Build.SOC_MODEL}', " +
            "Build.HARDWARE='${Build.HARDWARE}', Build.BOARD='${Build.BOARD}', " +
            "Build.DEVICE='${Build.DEVICE}', normalized='$soc'")
        return soc
    }

    fun listModels(filterBySoc: Boolean = true): List<ResolvedQnnModel> {
        val soc = getDeviceSoc()
        OmniLog.d(TAG, "[listModels] device SoC=$soc, filterBySoc=$filterBySoc")
        val entries = if (filterBySoc && soc.isNotEmpty()) {
            allEntries.filter { it.soc.equals(soc, ignoreCase = true) }
        } else {
            allEntries
        }
        return entries.map { ResolvedQnnModel(modelId = it.modelId, entry = it) }
    }

    fun findModel(modelId: String): ResolvedQnnModel? {
        val normalizedId = modelId.trim()
        if (normalizedId.isEmpty()) return null
        val entry = allEntries.firstOrNull { it.modelId == normalizedId }
            ?: return null
        return ResolvedQnnModel(modelId = entry.modelId, entry = entry)
    }

    fun allModels(): List<ResolvedQnnModel> = listModels(filterBySoc = false)

    fun isDeviceSupported(): Boolean {
        val soc = getDeviceSoc()
        return allEntries.any { it.soc.equals(soc, ignoreCase = true) }
    }
}
