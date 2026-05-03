import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/codex_app_server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/CodexAppServer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('startTurn forwards codex permission payload', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.startTurn(
      conversationId: 42,
      threadId: 'thread-1',
      text: 'hello',
      approvalPolicy: 'never',
      approvalsReviewer: 'user',
      sandboxPolicy: const <String, dynamic>{'type': 'dangerFullAccess'},
    );

    expect(capturedCall?.method, 'turn/start');
    final args = Map<String, dynamic>.from(
      (capturedCall?.arguments as Map).cast<String, dynamic>(),
    );
    expect(args['conversationId'], 42);
    expect(args['threadId'], 'thread-1');
    expect(args['text'], 'hello');
    expect(args['approvalPolicy'], 'never');
    expect(args['approvalsReviewer'], 'user');
    expect(args['sandboxPolicy'], const <String, dynamic>{
      'type': 'dangerFullAccess',
    });
  });
}
