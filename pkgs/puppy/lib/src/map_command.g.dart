// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_command.dart';

// **************************************************************************
// CliGenerator
// **************************************************************************

MapArgs _$parseMapArgsResult(ArgResults result) => MapArgs(
      deep: result['deep'] as bool,
      rest: result.rest,
    );

ArgParser _$populateMapArgsParser(ArgParser parser) => parser
  ..addFlag(
    'deep',
    abbr: 'd',
    help: 'Keep looking for "nested" pubspec files.',
  );

final _$parserForMapArgs = _$populateMapArgsParser(ArgParser());

MapArgs parseMapArgs(List<String> args) {
  final result = _$parserForMapArgs.parse(args);
  return _$parseMapArgsResult(result);
}

abstract class _$MapArgsCommand<T> extends Command<T> {
  _$MapArgsCommand() {
    _$populateMapArgsParser(argParser);
  }

  late final _options = _$parseMapArgsResult(argResults!);
}
