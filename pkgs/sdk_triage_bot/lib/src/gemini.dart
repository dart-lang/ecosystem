// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  // Possible values for models: gemini-1.5-pro-latest, gemini-1.5-flash-latest,
  // gemini-1.0-pro-latest, gemini-1.5-flash-exp-0827.
  static const String classificationModel = 'models/gemini-1.5-flash-latest';
  static const String summarizationModel = 'models/gemini-1.5-flash-latest';

  final GenerativeModel _summarizeModel;
  final GenerativeModel _classifyModel;

  GeminiService({
    required String apiKey,
    required http.Client httpClient,
  })  : _summarizeModel = GenerativeModel(
          model: summarizationModel,
          apiKey: apiKey,
          generationConfig: GenerationConfig(temperature: 0.2),
          httpClient: httpClient,
        ),
        _classifyModel = GenerativeModel(
          // TODO(devoncarew): substitute our tuned model
          // model: 'tunedModels/autotune-sdk-triage-tuned-prompt-1l96e2n',
          model: classificationModel,
          apiKey: apiKey,
          generationConfig: GenerationConfig(temperature: 0.2),
          httpClient: httpClient,
        );

  /// Call the summarize model with the given prompt.
  ///
  /// On failures, this will throw a [GenerativeAIException].
  Future<String> summarize(String prompt) {
    return _query(_summarizeModel, prompt);
  }

  /// Call the classify model with the given prompt.
  ///
  /// On failures, this will throw a [GenerativeAIException].
  Future<List<String>> classify(String prompt) async {
    final result = await _query(_classifyModel, prompt);
    final labels = result.split(',').map((l) => l.trim()).toList()..sort();
    return labels;
  }

  Future<String> _query(GenerativeModel model, String prompt) async {
    final response = await model.generateContent([Content.text(prompt)]);
    return (response.text ?? '').trim();
  }
}
