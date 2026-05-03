import 'dart:convert';

import 'package:ui/features/home/pages/chat/mixins/agent_stream_handler.dart';
import 'package:ui/features/home/pages/chat/services/chat_conversation_runtime_coordinator.dart';
import 'package:ui/models/chat_message_model.dart';

class CodexReduceResult {
  const CodexReduceResult({
    required this.handled,
    this.method,
    this.threadId,
    this.turnId,
    this.requestId,
  });

  final bool handled;
  final String? method;
  final String? threadId;
  final String? turnId;
  final Object? requestId;
}

class CodexEventReducer {
  const CodexEventReducer();

  CodexReduceResult reduce({
    required ChatConversationRuntimeState runtime,
    required Map<String, dynamic> event,
  }) {
    final message = _asStringMap(event['message']) ?? event;
    final method = _string(message['method']) ?? _string(event['method']);
    if (method == null || method.isEmpty) {
      return const CodexReduceResult(handled: false);
    }

    final params =
        _asStringMap(message['params']) ??
        _asStringMap(event['params']) ??
        const <String, dynamic>{};
    final threadId = _firstString([
      event['threadId'],
      params['threadId'],
      params['thread_id'],
      _asStringMap(params['thread'])?['id'],
    ]);
    final turnId = _firstString([
      event['turnId'],
      params['turnId'],
      params['turn_id'],
      _asStringMap(params['turn'])?['id'],
    ]);
    final itemId = _firstString([
      params['itemId'],
      params['item_id'],
      _asStringMap(params['item'])?['id'],
      params['id'],
    ]);
    final taskId =
        _firstString([turnId, itemId, threadId]) ??
        'codex-${runtime.conversationId}';

    if (method == 'turn/started') {
      runtime.isAiResponding = true;
      runtime.currentDispatchTaskId = taskId;
      runtime.lastAgentTaskId = taskId;
      runtime.currentThinkingStage = ThinkingStage.thinking.value;
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'turn/completed' || method == 'thread/closed') {
      _completeTurn(runtime, taskId);
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/started') {
      final item = _asStringMap(params['item']) ?? params;
      final itemType = _string(item['type']) ?? '';
      final startedItemId = _firstString([item['id'], params['id']]) ?? taskId;
      if (itemType == 'reasoning') {
        _upsertThinkingCard(
          runtime,
          taskId: taskId,
          cardId: '$startedItemId-codex-thinking',
          isLoading: true,
          stage: ThinkingStage.thinking.value,
        );
      } else if (itemType == 'agentMessage') {
        final text = _extractText(item['text']) ?? '';
        if (text.isNotEmpty) {
          _appendAssistantText(runtime, taskId, text);
        }
      } else if (itemType == 'commandExecution' || itemType == 'fileChange') {
        _upsertToolCard(
          runtime,
          cardId:
              '$startedItemId-codex-${itemType == 'commandExecution' ? 'command' : 'file'}',
          taskId: taskId,
          toolType: itemType == 'commandExecution' ? 'terminal' : 'file',
          title: itemType == 'commandExecution'
              ? _commandTitle(item)
              : 'Codex file change',
          status: 'running',
          summary: _extractText(item['summary']) ?? '',
          progress: _extractText(item['status']) ?? '',
          raw: item,
        );
      } else if (itemType.contains('requestApproval')) {
        _upsertCodexRequestCard(
          runtime,
          cardId: '$startedItemId-codex-approval',
          requestId: params['requestId'] ?? message['id'],
          requestKind: 'approval',
          title: _approvalTitle(itemType, item),
          detail: _approvalDetail(item),
          params: item,
        );
      } else if (itemType == 'tool' || itemType == 'mcpToolCall') {
        _upsertToolCard(
          runtime,
          cardId: '$startedItemId-codex-tool',
          taskId: taskId,
          toolType: _string(item['toolType']) ?? 'tool',
          title: _string(item['toolName']) ?? 'Codex tool',
          status: 'running',
          summary: _extractText(item['summary']) ?? '',
          progress: _extractText(item['progress']) ?? '',
          raw: item,
        );
      }
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
        requestId: params['requestId'] ?? message['id'],
      );
    }

    if (method == 'item/agentMessage/delta') {
      final delta =
          _extractText(params['delta']) ??
          _extractText(params['text']) ??
          _extractText(params['message']) ??
          '';
      if (delta.isNotEmpty) {
        _appendAssistantText(runtime, taskId, delta);
      }
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (_isReasoningMethod(method)) {
      final text =
          _extractText(params['delta']) ??
          _extractText(params['text']) ??
          _extractText(params['summary']) ??
          _extractText(params['part']) ??
          '';
      if (text.isNotEmpty) {
        _appendThinking(runtime, taskId, text);
      }
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/plan/delta' || method == 'turn/plan/updated') {
      final text =
          _extractText(params['delta']) ??
          _extractText(params['plan']) ??
          _extractText(params['text']) ??
          '';
      _upsertToolCard(
        runtime,
        cardId: '$taskId-codex-plan',
        taskId: taskId,
        toolType: 'plan',
        title: 'Codex plan',
        status: 'running',
        summary: text,
        progress: text,
        raw: params,
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/commandExecution/outputDelta' ||
        method == 'item/commandExecution/terminalInteraction') {
      final delta =
          _extractText(params['delta']) ??
          _extractText(params['output']) ??
          _extractText(params['text']) ??
          '';
      _appendToolOutput(
        runtime,
        cardId: '${itemId ?? taskId}-codex-command',
        taskId: taskId,
        toolType: 'terminal',
        title: _commandTitle(params),
        outputDelta: delta,
        raw: params,
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/fileChange/outputDelta' ||
        method == 'turn/diff/updated') {
      final delta =
          _extractText(params['delta']) ??
          _extractText(params['output']) ??
          _extractText(params['text']) ??
          '';
      _appendToolOutput(
        runtime,
        cardId: '${itemId ?? taskId}-codex-file',
        taskId: taskId,
        toolType: 'file',
        title: 'Codex file change',
        outputDelta: delta,
        raw: params,
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method.endsWith('requestApproval')) {
      final requestId = message['id'];
      _upsertCodexRequestCard(
        runtime,
        cardId: '${requestId ?? itemId ?? taskId}-codex-approval',
        requestId: requestId,
        requestKind: 'approval',
        title: _approvalTitle(method, params),
        detail: _approvalDetail(params),
        params: params,
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
        requestId: requestId,
      );
    }

    if (method == 'item/tool/requestUserInput') {
      final requestId = message['id'];
      final question = _firstQuestion(params);
      _upsertCodexRequestCard(
        runtime,
        cardId: '${requestId ?? itemId ?? taskId}-codex-user-input',
        requestId: requestId,
        requestKind: 'user_input',
        title: question.title,
        detail: question.detail,
        questionId: question.id,
        params: params,
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
        requestId: requestId,
      );
    }

    if (method == 'item/completed') {
      _completeItem(runtime, taskId, itemId, params);
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'account/updated' ||
        method == 'account/login/completed' ||
        method == 'account/rateLimits/updated' ||
        method == 'account/read') {
      _upsertToolCard(
        runtime,
        cardId: '$taskId-codex-account',
        taskId: taskId,
        toolType: 'account',
        title: method,
        status: 'success',
        summary: _accountSummary(params),
        progress: _accountSummary(params),
        raw: params,
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'codex/stderr' || method == 'codex/parseError') {
      final removedStaleCard = _removeCodexDebugStatusCards(runtime);
      return CodexReduceResult(
        handled: removedStaleCard,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'error') {
      final detail =
          _extractText(params['message']) ??
          _extractText(params['error']) ??
          _safeJson(params);
      _upsertToolCard(
        runtime,
        cardId: '$taskId-codex-status',
        taskId: taskId,
        toolType: 'status',
        title: method,
        status: 'error',
        summary: detail,
        progress: detail,
        raw: params,
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    return CodexReduceResult(
      handled: false,
      method: method,
      threadId: threadId,
      turnId: turnId,
    );
  }

  void _appendAssistantText(
    ChatConversationRuntimeState runtime,
    String taskId,
    String delta,
  ) {
    runtime.isAiResponding = true;
    runtime.currentDispatchTaskId = taskId;
    runtime.lastAgentTaskId = taskId;
    final messageId = '$taskId-codex-agent';
    final previous = runtime.currentAiMessages[messageId] ?? '';
    final next = previous + delta;
    runtime.currentAiMessages[messageId] = next;
    final index = runtime.messages.indexWhere(
      (message) => message.id == messageId,
    );
    final content = <String, dynamic>{'text': next, 'id': messageId};
    if (index == -1) {
      runtime.messages.removeWhere((message) => message.isLoading);
      runtime.messages.insert(
        0,
        ChatMessageModel(id: messageId, type: 1, user: 2, content: content),
      );
      return;
    }
    runtime.messages[index] = runtime.messages[index].copyWith(
      content: content,
      isLoading: false,
      isError: false,
    );
  }

  void _appendThinking(
    ChatConversationRuntimeState runtime,
    String taskId,
    String delta,
  ) {
    runtime.isDeepThinking = true;
    runtime.currentThinkingStage = ThinkingStage.thinking.value;
    runtime.deepThinkingContent = '${runtime.deepThinkingContent}$delta';
    runtime.lastAgentTaskId = taskId;
    final cardId = '$taskId-codex-thinking';
    _upsertThinkingCard(
      runtime,
      taskId: taskId,
      cardId: cardId,
      isLoading: true,
      stage: ThinkingStage.thinking.value,
    );
  }

  void _upsertThinkingCard(
    ChatConversationRuntimeState runtime, {
    required String taskId,
    required String cardId,
    required bool isLoading,
    required int stage,
  }) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    final startTime = index == -1
        ? DateTime.now().millisecondsSinceEpoch
        : _asInt(runtime.messages[index].cardData?['startTime']) ??
              DateTime.now().millisecondsSinceEpoch;
    final cardData = <String, dynamic>{
      'type': 'deep_thinking',
      'isLoading': isLoading,
      'thinkingContent': runtime.deepThinkingContent,
      'stage': stage,
      'taskID': taskId,
      'cardId': cardId,
      'startTime': startTime,
      'endTime': isLoading ? null : DateTime.now().millisecondsSinceEpoch,
      'isCollapsible': true,
    };
    final message = ChatMessageModel.cardMessage(cardData, id: cardId);
    if (index == -1) {
      runtime.messages.insert(0, message);
    } else {
      runtime.messages[index] = runtime.messages[index].copyWith(
        content: {'cardData': cardData, 'id': cardId},
      );
    }
  }

  void _appendToolOutput(
    ChatConversationRuntimeState runtime, {
    required String cardId,
    required String taskId,
    required String toolType,
    required String title,
    required String outputDelta,
    required Map<String, dynamic> raw,
  }) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    final existingCardData = index == -1
        ? const <String, dynamic>{}
        : runtime.messages[index].cardData ?? const <String, dynamic>{};
    final existingOutput = (existingCardData['terminalOutput'] ?? '')
        .toString();
    final output = _trimTerminalOutput(existingOutput + outputDelta);
    _upsertToolCard(
      runtime,
      cardId: cardId,
      taskId: taskId,
      toolType: toolType,
      title: title,
      status: 'running',
      summary: outputDelta.isNotEmpty ? outputDelta.trim() : title,
      progress: outputDelta,
      terminalOutput: output,
      raw: raw,
    );
  }

  void _upsertToolCard(
    ChatConversationRuntimeState runtime, {
    required String cardId,
    required String taskId,
    required String toolType,
    required String title,
    required String status,
    required String summary,
    required String progress,
    required Map<String, dynamic> raw,
    String terminalOutput = '',
  }) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    final existing = index == -1 ? null : runtime.messages[index];
    final existingCardData = existing?.cardData ?? const <String, dynamic>{};
    final cardData = <String, dynamic>{
      'type': 'agent_tool_summary',
      'taskId': taskId,
      'toolName': 'codex.$toolType',
      'displayName': title,
      'toolTitle': title,
      'cardId': cardId,
      'toolType': toolType,
      'status': status,
      'summary': summary.isNotEmpty
          ? summary
          : (existingCardData['summary'] ?? '').toString(),
      'progress': progress.isNotEmpty
          ? progress
          : (existingCardData['progress'] ?? '').toString(),
      'argsJson': _safeJson(raw),
      'resultPreviewJson': '',
      'rawResultJson': _safeJson(raw),
      'terminalOutput': terminalOutput.isNotEmpty
          ? terminalOutput
          : (existingCardData['terminalOutput'] ?? '').toString(),
      'terminalOutputDelta': progress,
      'showTerminalOutput': terminalOutput.isNotEmpty || toolType == 'terminal',
      'showRawResult': true,
    };
    final message = ChatMessageModel.cardMessage(cardData, id: cardId);
    if (index == -1) {
      runtime.messages.insert(0, message);
    } else {
      runtime.messages[index] = existing!.copyWith(
        content: {'cardData': cardData, 'id': cardId},
      );
    }
    runtime.lastAgentToolType = toolType;
  }

  void _upsertCodexRequestCard(
    ChatConversationRuntimeState runtime, {
    required String cardId,
    required Object? requestId,
    required String requestKind,
    required String title,
    required String detail,
    required Map<String, dynamic> params,
    String? questionId,
  }) {
    final cardData = <String, dynamic>{
      'type': 'codex_request',
      'requestId': requestId,
      'requestKind': requestKind,
      'title': title,
      'detail': detail,
      'questionId': questionId,
      'rawParamsJson': _safeJson(params),
      'status': 'pending',
    };
    final message = ChatMessageModel.cardMessage(cardData, id: cardId);
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    if (index == -1) {
      runtime.messages.insert(0, message);
    } else {
      runtime.messages[index] = runtime.messages[index].copyWith(
        content: {'cardData': cardData, 'id': cardId},
      );
    }
    runtime.isAiResponding = true;
  }

  void _completeItem(
    ChatConversationRuntimeState runtime,
    String taskId,
    String? itemId,
    Map<String, dynamic> params,
  ) {
    final item = _asStringMap(params['item']) ?? params;
    final itemType = _string(item['type']) ?? '';
    final text =
        _extractText(item['text']) ??
        _extractText(item['message']) ??
        _extractText(item['content']) ??
        '';
    if (itemType == 'agentMessage' && text.isNotEmpty) {
      final messageId = '$taskId-codex-agent';
      if ((runtime.currentAiMessages[messageId] ?? '').isEmpty) {
        _appendAssistantText(runtime, taskId, text);
      }
    }
    if (itemId != null) {
      for (final suffix in const ['command', 'file', 'plan']) {
        _markToolCardComplete(runtime, '$itemId-codex-$suffix');
      }
    }
  }

  void _completeTurn(ChatConversationRuntimeState runtime, String taskId) {
    runtime.isAiResponding = false;
    runtime.isExecutingTask = false;
    runtime.isCheckingExecutableTask = false;
    runtime.currentDispatchTaskId = null;
    runtime.currentAiMessages.clear();
    runtime.isDeepThinking = false;
    runtime.currentThinkingStage = ThinkingStage.complete.value;
    final thinkingCardId = '$taskId-codex-thinking';
    if (runtime.messages.any((message) => message.id == thinkingCardId)) {
      _upsertThinkingCard(
        runtime,
        taskId: taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }
  }

  void _markToolCardComplete(
    ChatConversationRuntimeState runtime,
    String cardId,
  ) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    if (index == -1) return;
    final existing = runtime.messages[index];
    final cardData = Map<String, dynamic>.from(existing.cardData ?? const {});
    cardData['status'] = 'success';
    runtime.messages[index] = existing.copyWith(
      content: {'cardData': cardData, 'id': cardId},
    );
  }

  bool _removeCodexDebugStatusCards(ChatConversationRuntimeState runtime) {
    final before = runtime.messages.length;
    runtime.messages.removeWhere((message) {
      final cardData = message.cardData;
      if (cardData == null) return false;
      final toolName = _string(cardData['toolName']);
      final title =
          _string(cardData['toolTitle']) ?? _string(cardData['displayName']);
      return toolName == 'codex.status' &&
          (title == 'codex/stderr' || title == 'codex/parseError');
    });
    return runtime.messages.length != before;
  }

  String _approvalTitle(String method, Map<String, dynamic> params) {
    if (method.contains('commandExecution')) {
      return _commandTitle(params);
    }
    if (method.contains('fileChange')) {
      return 'Codex file approval';
    }
    return 'Codex approval';
  }

  String _approvalDetail(Map<String, dynamic> params) {
    return _extractText(params['reason']) ??
        _extractText(params['description']) ??
        _extractText(params['command']) ??
        _safeJson(params);
  }

  String _commandTitle(Map<String, dynamic> params) {
    final command =
        _extractText(params['command']) ??
        _extractText(_asStringMap(params['item'])?['command']) ??
        _extractText(params['cmd']);
    if (command == null || command.trim().isEmpty) {
      return 'Codex command';
    }
    final trimmed = command.trim();
    return trimmed.length > 48 ? '${trimmed.substring(0, 48)}...' : trimmed;
  }

  _CodexQuestion _firstQuestion(Map<String, dynamic> params) {
    final questions = params['questions'];
    if (questions is List && questions.isNotEmpty) {
      final first = _asStringMap(questions.first);
      if (first != null) {
        final id =
            _string(first['id']) ?? _string(first['questionId']) ?? 'answer';
        final title =
            _string(first['label']) ??
            _string(first['title']) ??
            _string(first['question']) ??
            'Codex needs input';
        final detail =
            _string(first['description']) ??
            _string(first['placeholder']) ??
            title;
        return _CodexQuestion(id: id, title: title, detail: detail);
      }
    }
    final id =
        _string(params['questionId']) ?? _string(params['id']) ?? 'answer';
    final title =
        _string(params['question']) ??
        _string(params['title']) ??
        'Codex needs input';
    final detail = _string(params['description']) ?? title;
    return _CodexQuestion(id: id, title: title, detail: detail);
  }
}

class _CodexQuestion {
  const _CodexQuestion({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;
}

bool _isReasoningMethod(String method) {
  return method == 'item/reasoning/summaryPartAdded' ||
      method == 'item/reasoning/summaryTextDelta' ||
      method == 'item/reasoning/textDelta';
}

Map<String, dynamic>? _asStringMap(dynamic value) {
  if (value is! Map) return null;
  return value.map((key, nestedValue) => MapEntry(key.toString(), nestedValue));
}

String? _extractText(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  final map = _asStringMap(value);
  if (map != null) {
    return _firstString([
      map['text'],
      map['content'],
      map['message'],
      map['value'],
      map['delta'],
      map['summary'],
    ]);
  }
  if (value is List) {
    return value.map(_extractText).whereType<String>().join();
  }
  return value.toString();
}

String? _string(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _firstString(Iterable<dynamic> values) {
  for (final value in values) {
    final text = _extractText(value)?.trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _safeJson(dynamic value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value?.toString() ?? '';
  }
}

String _accountSummary(Map<String, dynamic> params) {
  final account = _asStringMap(params['account']) ?? params;
  final email = _string(account['email']);
  final plan = _string(account['planType']) ?? _string(account['plan_type']);
  final type = _string(account['type']);
  final parts = <String>[
    if (email != null) email,
    if (plan != null) plan,
    if (type != null && type != 'chatgpt') type,
  ];
  return parts.isEmpty ? _safeJson(params) : parts.join(' / ');
}

String _trimTerminalOutput(String value) {
  const maxChars = 64 * 1024;
  const maxLines = 600;
  var text = value;
  if (text.length > maxChars) {
    text = text.substring(text.length - maxChars);
  }
  final lines = text.split('\n');
  if (lines.length > maxLines) {
    text = lines.sublist(lines.length - maxLines).join('\n');
  }
  return text;
}
