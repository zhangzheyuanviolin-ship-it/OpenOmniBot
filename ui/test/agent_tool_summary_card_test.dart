import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/agent_tool_summary_card.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/terminal_output_utils.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/services/assists_core_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TerminalOutputUtils builds readable output from result json', () {
    final output = TerminalOutputUtils.buildDisplayOutput(
      terminalOutput: '',
      rawResultJson: jsonEncode({
        'liveFallbackReason': '共享存储未就绪',
        'stdout': 'hello',
        'stderr': 'warning',
      }),
      resultPreviewJson: '',
    );

    expect(output, contains('hello'));
    expect(output, contains('[stderr]'));
    expect(output, contains('warning'));
  });

  test('AnsiTextSpanBuilder applies color and bold to sgr spans', () {
    const baseStyle = TextStyle(fontSize: 12, color: Colors.white);
    final span = AnsiTextSpanBuilder.build(
      '\u001B[31;1merror\u001B[0m',
      baseStyle,
    );

    final children = span.children!;
    final styledChild = children.first as TextSpan;
    expect(styledChild.text, 'error');
    expect(styledChild.style?.fontWeight, FontWeight.w700);
    expect(styledChild.style?.color, const Color(0xFFE06C75));
  });

  testWidgets('tool card prefers toolTitle when rendering compact chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentToolSummaryCard(
            cardData: {
              'status': 'success',
              'displayName': '终端执行',
              'toolTitle': '检查仓库状态',
              'toolType': 'terminal',
              'summary': '终端命令执行成功',
              'argsJson': jsonEncode({
                'command': 'ls -la',
                'executionMode': 'termux',
                'timeoutSeconds': 60,
              }),
            },
          ),
        ),
      ),
    );

    expect(find.text('检查仓库状态'), findsOneWidget);
    expect(find.text('终端执行'), findsNothing);
  });

  testWidgets(
    'interrupted status shows stopped state without loading spinner',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentToolSummaryCard(
              cardData: {
                'status': 'interrupted',
                'displayName': 'tool',
                'toolType': 'builtin',
                'summary': 'stopped',
              },
            ),
          ),
        ),
      );

      expect(find.text('\u4E2D\u65AD'), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('timeout status shows dedicated timeout badge and icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentToolSummaryCard(
            cardData: {
              'status': 'timeout',
              'displayName': '终端执行',
              'toolType': 'terminal',
              'summary': '终端命令等待超时',
            },
          ),
        ),
      ),
    );

    expect(find.text('超时'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tool card falls back to args tool_title when field missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentToolSummaryCard(
            cardData: {
              'status': 'running',
              'displayName': '读取文件',
              'toolType': 'workspace',
              'summary': '已读取文件',
              'argsJson': jsonEncode({
                'tool_title': '查看配置',
                'path': 'README.md',
              }),
            },
          ),
        ),
      ),
    );

    expect(find.text('查看配置'), findsOneWidget);
    expect(find.text('工作区'), findsOneWidget);
  });

  testWidgets('tool card title follows appearance text color', (tester) async {
    const customTextColor = Color(0xFFEEE6D7);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentToolSummaryCard(
            cardData: {
              'status': 'success',
              'toolTitle': '同步索引',
              'toolType': 'workspace',
              'summary': '已完成同步',
            },
            visualProfile: const AppBackgroundVisualProfile(
              sampledImageLuminance: 0.12,
              effectiveLuminance: 0.24,
              textTone: AppBackgroundTextTone.light,
              customPrimaryTextColor: customTextColor,
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('同步索引'));
    expect(title.style?.color, customTextColor);
    expect(title.style?.fontSize, 12);
  });

  test(
    'utg run-log import result keeps raw replay semantics for direct replay',
    () {
      final result = UtgRunLogImportResult.fromMap(<String, dynamic>{
        'success': true,
        'run_id': 'run_123',
        'created_path_id': 'raw_replay_run123',
        'paths_created': 1,
        'nodes_created': 2,
        'nodes_updated': 1,
        'functions_created': 3,
        'warnings': <String>[],
        'run_log_path': '/tmp/agent_runs.jsonl',
        'path_kind': 'raw_replay',
        'asset_state': 'temporary',
      });

      expect(result.success, isTrue);
      expect(result.createdPathId, 'raw_replay_run123');
      expect(result.pathKind, 'raw_replay');
      expect(result.assetState, 'temporary');
      expect(result.functionsCreated, 3);
    },
  );

  test(
    'utg distill result preserves ready-asset metadata and raw response',
    () {
      final result = UtgPathMutationResult.fromMap(<String, dynamic>{
        'success': true,
        'path_id': 'raw_replay_run123',
        'created_path_id': 'ready_path_wifi',
        'path_kind': 'distilled_asset',
        'asset_state': 'ready',
        'derived_from_raw_path_id': 'raw_replay_run123',
        'functions_created': 2,
        'function_names': <String>['open_settings', 'search_wifi'],
      });

      expect(result.success, isTrue);
      expect(result.createdPathId, 'ready_path_wifi');
      expect(result.pathKind, 'distilled_asset');
      expect(result.assetState, 'ready');
      expect(result.derivedFromRawPathId, 'raw_replay_run123');
      expect(result.rawJson['functions_created'], 2);
      expect(result.rawJson['function_names'], <String>[
        'open_settings',
        'search_wifi',
      ]);
    },
  );

  test('utg path summary parses raw replay and ready asset partitions', () {
    final snapshot = UtgPathsSnapshot.fromMap(<String, dynamic>{
      'success': true,
      'count': 2,
      'provider': 'omniflow_utg',
      'paths': <Map<String, dynamic>>[
        <String, dynamic>{
          'path_id': 'raw_replay_run123',
          'description': 'raw replay run123',
          'step_count': 2,
          'path_kind': 'raw_replay',
          'asset_state': 'temporary',
          'derived_from_raw_path_id': '',
          'parameter_names': <String>[],
        },
        <String, dynamic>{
          'path_id': 'ready_path_wifi',
          'description': r'打开设置并搜索${query}',
          'step_count': 1,
          'path_kind': 'distilled_asset',
          'asset_state': 'ready',
          'derived_from_raw_path_id': 'raw_replay_run123',
          'parameter_names': <String>['query'],
          'parameter_examples': <String, String>{'query': 'Wi-Fi'},
        },
      ],
    });

    expect(snapshot.success, isTrue);
    expect(snapshot.paths, hasLength(2));
    expect(snapshot.paths.first.pathKind, 'raw_replay');
    expect(snapshot.paths.first.assetState, 'temporary');
    expect(snapshot.paths.last.pathKind, 'distilled_asset');
    expect(snapshot.paths.last.assetState, 'ready');
    expect(snapshot.paths.last.derivedFromRawPathId, 'raw_replay_run123');
    expect(snapshot.paths.last.parameterNames, <String>['query']);
    expect(snapshot.paths.last.parameterExamples['query'], 'Wi-Fi');
  });

  testWidgets(
    'run log popup keeps memory and replay actions when only ingest payload exists',
    (tester) async {
      const channel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getVlmTaskRunLog') {
          return <String, dynamic>{
            'success': true,
            'task_id': 'task_ingest_only',
            'run_log': <String, dynamic>{
              'goal': '打开设置',
              'success': true,
              'done_reason': 'completed',
              'steps': <Map<String, dynamic>>[
                <String, dynamic>{
                  'step_index': 0,
                  'plan': <String, dynamic>{'tool_name': 'run_action'},
                },
              ],
              'final_observation': <String, dynamic>{
                'package_name': 'com.demo',
              },
              'extra': <String, dynamic>{'compile_kind': 'miss'},
            },
            'ingest_payload': <String, dynamic>{
              'goal': '打开设置',
              'steps': <Map<String, dynamic>>[
                <String, dynamic>{
                  'observation': <String, dynamic>{
                    'xml': '<hierarchy />',
                    'package_name': 'com.demo',
                  },
                  'tool_call': <String, dynamic>{
                    'name': 'click',
                    'params': <String, dynamic>{'x': 1, 'y': 2},
                  },
                },
              ],
            },
          };
        }
        return null;
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentToolSummaryCard(
              cardData: <String, dynamic>{
                'status': 'success',
                'toolName': 'vlm_task',
                'toolType': 'builtin',
                'toolTitle': '执行设置任务',
                'toolTaskId': 'task_ingest_only',
                'compileStatus': 'miss',
                'executionRoute': 'vlm',
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();

      expect(find.text('记忆'), findsOneWidget);
      expect(find.text('重放'), findsOneWidget);

      final rememberButton = tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.text('记忆'),
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            )
            .first,
      );
      final replayButton = tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.text('重放'),
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            )
            .first,
      );
      expect(rememberButton.onPressed, isNotNull);
      expect(replayButton.onPressed, isNotNull);
    },
  );

  testWidgets('tool card shows OmniFlow route chip for compile hit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentToolSummaryCard(
            cardData: <String, dynamic>{
              'status': 'success',
              'toolTitle': '执行轨迹',
              'toolType': 'builtin',
              'compileStatus': 'hit',
              'executionRoute': 'utg',
            },
          ),
        ),
      ),
    );

    expect(find.text('OmniFlow'), findsOneWidget);
  });
}
