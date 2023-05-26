A tool to bulk validate and fix GitHub repos.

## blast_repo

```
Usage: blast_repo <options> [org/repo]

    --keep-temp                 Don't delete the temporary repo clone.
    --tweaks=<tweak1,tweak2>    Optionally list the specific tweaks to run (defaults to all applicable tweaks).
                                [auto-publish, dependabot, github-actions, monorepo, no-response]
    --reviewer=<github-id>      Specify the GitHub handle for the desired reviewer.
-h, --help                      Prints out usage and exits.

available tweaks:
  auto-publish: configure a github action to enable package auto-publishing
  dependabot: ensure ".github/dependabot.yml" exists and has the correct content
  github-actions: ensure GitHub actions use the latest versions and are keyed by SHA
  monorepo: regenerate the latest configuration files for package:mono_repo
  no-response: configure a 'no response' bot to handle needs-info labels
```
