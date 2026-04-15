import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/model_provider_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds request urls from root base url', () {
    expect(
      ModelProviderConfigService.buildModelsRequestUrl(
        'https://api.example.com',
      ),
      'https://api.example.com/v1/models',
    );
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(
        'https://api.example.com',
      ),
      'https://api.example.com/v1/chat/completions',
    );
  });

  test('allows trailing marker to bypass automatic request suffixes', () {
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(
        'https://api.example.com/custom/chat#',
      ),
      'https://api.example.com/custom/chat',
    );
    expect(
      ModelProviderConfigService.buildAnthropicMessagesRequestUrl(
        'https://api.example.com/custom/messages#',
      ),
      'https://api.example.com/custom/messages',
    );
  });

  test('builds request urls without duplicating v1 suffix', () {
    expect(
      ModelProviderConfigService.buildModelsRequestUrl(
        'https://api.example.com/v1',
      ),
      'https://api.example.com/v1/models',
    );
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(
        'https://api.example.com/v1',
      ),
      'https://api.example.com/v1/chat/completions',
    );
  });

  test(
    'normalizes explicit endpoint inputs before rebuilding request urls',
    () {
      expect(
        ModelProviderConfigService.buildModelsRequestUrl(
          'https://api.example.com/v1/chat/completions',
        ),
        'https://api.example.com/v1/models',
      );
      expect(
        ModelProviderConfigService.buildChatCompletionsRequestUrl(
          'https://api.example.com/v1/models',
        ),
        'https://api.example.com/v1/chat/completions',
      );
    },
  );

  test('builds anthropic request urls from base url', () {
    expect(
      ModelProviderConfigService.buildAnthropicMessagesRequestUrl(
        'https://api.anthropic.com',
      ),
      'https://api.anthropic.com/v1/messages',
    );
    expect(
      ModelProviderConfigService.buildAnthropicMessagesRequestUrl(
        'https://api.anthropic.com/v1',
      ),
      'https://api.anthropic.com/v1/messages',
    );
    expect(
      ModelProviderConfigService.buildAnthropicMessagesRequestUrl(
        'https://api.anthropic.com/v1/messages',
      ),
      'https://api.anthropic.com/v1/messages',
    );
  });

  test('returns null for invalid base url input', () {
    expect(
      ModelProviderConfigService.buildModelsRequestUrl('api.example.com'),
      isNull,
    );
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(''),
      isNull,
    );
  });
}
