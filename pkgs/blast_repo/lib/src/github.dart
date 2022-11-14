import 'dart:io';

import 'package:github/github.dart';

GitHub createGitHubClient() => GitHub(
      auth: Authentication.withToken(Platform.environment['GITHUB_TOKEN']),
    );
