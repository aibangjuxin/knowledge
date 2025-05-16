

| 项目字段名称                              | 含义/目的说明                                                                 | 具体内容要求                                                                                         | 是否必填 |
|------------------------------------------|------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|----------|
| Regression Test Method                   | 回归测试方法的描述                                                           | 描述使用的回归测试策略，比如：手动测试、自动化测试（如JUnit、Selenium）、集成测试工具等。              | 是       |
| Regression Test Evidence                 | 回归测试的证据                                                              | 提供具体的测试结果截图、测试报告链接、测试成功日志或测试覆盖率报告等。                               | 是       |
| Performance and Stress Test Evidence     | 性能与压力测试的执行证明                                                     | 提供如 JMeter、Locust、Gatling 执行的报告链接或截图；标注测试环境和关键指标（如 RPS、latency）。        | 否       |
| Reason for Performance/Stress Test not Performed | 若未执行性能/压力测试，需说明理由                                      | 示例：小版本无核心变化、测试环境资源限制、非主路径变更或技术债优先级调整等。                          | 是（在未执行测试时） |
| Post Deployment Verification Evidence Link| 部署后验证的相关证据或验证成功的链接                                        | 验证是否部署成功，例如 smoke test 的日志、健康检查结果、控制台截图、监控截图（如Prometheus/Grafana）。 | 是       |
| Regression Testing at Artifact Level     | 是否可以以 artifact 单元（如jar, image等）进行回归测试                     | 说明是否该测试与具体构件关联，而不是与整个平台绑定。比如只对单独 jar/image 做测试就可覆盖回归需求。     | 否       |
| Regression Scope                         | 本次回归测试覆盖的功能模块/接口范围描述                                     | 说明哪些模块或功能受影响、哪些接口经过回归验证，例如“支付接口、用户服务模块、订单创建流程”。            | 是       |
| Regression Test Tool/Framework           | 所使用的测试工具或框架                                                      | 示例：JUnit, Postman, Karate, Cypress, PyTest, Selenium 等。                                         | 是       |
| Regression Test Result Summary           | 测试结果简要汇总                                                            | 如“全部通过”、“5项通过，1项忽略（原因：XXX）”、“0失败”。建议结构化呈现总用例数、失败数等。             | 是       |
| Additional Notes                         | 备注信息                                                                    | 可选项。填写风险说明、需后续补测事项、特例说明等。                                                   | 否       |

建议实践说明：
	•	Evidence 类字段可以直接链接到 Jenkins/GitLab CI 流水线中的报告产出。
	•	Post Deployment Verification 可通过 smoke test 的 script log 输出或 GKE 的 Deployment/Pod readiness 状态截图来作为佐证。
	•	如果采用 GitOps，可以把对应的测试脚本版本、测试结果作为 artifact 上传到 Artifact Registry/GCS 中，做长期追踪。
	•	对于无法测试或跳过测试的项目，一定要说明“跳过原因”，以供审计或后期回溯。

如需我协助提供一个完整模板文档用于 Release checklist 或 CI/CD 流程，也可以继续告诉我。