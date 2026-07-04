import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';

class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One event from a streamed completion: either a text delta or, at the end,
/// the token usage (when the provider reports it).
class ChatChunk {
  const ChatChunk.text(this.text) : usage = null;
  const ChatChunk.usage(this.usage) : text = null;

  final String? text;
  final TokenUsage? usage;
}

/// Minimal client for the OpenAI `/chat/completions` API with streaming.
///
/// Deliberately provider-agnostic: it only speaks the OpenAI wire format, so
/// the same code drives OpenAI, DeepSeek, Groq, OpenRouter, Ollama, LM Studio
/// and anything else that exposes a compatible endpoint.
class OpenAiCompatibleClient {
  OpenAiCompatibleClient([http.Client? client])
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Streams assistant text deltas as they arrive, followed by a final usage
  /// chunk when the provider reports token counts. Completes when the server
  /// sends `[DONE]`. Throws [LlmException] on a non-200 response.
  Stream<ChatChunk> streamChat({
    required String baseUrl,
    required String? apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double? temperature,
  }) async* {
    final uri = Uri.parse('${_normalize(baseUrl)}/chat/completions');
    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    if (apiKey != null && apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }
    request.body = jsonEncode({
      'model': model,
      'messages': messages,
      'stream': true,
      // Ask compatible providers (OpenAI, DeepSeek, …) to include token usage
      // in the final streamed chunk. Providers that ignore it simply won't.
      'stream_options': {'include_usage': true},
      'temperature': ?temperature,
    });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on Object catch (e) {
      throw LlmException('Could not connect: $e');
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw LlmException('HTTP ${response.statusCode}: ${_extractError(body)}');
    }

    final lines =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;

      Map<String, Object?> json;
      try {
        json = jsonDecode(data) as Map<String, Object?>;
      } catch (_) {
        continue; // keep-alive or partial line, ignore
      }

      final usage = json['usage'];
      if (usage is Map<String, Object?>) {
        yield ChatChunk.usage(TokenUsage.fromJson(usage));
      }

      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'] as Map?;
      final content = delta?['content'];
      if (content is String && content.isNotEmpty) {
        yield ChatChunk.text(content);
      }
    }
  }

  String _normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Pulls the human-readable message out of a JSON error body when possible.
  String _extractError(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['error'] is Map) {
        final msg = (json['error'] as Map)['message'];
        if (msg is String) return msg;
      }
    } catch (_) {}
    return body.length > 300 ? body.substring(0, 300) : body;
  }

  void close() => _client.close();
}
