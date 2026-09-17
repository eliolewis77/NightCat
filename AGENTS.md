# AGENTS.md — 接手开发说明

> ✅ 项目现状：上游 Lidless 已改造为 **NightCat**（四档保持唤醒、中英双语、
> 档位锁定、安全网、Sparkle 自动更新），已发布 v1.0.0。原始改造计划
> （SPEC / DECISIONS / PLAN）为维护者本地文档，不入库；改前可向维护者索取。

## 构建与测试

```bash
brew install xcodegen        # Xcode 15+（String Catalog）
xcodegen generate
xcodebuild test -scheme NightCat-CI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme NightCat -destination 'platform=macOS' -configuration Debug
```

**硬性约束：**

- `project.yml` 是唯一事实来源。`NightCat.xcodeproj` 是生成产物（gitignored），**永远不要手改**。
- `Sources/Shared/` 有约 1300 行单元测试，改这里的逻辑要同步维护测试。
- 运行 App 需要开发者签名——特权 Helper 会校验 App 的代码签名。
  签名身份要求 `project.yml` 的 `DEVELOPMENT_TEAM` 与
  `Sources/Shared/HelperProtocol.swift` 的 `NightCatHelper.teamID` **一致**，
  不一致时 XPC 静默失败、无任何报错。

## 关键约束

- **不要删除 `LICENSE` 里的原始版权声明**（MIT 要求保留上游作者版权）。
- **不要把状态机搬进 helper。** helper 保持「薄」：只翻 `disablesleep` 标志 + 心跳。
- **不要动 helper 的 90 秒看门狗语义**：App 停止心跳超 90 秒自动恢复睡眠，
  是防「卡在永远不睡」的核心安全网。
- 不要在未明确要求的前提下引入第三方依赖。

## 坑清单

| 坑 | 说明 |
|---|---|
| helper 静默失效 | Team ID / bundle id 不匹配时 XPC 连不上，界面无报错。先查签名 |
| `SKIP_INSTALL` / `CREATE_INFOPLIST_SECTION_IN_BINARY` | `project.yml` 里必需，删了 helper 无法 exec 或 archive 被拒 |
| 需要真实签名才能运行 | `CODE_SIGNING_ALLOWED=NO` 只能编译测试 |
| AppNap 已禁用 | `NSAppSleepDisabled` 在 project.yml——菜单栏 App 被冻结会停心跳、误触看门狗 |
| 合盖跑有热量代价 | 合盖散热差，长时间跑批注意通风 |

## 发布

见 `scripts/release.sh` 头部文档：bump `MARKETING_VERSION` → `./scripts/release.sh`
→ DMG 传 GitHub Release、appcast push（Pages 自动部署）。

## 交付与验证习惯（项目所有者的明确偏好）

- **改完直接报告**：改了什么、在哪个文件、哪一步没做完、哪里还没验证。不要用「已完成」笼统盖过。
- **不要主动跑单测、全量回归、装机截图来自证**——验证是所有者自己的环节。例外：他在当轮明确要求。
- 最低限度：提交前确认**能编译**。没验证就如实说「未验证」。
