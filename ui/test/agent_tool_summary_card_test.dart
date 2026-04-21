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
      expect(result.createdFunctionId, 'raw_replay_run123');
      expect(result.assetKind, 'raw_replay');
      expect(result.assetState, 'temporary');
      expect(result.functionsCreated, 3);
    },
  );

  test(
    'utg distill result preserves ready-asset metadata and raw response',
    () {
      final result = UtgFunctionMutationResult.fromMap(<String, dynamic>{
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
      expect(result.createdFunctionId, 'ready_path_wifi');
      expect(result.assetKind, 'distilled_asset');
      expect(result.assetState, 'ready');
      expect(result.derivedFromRawFunctionId, 'raw_replay_run123');
      expect(result.rawJson['functions_created'], 2);
      expect(result.rawJson['function_names'], <String>[
        'open_settings',
        'search_wifi',
      ]);
    },
  );

  test('utg path summary parses raw replay and ready asset partitions', () {
    final snapshot = UtgFunctionsSnapshot.fromMap(<String, dynamic>{
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
    expect(snapshot.functions, hasLength(2));
    expect(snapshot.functions.first.assetKind, 'raw_replay');
    expect(snapshot.functions.first.assetState, 'temporary');
    expect(snapshot.functions.last.assetKind, 'distilled_asset');
    expect(snapshot.functions.last.assetState, 'ready');
    expect(
      snapshot.functions.last.derivedFromRawFunctionId,
      'raw_replay_run123',
    );
    expect(snapshot.functions.last.parameterNames, <String>['query']);
    expect(snapshot.functions.last.parameterExamples['query'], 'Wi-Fi');
  });

  testWidgets(
    'run log popup keeps memory and replay actions when provider run_id exists',
    (tester) async {
      const channel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getVlmTaskRunLog') {
          return <String, dynamic>{
            'success': true,
            'task_id': 'task_ingest_only',
            'run_id': 'run_ingest_only',
          };
        }
        if (call.method == 'requestUtgJson') {
          return <String, dynamic>{
            'success': true,
            'run_id': 'run_ingest_only',
            'run_log': <String, dynamic>{
              'goal': '打开设置',
              'success': true,
              'done_reason': 'completed',
            },
            'view': <String, dynamic>{
              'success': true,
              'goal': '打开设置',
              'step_count': 1,
              'compile_label': 'compile miss',
              'tool_label': 'click',
              'summary': '已打开设置',
              'final_package': 'com.demo',
              'steps': <Map<String, dynamic>>[
                <String, dynamic>{
                  'title': '点击设置',
                  'selected_by': 'VLM',
                  'why': 'provider view',
                  'actions': <String>['click(1, 2)'],
                  'result': '成功',
                  'summary': '已完成',
                  'success': true,
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

  testWidgets('vlm task success card tap also opens run log popup', (
    tester,
  ) async {
    const channel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getVlmTaskRunLog') {
        return <String, dynamic>{
          'success': true,
          'task_id': 'task_card_tap',
          'run_id': 'run_card_tap',
        };
      }
      if (call.method == 'requestUtgJson') {
        return <String, dynamic>{
          'success': true,
          'run_id': 'run_card_tap',
          'run_log': <String, dynamic>{
            'goal': '打开设置',
            'success': true,
            'done_reason': 'completed',
          },
          'view': <String, dynamic>{
            'success': true,
            'goal': '打开设置',
            'step_count': 1,
            'compile_label': 'compile miss',
            'tool_label': '打开应用 com.android.settings',
            'summary': '已打开设置',
            'final_package': 'com.android.settings',
            'steps': <Map<String, dynamic>>[
              <String, dynamic>{'title': '打开设置', 'success': true},
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
              'toolTitle': '打开设置应用',
              'toolTaskId': 'task_card_tap',
              'compileStatus': 'miss',
              'executionRoute': 'vlm',
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AgentToolSummaryCard));
    await tester.pumpAndSettle();

    expect(find.text('Run Log 详情'), findsOneWidget);
    expect(find.text('记忆'), findsOneWidget);
    expect(find.text('重放'), findsOneWidget);
  });

  testWidgets(
    'vlm task view prefers taskId from result json over agent task id',
    (tester) async {
      const channel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var requestedTaskId = '';
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getVlmTaskRunLog') {
          requestedTaskId = ((call.arguments as Map?)?['taskId'] ?? '')
              .toString();
          if (requestedTaskId == 'vlm_task_real') {
            return <String, dynamic>{
              'success': true,
              'task_id': 'vlm_task_real',
              'run_id': 'run_real',
            };
          }
          return <String, dynamic>{
            'success': false,
            'task_id': requestedTaskId,
            'error_message': '未找到对应的 run_log',
          };
        }
        if (call.method == 'requestUtgJson') {
          return <String, dynamic>{
            'success': true,
            'run_id': 'run_real',
            'run_log': <String, dynamic>{
              'goal': '打开蓝牙设置',
              'success': true,
              'done_reason': 'completed',
            },
            'view': <String, dynamic>{
              'success': true,
              'goal': '打开蓝牙设置',
              'step_count': 1,
              'compile_label': 'compile miss',
              'tool_label': '打开应用 com.android.settings',
              'summary': '已打开蓝牙设置',
              'final_package': 'com.android.settings',
              'steps': <Map<String, dynamic>>[
                <String, dynamic>{
                  'title': '打开设置',
                  'actions': <String>['open_app(com.android.settings)'],
                  'success': true,
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
                'toolTitle': '打开蓝牙设置',
                'toolTaskId': 'agent_task_outer',
                'resultPreviewJson': jsonEncode(<String, dynamic>{
                  'taskId': 'vlm_task_real',
                }),
                'compileStatus': 'miss',
                'executionRoute': 'vlm',
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();

      expect(requestedTaskId, 'vlm_task_real');
      expect(find.text('Run Log 详情'), findsOneWidget);
      expect(find.text('记忆'), findsOneWidget);
      expect(find.text('重放'), findsOneWidget);
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
