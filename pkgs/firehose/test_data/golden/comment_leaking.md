<details>
<summary>
<strong>API leaks</strong> :warning:
</summary>

The following packages contain symbols visible in the public API, but not exported by the library. Export these symbols or remove them from your publicly visible API.

| Package | Leaked API symbol | Leaking sources |
| :--- | :--- | :--- |
|package5|NonExported|package5_base.dart::Awesome::myClass|
|package5|NonExported2|package5_base.dart::Awesome::myClass2|
|package5|TransitiveNonExported|package5_base.dart::NonExported2::myClass|


This check can be disabled by tagging the PR with `skip-leaking-check`.
</details>

