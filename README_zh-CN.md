<!-- hy-mt2-i18n:start -->
[English](./README.md) | **中文** | [日本語](./README_ja.md) | [Español](./README_es.md)
<!-- hy-mt2-i18n:end -->

## 概览

该仓库收录了各类 Dart 生态系统工具与包。

## 包列表

| 包名 | 描述 | 版本 |
| --- | --- | --- |
| [blast_repo](pkgs/blast_repo/) | 用于批量验证并修复 GitHub 仓库的工具。 |  |
| [canary](pkgs/canary/) | 用于测试生态系统中包升级的工具。 |  |
| [corpus](pkgs/corpus/) | 用于计算某个包的 API 使用量的工具。 |  |
| [dart_flutter_team_lints](pkgs/dart_flutter_team_lints/) | Dart 和 Flutter 团队使用的分析规则集。 | [![pub package](https://img.shields.io/pub/v/dart_flutter_team_lints.svg)](https://pub.dev/packages/dart_flutter_team_lints) |
| [firehose](pkgs/firehose/) | 用于通过 GitHub Actions 自动发布 Pub 包的工具。 | [![pub package](https://img.shields.io/pub/v/firehose.svg)](https://pub.dev/packages/firehose) |
| [repo_manage](pkgs/repo_manage/) | 各种问题、仓库及 PR 查询工具。 |  |
| [sdk_triage_bot](pkgs/sdk_triage_bot/) | 用于处理 dart-lang/sdk 相关问题的自动化分拣工具。 |  |
| [trebuchet](pkgs/trebuchet/) | 用于将现有包迁移至单仓库中的工具。 |  |

## Dart 单体仓库

以下是 Dart 团队主要仓库的概览：

| 主要仓库 | 描述 |
| --- | --- |
| [sdk](https://github.com/dart-lang/sdk) | Dart SDK，包含虚拟机、JS和Wasm编译器、分析工具、核心库等。 |

| SLO 单体仓库 | 描述 |
| --- | --- |
| [core](https://github.com/dart-lang/core) | 该仓库存放着 Dart 的核心包。 |
| [tools](https://github.com/dart-lang/tools) | 该仓库存放着与工具相关的 Dart 包。 |
| [labs](https://github.com/dart-lang/labs) | 该仓库存放着 Dart 的“实验性”包。 |

| 主题相关 mono-repos | 描述 |
| --- | --- |
| [build](https://github.com/dart-lang/build) | 用 Dart 编写的 Dart 构建系统 |
| [ecosystem](https://github.com/dart-lang/ecosystem) | 该仓库存放各类 Dart 生态系统工具与包 |
| [http](https://github.com/dart-lang/http) | 用于在 Dart 中发送 HTTP 请求的可组合 API |
| [i18n](https://github.com/dart-lang/i18n) | 用于 Dart 国际化及本地化包的通用 mono-repo |
| [leak_tracker](https://github.com/dart-lang/leak_tracker) | 用于 Dart 和 Flutter 应用程序内存泄漏检测的框架 |
| [macros](https://github.com/dart-lang/macros) | 用于宏开发的 Dart mono-repo |
| [native](https://github.com/dart-lang/native) | 与 FFI 及原生资源打包相关的 Dart 包 |
| [shelf](https://github.com/dart-lang/shelf) | 用于 Dart 的 Web 服务器中间件 |
| [test](https://github.com/dart-lang/test) | 用于编写 Dart 单元测试的库 |
| [webdev](https://github.com/dart-lang/webdev) | 用于 Dart Web 开发的 CLI 工具 |

## 发布自动化

如需了解我们的发布自动化及版本发布流程，请访问
https://github.com/dart-lang/ecosystem/wiki/Publishing-automation。

如需了解有关贡献的更多信息，请查看我们的
[贡献指南](CONTRIBUTING.md) 页面。
