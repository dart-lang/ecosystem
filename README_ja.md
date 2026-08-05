<!-- hy-mt2-i18n:start -->
[English](./README.md) | [中文](./README_zh-CN.md) | **日本語** | [Español](./README_es.md)
<!-- hy-mt2-i18n:end -->

## 概要

このリポジトリには、Dartエコシステム向けの一般的なツールやパッケージが収められています。

## パッケージ一覧

| Package | Description | Version |
| --- | --- | --- |
| [blast_repo](pkgs/blast_repo/) | GitHubリポジトリを一括で検証し修正するためのツールです。 |  |
| [canary](pkgs/canary/) | エコシステム全体に対してパッケージのアップグレードをテストするためのツールです。 |  |
| [corpus](pkgs/corpus/) | パッケージのAPI利用状況を算出するためのツールです。 |  |
| [dart_flutter_team_lints](pkgs/dart_flutter_team_lints/) | DartおよびFlutterチームで使用されている分析ルールセットです。 | [![pub package](https://img.shields.io/pub/v/dart_flutter_team_lints.svg)](https://pub.dev/packages/dart_flutter_team_lints) |
| [firehose](pkgs/firehose/) | GitHub ActionsからPubパッケージの自動公開を実現するツールです。 | [![pub package](https://img.shields.io/pub/v/firehose.svg)](https://pub.dev/packages/firehose) |
| [repo_manage](pkgs/repo_manage/) | 様々な問題やリポジトリ、PRに関するクエリを処理するツールです。 |  |
| [sdk_triage_bot](pkgs/sdk_triage_bot/) | dart-lang/sdkの問題を自動的に分類するためのツールです。 |  |
| [trebuchet](pkgs/trebuchet/) | 既存のパッケージをモノレポジトリに移行させるためのツールです。 |  |

## Dartのモノレポ

こちらがDartチームの主要なリポジトリの概要です：

| メインリポジトリ | 説明 |
| --- | --- |
| [sdk](https://github.com/dart-lang/sdk) | VM、JSおよびWasmコンパイラ、分析ツール、コアライブラリなどを含むDart SDKです。 |

| SLO mono-repos | Description |
| --- | --- |
| [core](https://github.com/dart-lang/core) | こちらのリポジトリにはDartのコアパッケージが収められています。 |
| [tools](https://github.com/dart-lang/tools) | こちらのリポジトリにはDart関連のツール系パッケージが収められています。 |
| [labs](https://github.com/dart-lang/labs) | こちらのリポジトリにはDartの「labs」パッケージが収められています。 |

| Topic mono-repos | Description |
| --- | --- |
| [build](https://github.com/dart-lang/build) | Dartで記述されたDart用のビルドシステム |
| [ecosystem](https://github.com/dart-lang/ecosystem) | 一般的なDartエコシステム向けのツールやパッケージが収められているリポジトリです。 |
| [http](https://github.com/dart-lang/http) | DartでHTTPリクエストを行うためのコンポーザブルなAPI |
| [i18n](https://github.com/dart-lang/i18n) | Dartのi18nおよびl10nパッケージ用の汎用モノレポ |
| [leak_tracker](https://github.com/dart-lang/leak_tracker) | DartおよびFlutterアプリケーションのメモリリークを追跡するためのフレームワーク |
| [macros](https://github.com/dart-lang/macros) | マクロ開発用のDartモノレポ |
| [native](https://github.com/dart-lang/native) | FFIやネイティブアセットのバンデリングに関連するDartパッケージ |
| [shelf](https://github.com/dart-lang/shelf) | Dart用のウェブサーバーミドルウェア |
| [test](https://github.com/dart-lang/test) | Dartで単体テストを記述するためのライブラリ |
| [webdev](https://github.com/dart-lang/webdev) | Dartのウェブ開発用CLI |

## パブリッシング自動化

パブリッシング自動化およびリリースプロセスに関する詳細は、
https://github.com/dart-lang/ecosystem/wiki/Publishing-automation をご覧ください。

貢献に関する詳細な情報については、当方の
[contributing](CONTRIBUTING.md) ページをご覧ください。
