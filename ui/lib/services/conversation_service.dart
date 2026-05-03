import 'package:flutter/services.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/conversation_history_service.dart';

class ConversationService {
  static const MethodChannel _assistCore = MethodChannel(
    'cn.com.omnimind.bot/AssistCoreEvent',
  );

  static List<ConversationModel> _normalizeConversations(List<dynamic> raw) {
    final conversations = raw
        .whereType<Map>()
        .map(
          (json) => ConversationModel.fromJson(
            Map<String, dynamic>.from(json.cast<String, dynamic>()),
          ),
        )
        .toList();
    conversations.sort((a, b) {
      final byUpdatedAt = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdatedAt != 0) return byUpdatedAt;
      final aPenalty = a.mode == ConversationMode.subagent ? 1 : 0;
      final bPenalty = b.mode == ConversationMode.subagent ? 1 : 0;
      final byMode = aPenalty.compareTo(bPenalty);
      if (byMode != 0) return byMode;
      return b.createdAt.compareTo(a.createdAt);
    });
    return conversations;
  }

  static Future<List<ConversationModel>> getAllConversations({
    bool includeArchived = false,
    bool archivedOnly = false,
  }) async {
    try {
      final result = await _assistCore.invokeMethod<List<dynamic>>(
        'getConversations',
      );
      if (result == null) return [];
      final conversations = _normalizeConversations(result);
      if (archivedOnly) {
        return conversations.where((item) => item.isArchived).toList();
      }
      if (includeArchived) {
        return conversations;
      }
      return conversations.where((item) => !item.isArchived).toList();
    } on PlatformException catch (e) {
      print('[ConversationService] 获取对话列表失败: ${e.message}');
      return [];
    } catch (e) {
      print('[ConversationService] 获取对话列表异常: $e');
      return [];
    }
  }

  static Future<List<ConversationModel>> getConversationsByPage({
    required int offset,
    required int limit,
    bool includeArchived = false,
    bool archivedOnly = false,
  }) async {
    final all = await getAllConversations(
      includeArchived: includeArchived,
      archivedOnly: archivedOnly,
    );
    if (all.isEmpty) return [];
    final start = offset < 0 ? 0 : offset;
    if (start >= all.length) return [];
    final end = (start + limit) > all.length ? all.length : (start + limit);
    return all.sublist(start, end);
  }

  static Future<int?> createConversation({
    required String title,
    String? summary,
    ConversationMode mode = ConversationMode.normal,
  }) async {
    try {
      final result = await _assistCore.invokeMethod<dynamic>(
        'createConversation',
        {'title': title, 'summary': summary, 'mode': mode.storageValue},
      );
      if (result is int) return result;
      if (result is String) return int.tryParse(result);
      return null;
    } on PlatformException catch (e) {
      print('创建对话失败: ${e.message}');
      return null;
    } catch (e) {
      print('创建对话失败: $e');
      return null;
    }
  }

  static Future<bool> updateConversation(ConversationModel conversation) async {
    try {
      final result = await _assistCore.invokeMethod<dynamic>(
        'updateConversation',
        {'conversation': conversation.toJson()},
      );
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('更新对话失败: ${e.message}');
      return false;
    } catch (e) {
      print('更新对话失败: $e');
      return false;
    }
  }

  static Future<bool> updateConversationPromptTokenThreshold({
    required int conversationId,
    required int promptTokenThreshold,
  }) async {
    try {
      final result = await _assistCore
          .invokeMethod<dynamic>('updateConversationPromptTokenThreshold', {
            'conversationId': conversationId,
            'promptTokenThreshold': promptTokenThreshold,
          });
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('更新对话压缩阈值失败: ${e.message}');
      return false;
    } catch (e) {
      print('更新对话压缩阈值失败: $e');
      return false;
    }
  }

  static Future<bool> deleteConversation(
    int conversationId, {
    ConversationMode? mode,
  }) async {
    if (mode == ConversationMode.codex) {
      try {
        await CodexAppServerService.archiveThread(
          conversationId: conversationId,
        );
        final conversations = await getAllConversations(includeArchived: true);
        final conversation = conversations
            .where((item) => item.id == conversationId)
            .cast<ConversationModel?>()
            .firstWhere((item) => item != null, orElse: () => null);
        if (conversation != null && !conversation.isArchived) {
          await updateConversation(conversation.copyWith(isArchived: true));
        }
        await ConversationHistoryService.clearConversationThreadReferences(
          conversationId,
          mode: ConversationMode.codex,
        );
        await setCurrentConversationTarget(
          await ConversationHistoryService.getLastVisibleThreadTarget(),
        );
        return true;
      } catch (e) {
        print('归档 Codex 对话失败: $e');
        return false;
      }
    }
    try {
      final result = await _assistCore.invokeMethod<dynamic>(
        'deleteConversation',
        {
          'conversationId': conversationId,
          if (mode != null) 'mode': mode.storageValue,
        },
      );
      final deleted = result == 'SUCCESS';
      if (!deleted) {
        return false;
      }
      await ConversationHistoryService.clearConversationMessages(
        conversationId,
        mode: mode ?? ConversationMode.normal,
      );
      await ConversationHistoryService.clearConversationThreadReferences(
        conversationId,
        mode: mode,
      );
      await setCurrentConversationTarget(
        await ConversationHistoryService.getLastVisibleThreadTarget(),
      );
      return true;
    } on PlatformException catch (e) {
      print('删除对话失败: ${e.message}');
      return false;
    } catch (e) {
      print('删除对话失败: $e');
      return false;
    }
  }

  static Future<bool> archiveConversation(
    ConversationModel conversation,
  ) async {
    if (conversation.mode == ConversationMode.codex) {
      try {
        await CodexAppServerService.archiveThread(
          conversationId: conversation.id,
        );
      } catch (e) {
        print('Codex 归档失败: $e');
        return false;
      }
    }
    final archived = await updateConversation(
      conversation.copyWith(isArchived: true),
    );
    if (!archived) {
      return false;
    }
    if (conversation.mode == ConversationMode.codex) {
      await ConversationHistoryService.clearConversationThreadReferences(
        conversation.id,
        mode: ConversationMode.codex,
      );
    }
    await setCurrentConversationTarget(
      await ConversationHistoryService.getLastVisibleThreadTarget(),
    );
    return true;
  }

  static Future<bool> unarchiveConversation(
    ConversationModel conversation,
  ) async {
    if (conversation.mode == ConversationMode.codex) {
      try {
        await CodexAppServerService.unarchiveThread(
          conversationId: conversation.id,
        );
      } catch (e) {
        print('Codex 恢复失败: $e');
        return false;
      }
    }
    return updateConversation(conversation.copyWith(isArchived: false));
  }

  static Future<bool> updateConversationTitle({
    required int conversationId,
    required String newTitle,
    ConversationMode mode = ConversationMode.normal,
  }) async {
    if (mode == ConversationMode.codex) {
      try {
        await CodexAppServerService.setThreadName(
          conversationId: conversationId,
          name: newTitle,
        );
        return true;
      } catch (e) {
        print('更新 Codex 对话标题失败: $e');
        return false;
      }
    }
    try {
      final result = await _assistCore
          .invokeMethod<dynamic>('updateConversationTitle', {
            'conversationId': conversationId,
            'newTitle': newTitle,
            'mode': mode.storageValue,
          });
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('更新对话标题失败: ${e.message}');
      return false;
    } catch (e) {
      print('更新对话标题失败: $e');
      return false;
    }
  }

  static Future<String?> generateConversationSummary({
    required String conversationHistory,
  }) async {
    try {
      final result = await _assistCore.invokeMethod(
        'generateConversationSummary',
        {'conversationHistory': conversationHistory},
      );
      return result as String?;
    } on PlatformException catch (e) {
      print('生成对话摘要失败: ${e.message}');
      return null;
    } catch (e) {
      print('生成对话摘要失败: $e');
      return null;
    }
  }

  static Future<bool> completeConversation(
    int conversationId, {
    ConversationMode? mode,
  }) async {
    try {
      final result = await _assistCore.invokeMethod<dynamic>(
        'completeConversation',
        {
          'conversationId': conversationId,
          if (mode != null) 'mode': mode.storageValue,
        },
      );
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('完成对话失败: ${e.message}');
      return false;
    } catch (e) {
      print('完成对话失败: $e');
      return false;
    }
  }

  static Future<bool> setCurrentConversationId(
    int? conversationId, {
    ConversationMode mode = ConversationMode.normal,
  }) async {
    try {
      final result = await _assistCore.invokeMethod<dynamic>(
        'setCurrentConversationId',
        {'conversationId': conversationId ?? 0, 'mode': mode.storageValue},
      );
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('设置当前对话ID失败: ${e.message}');
      return false;
    } catch (e) {
      print('设置当前对话ID失败: $e');
      return false;
    }
  }

  static Future<bool> setCurrentConversationTarget(
    ConversationThreadTarget? target,
  ) async {
    return setCurrentConversationId(
      target?.conversationId,
      mode: target?.mode ?? ConversationMode.normal,
    );
  }

  static Future<ConversationModel?> getLatestConversation({
    ConversationMode? mode,
    bool includeArchived = false,
  }) async {
    final conversations = await getAllConversations(
      includeArchived: includeArchived,
    );
    for (final conversation in conversations) {
      if (mode == null || conversation.mode == mode) {
        return conversation;
      }
    }
    return null;
  }

  static Future<ConversationThreadTarget?> getLatestConversationTarget({
    ConversationMode? mode,
    bool includeArchived = false,
  }) async {
    final conversation = await getLatestConversation(
      mode: mode,
      includeArchived: includeArchived,
    );
    if (conversation == null) {
      return null;
    }
    return ConversationThreadTarget.existing(
      conversationId: conversation.id,
      mode: conversation.mode,
    );
  }
}
