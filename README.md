# MausIPA

一台 iPhone 上的自签 AI 助手：**把每个 AI 当成一个联系人**，水墨风格，渠道自带，局域网可当 `/v1` 网关用。

不用电脑、不用 VPS，也不需要 Apple 开发者账号 —— GitHub Actions 直接编译出未签名 `.ipa`，用 TrollStore / AltStore / SideStore / Sideloadly 自签安装。

---

## 它是什么

**对话（联系人）**
- 每个联系人是一张卡片：名字、印章头像、绑定的渠道与模型、人格提示词、长期记忆，以及独立的对话历史。
- 对话只存在这台手机上；API Key 与令牌只进钥匙串。

**渠道**
| 渠道 | 说明 |
| --- | --- |
| OpenCode Zen 免费 | 无需登录（公共身份 `public`），按 OpenCode 2.2.5 的请求头、会话 id 与环境块发出；模型列表实时从 Zen 拉取 |
| GitHub Copilot | GitHub OAuth 设备码登录 → 换取 Copilot 推理令牌 → Chat Completions |
| ZCode（Z.ai / 智谱） | 内置 WKWebView 登录页，走 ZCode 的 CLI 授权流程，自动领 `zcode-api-key`，走 Anthropic Messages 接口；也可以直接粘贴 GLM Coding Plan Key |
| 自定义渠道 | 任意 Base URL，支持 OpenAI / Anthropic / Gemini 三种兼容格式，自定义模型与模型别名 |
| 远程服务 | 电脑或 VPS 上自建助手（如 OpenMausBot / Timon）的地址 + 配对令牌，按 OpenAI 兼容方式接入 |

**团队接力**
- 默认四个角色：总控、码匠、审阅、探索，各自可以绑不同渠道与模型。
- 在对话里点「接力」，把上一条回答交给另一位角色，用同一段上下文继续。
- 「团队任务」按顺序把一件事交给多个角色，一步接一步跑完。

**网关**
- 打开后，同 Wi-Fi 的设备可以调用 `http://<iPhone 的 IP>:8787/v1/chat/completions` 与 `/v1/models`。
- 支持 SSE 流式输出、可选 Bearer 令牌。

**其他**
- 原生 SSE 流式、Markdown 渲染、代码块一键复制、`<think>` / `reasoning_content` 折叠。
- 系统提示词预设、模型重定向（可跨渠道）。
- 水墨（宣纸米白 / 深墨双色、朱砂点缀）与清淡原生两套观感，字号可调。

## 安装

1. 在仓库的 **Actions** 里下载最新一次构建的 artifact `MausIPA-unsigned-ipa`（或 Releases 里的 `build-N`）。
2. 解压得到 `MausIPA-unsigned.ipa`。
3. 用 TrollStore、AltStore、SideStore 或 Sideloadly 自签安装。

## 自己编译

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project MausIPA.xcodeproj -scheme MausIPA \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

## 关于隐私

- 所有 API Key、OAuth 令牌、ZCode Key 只写在 iOS 钥匙串（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）。
- 对话与设置存在 App 沙盒的 `Documents/mausipa.json`，可在「文件」App 里看到。
- 请求由这台 iPhone 直接发往对应服务商，没有中转服务器。
- 局域网网关只在 App 前台运行时监听，只在你自己的网络内可达。

## 致谢

渠道实现参照 [magpie-community/plugins](https://github.com/magpie-community/plugins) 中 `zen-free`、`copilot`、`zcode` 的真实端点与鉴权流程；「AI 作为联系人」的形态受 [OpenMausBot](https://github.com/milind-soni/OpenMausBot) 启发；多角色接力受 [Timon](https://github.com/ai-timon/timon) 启发。

仅供个人学习与自用，请遵守各服务商的条款。
