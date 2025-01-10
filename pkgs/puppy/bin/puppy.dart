import 'package:args/command_runner.dart';
import 'package:puppy/src/map_command.dart';

Future<void> main(List<String> args) async {
  var runner = CommandRunner<void>(
      'dgit', 'A dart implementation of distributed version control.')
    ..addCommand(MapCommand());

  await runner.run(args);
}
