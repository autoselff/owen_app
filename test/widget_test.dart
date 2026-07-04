import 'package:flutter_test/flutter_test.dart';
import 'package:owen/data/models/provider_profile.dart';

void main() {
  test('ProviderProfile survives a DB round-trip', () {
    const profile = ProviderProfile(
      id: 'abc',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: ['deepseek-chat', 'deepseek-reasoner'],
      defaultModel: 'deepseek-chat',
    );

    final restored = ProviderProfile.fromDbMap(profile.toDbMap());

    expect(restored.name, profile.name);
    expect(restored.baseUrl, profile.baseUrl);
    expect(restored.models, profile.models);
    expect(restored.defaultModel, profile.defaultModel);
  });
}
