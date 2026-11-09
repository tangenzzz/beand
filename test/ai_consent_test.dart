import 'dart:typed_data';

import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_prompt.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_service.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Permission to send personal data to an AI provider: tied to the server that
// receives it, kept on this device, and enforced in the service as well as in
// the dialog.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AiSettings> claude() async {
    final settings = AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true);
    await settings.setProvider(AiProvider.claude);
    await settings.setKey(AiProvider.claude, 'sk-ant');
    return settings;
  }

  test(
    'without consent nothing is sent, not even the shop page fetch',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      final service = AiService(await claude(), httpClient: client);

      await expectLater(
        service.extractBean(
          image: AiImage(bytes: Uint8List(1), mediaType: 'image/jpeg'),
        ),
        throwsA(isA<AiFailure>()),
      );
      await expectLater(
        service.extractBean(url: Uri.parse('https://shop.example/kenya')),
        throwsA(isA<AiFailure>()),
      );
      expect(requests, 0);
    },
  );

  test('the recipient is named: the vendor, or the host for Custom', () async {
    final settings = await claude();
    expect(settings.recipientName, 'Anthropic');
    expect(settings.recipientAddress, 'api.anthropic.com');

    await settings.setProvider(AiProvider.compatible);
    await settings.setBaseUrl('http://192.168.1.5:11434/v1');
    expect(settings.recipientName, '192.168.1.5:11434');
  });

  test('consent is per recipient: another Custom server asks again', () async {
    final settings = await claude();
    await settings.setProvider(AiProvider.compatible);
    await settings.setBaseUrl('https://openrouter.ai/api/v1');
    await settings.grantConsent();
    expect(settings.hasConsent, isTrue);

    await settings.setBaseUrl('https://api.groq.com/openai/v1');
    expect(settings.hasConsent, isFalse);

    await settings.setProvider(AiProvider.claude);
    expect(settings.hasConsent, isFalse);
  });

  test('consent survives a restart', () async {
    final store = InMemoryAiKeyStore();
    final settings = AiSettings(keyStore: store, enabled: true);
    await settings.setProvider(AiProvider.claude);
    await settings.grantConsent();

    final reloaded = await AiSettings.load(keyStore: store);
    expect(reloaded.hasConsent, isTrue);
  });

  test('switching AI off takes the permission back', () async {
    final store = InMemoryAiKeyStore();
    final settings = AiSettings(keyStore: store, enabled: true);
    await settings.setProvider(AiProvider.claude);
    await settings.grantConsent();

    await settings.setEnabled(false);
    await settings.setEnabled(true);
    expect(settings.hasConsent, isFalse);

    final reloaded = await AiSettings.load(keyStore: store);
    expect(reloaded.hasConsent, isFalse);
  });

  test('an empty Custom address can never be consented to', () async {
    final settings = await claude();
    await settings.setProvider(AiProvider.compatible);
    await settings.grantConsent();
    expect(settings.hasConsent, isFalse);
  });
}
