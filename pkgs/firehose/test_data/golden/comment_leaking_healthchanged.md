<details open>
<summary>
<strong>API leaks</strong> :warning:
</summary>

The following packages contain symbols visible in the public API, but not exported by the library. Export these symbols or remove them from your publicly visible API.

| Package | Leaked API symbols |
| :--- | :--- |
|package5|NonExported<br>NonExported2<br>TransitiveNonExported|


This check can be disabled by tagging the PR with `skip-leaking-check`.
</details>

