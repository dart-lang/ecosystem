// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  final GenerativeModel _summarizeModel;
  final GenerativeModel _classifyModel;

  GeminiService({
    required String apiKey,
    required http.Client httpClient,
  })  : _summarizeModel = GenerativeModel(
          model: 'models/gemini-1.5-flash-latest',
          apiKey: apiKey,
          generationConfig: GenerationConfig(temperature: 0.2),
          httpClient: httpClient,
        ),
        _classifyModel = GenerativeModel(
          // TODO(devconcarew): substitute our tuned model
          // model: 'tunedModels/autotune-sdk-triage-tuned-prompt-1l96e2n',
          model: 'models/gemini-1.5-flash-latest',
          apiKey: apiKey,
          generationConfig: GenerationConfig(temperature: 0.2),
          httpClient: httpClient,
        );

  Future<String> summarize(String prompt) {
    return _query(_summarizeModel, prompt);
  }

  Future<List<String>> classify(String prompt) async {
    final result = await _query(_classifyModel, prompt);
    final labels = result.split(',').map((l) => l.trim()).toList();
    return labels;
  }

  Future<String> _query(GenerativeModel model, String prompt) async {
    final response = await model.generateContent([Content.text(prompt)]);
    return response.text!.trim();
  }
}
