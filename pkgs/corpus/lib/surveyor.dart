// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as path;

const bool _silent = true;

class Surveyor {
  final SurveyorVisitor visitor;
  final List<String> sourcePaths;
  final List<String> excludedPaths;

  Surveyor.fromDirs({
    required this.visitor,
    required List<io.Directory> directories,
    this.excludedPaths = const [],
  }) : sourcePaths = directories
            .map((directory) => path.normalize(directory.absolute.path))
            .toList() {
    assert(sourcePaths.isNotEmpty);
  }

  Future<void> analyze() async {
    for (var directory in sourcePaths) {
      await _analyzeDirectory(directory);
    }
  }

  Future<void> _analyzeDirectory(String directory) async {
    var analysisContextCollection = AnalysisContextCollection(
      includedPaths: [directory],
      excludedPaths: excludedPaths,
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    for (var analysisContext in analysisContextCollection.contexts) {
      var dir = analysisContext.contextRoot.root.path;
      var surveyorContext = SurveyorContext(analysisContext);

      visitor.preAnalysis(surveyorContext, subDir: dir != directory);

      for (var filePath in analysisContext.contextRoot.analyzedFiles()) {
        if (!_isDartFileName(filePath)) continue;

        surveyorContext._updateCurrentFilePath(filePath);

        try {
          var resolvedUnitResult = await analysisContext.currentSession
              .getResolvedUnit(filePath) as ResolvedUnitResult;
          resolvedUnitResult.unit.accept(visitor);
        } catch (e) {
          if (!_silent) {
            print('Exception caught analyzing: $filePath\n$e');
          }
        }

        surveyorContext._updateCurrentFilePath(null);
      }

      visitor.postAnalysis(surveyorContext);
    }
  }
}

abstract class SurveyorVisitor implements AstVisitor {
  void preAnalysis(SurveyorContext context, {required bool subDir});
  void postAnalysis(SurveyorContext context);
}

class SurveyorContext {
  final AnalysisContext analysisContext;
  String? _currentFilePath;

  SurveyorContext(this.analysisContext);

  String get currentFilePath => _currentFilePath!;

  void _updateCurrentFilePath(String? filePath) {
    _currentFilePath = filePath;
  }
}

bool _isDartFileName(String filePath) => filePath.endsWith('.dart');
