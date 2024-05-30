// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

abstract class GeminiService {
  Future<String> summarize(String prompt);
  Future<String> classify(String prompt);
}

class GeminiServiceImpl implements GeminiService {
  final GenerativeModel summarizeModel;
  final GenerativeModel classifyModel;

  GeminiServiceImpl({
    required String apiKey,
    required http.Client httpClient,
  })  : summarizeModel = GenerativeModel(
          model: 'models/gemini-1.5-flash-latest',
          apiKey: apiKey,
          generationConfig: GenerationConfig(temperature: 0.2),
          httpClient: httpClient,
        ),
        classifyModel = GenerativeModel(
          // TODO(devconcarew): substitute our tuned model
          // model: 'tunedModels/autotune-sdk-triage-tuned-prompt-1l96e2n',
          model: 'models/gemini-1.5-flash-latest',
          apiKey: apiKey,
          generationConfig: GenerationConfig(temperature: 0.2),
          httpClient: httpClient,
        );

  @override
  Future<String> summarize(String prompt) {
    return _query(summarizeModel, prompt);
  }

  @override
  Future<String> classify(String prompt) {
    return _query(classifyModel, prompt);
  }

  Future<String> _query(GenerativeModel model, String prompt) async {
    final response = await model.generateContent([Content.text(prompt)]);
    return response.text!.trim();
  }
}
