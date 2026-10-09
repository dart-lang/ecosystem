<details>
<summary>
<strong>Package Roll</strong> :warning:
</summary>

| Package | Version | Status |
| :--- | ---: | :--- |
| package:package1 | 1.0.0 | Missing roll confirmation |
| package:package2 | 1.0.0 | Missing roll confirmation |
| package:package3 | 1.0.0 | Missing roll confirmation |

Packages developed under `dart-lang` should be [rolled to google3 and the Dart SDK](https://github.com/dart-lang/sdk/blob/main/docs/External-Package-Maintenance.md#publishing-a-package) before publishing. Add `CONFIRMED_PACKAGE_ROLL=true` or `ROLLED_TO=<sha>` to the PR description once rolled.


This check can be disabled by tagging the PR with `skip-roll-check`.
</details>

