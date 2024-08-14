<details open>
<summary>
<strong>Package publish validation</strong> :exclamation:
</summary>

| Package | Version | Status |
| :--- | ---: | :--- |
| package:package2 | 1.0.0 | (error) pub publish dry-run failed; add the `publish-ignore-warnings` label to ignore |
| package:package3 | 1.0.0 | (error) pub publish dry-run failed; add the `publish-ignore-warnings` label to ignore |
| package:package5 | 1.2.0 | (error) pubspec version (1.2.0) and changelog (null) don't agree |

Documentation at https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
    

This check can be disabled by tagging the PR with `skip-version-check`.
</details>

