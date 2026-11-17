#Function test
# function
- function test
- 功能测试(function test)
- 非功能测试(non-function test)
- 区别:
	- 功能测试:测试软件的功能是否正常工作,主要测试软件是否能够按需求实现对应的功能。如接口测试、业务流程测试等。
	- 非功能测试:测试软件的其他特性,如性能、安全、可用性等。如压力测试、安全测试、可用性测试等。

## 在K8S+Kong的项目中,
- 需要注意的测试问题有:
功能测试方面:
- Kong的各个功能模块是否正常工作,如路由、服务发现、身份验证等。
- Kong与K8S的集成是否正常,例如K8S Ingress是否可以正常通过Kong进行流量管理等。
非功能测试方面:
- 性能:在高负载下,Kong+K8S的性能表现如何,是否会成为系统的性能瓶颈。
- 稳定性:在长期高负载或异常情况下,系统是否稳定运行,不会出现宕机崩溃等情况。
- 安全:检查Kong和K8S在安全方面是否有漏洞,例如鉴权漏洞、SQL注入漏洞等。
- 高可用:测试Kong和K8S的高可用机制是否有效,例如在节点失效或其他异常情况下,能否平滑进行故障转移。
other 
```bash
除此之外,在测试过程中还需要考虑自动化测试、模拟真实流量、日志收集与分析等问题。总体来说,要全面测试Kong+K8S在功能、性能、稳定性、安全、高可用等方面的表现,并通过分析测试结果不断优化系统。"non-functional test"（非功能测试）是两个常见的测试类型，它们有不同的重点和目标。
```

- reference other
- Function test
```
功能测试（function test）主要关注系统的功能和行为。它确保软件在各种输入条件下按照预期执行，并验证系统的各个功能模块是否正确工作。功能测试通常涉及单元测试、集成测试和系统测试等级别。
```
- Non-function test
```
非功能测试（non-functional test）则侧重于系统的性能、可用性、安全性和可靠性等方面。它关注系统在各种环境和负载条件下的性能表现以及用户体验。非功能测试可以包括性能测试、安全测试、可用性测试和可靠性测试等。
```
在进行功能测试和非功能测试时，您应该注意以下问题方面或考虑以下问题：

1. 功能测试：
- 确保每个功能模块的功能符合需求规格说明。
- 检查各种输入条件下的预期输出是否正确。
- 验证系统是否满足用户需求和预期行为。

2. 非功能测试：
- 性能测试：评估系统的性能指标，如响应时间、吞吐量和负载容量。
- 安全测试：验证系统的安全性，包括身份验证、授权和数据保护等方面。
- 可用性测试：评估系统的易用性和用户友好性。
- 可靠性测试：测试系统在各种异常条件下的稳定性和容错能力。

此外，还应考虑以下问题：
- 测试覆盖范围：确定要测试的功能和非功能方面的覆盖范围。
- 测试环境和数据：设置适当的测试环境和测试数据，以模拟实际使用情况。
- 测试工具和自动化：选择适当的测试工具和自动化脚本，以提高测试效率和一致性。
- 性能基准：设定性能指标和基准，以便将来进行比较和监测。

通过综合考虑功能测试和非功能测试，您可以确保系统在功能和性能方面都能够满足需求，并提供良好的用户体验。

对于在Kubernetes上运行Kong DP的情况，以下是一些测试考虑和具体细节，可以帮助确保系统的质量和可靠性：

1. 功能测试：
- 配置管理：测试Kong DP配置的正确性，包括路由、插件、证书等。
- 负载均衡和服务发现：验证Kong DP在Kubernetes集群中的负载均衡和服务发现功能是否正常工作。
- API管理：测试API的注册、发布和访问控制等功能。
- 插件功能：验证Kong DP所支持的插件在不同场景下的行为和功能。
- 错误处理：测试Kong DP对于无效请求、错误配置和异常情况的处理能力。

2. 性能测试：
- 吞吐量和响应时间：评估Kong DP在不同负载下的吞吐量和响应时间。
- 扩展性：测试Kong DP在增加节点或扩展Kubernetes集群时的性能表现。
- 负载均衡：验证Kong DP在负载均衡方面的性能和效果。

3. 安全性测试：
- 认证和授权：测试Kong DP的认证和授权机制，确保访问控制的准确性和安全性。
- 数据保护：验证Kong DP对于敏感数据的保护和安全传输（如SSL/TLS）。
- 漏洞和攻击测试：测试Kong DP的抗攻击能力，包括常见的漏洞和攻击类型。

4. 可用性测试：
- 容错和故障恢复：模拟节点故障或容器重启等场景，测试Kong DP的容错和故障恢复机制。
- 高可用性：验证Kong DP在多个副本或节点的配置下，系统是否能保持高可用性。

5. 集成测试：
- Kubernetes集成：测试Kong DP与Kubernetes的集成和互操作性，包括Pod和Service的自动发现等方面。

在进行测试时，还应该注意以下细节：
- 使用适当的测试数据和场景，以覆盖不同的使用情况和业务场景。
- 设置适当的测试环境，包括Kubernetes集群和Kong DP的部署环境。
- 结合持续集成和持续交付（CI/CD）流程，自动化测试并确保测试的可重复性和一致性。
- 监测和记录测试结果，包括性能指标、错误日志和异常情况。

通过综合考虑这些测试考虑和细节，您可以对在Kubernetes上运行Kong DP的系统进行全面的测试和验证，以确保其稳定性、性能和安全性。

功能测试(function test)和非功能测试(non-function test)的区别:

- 功能测试:测试软件的功能是否正常工作,主要测试软件是否能够按需求实现对应的功能。如接口测试、业务流程测试等。

- 非功能测试:测试软件的其他特性,如性能、安全、可用性等。如压力测试、安全测试、可用性测试等。

在K8S+Kong的项目中,需要注意的测试问题有:

功能测试方面:

- Kong的各个功能模块是否正常工作,如路由、服务发现、身份验证等。
- Kong与K8S的集成是否正常,例如K8S Ingress是否可以正常通过Kong进行流量管理等。

非功能测试方面:

- 性能:在高负载下,Kong+K8S的性能表现如何,是否会成为系统的性能瓶颈。
- 稳定性:在长期高负载或异常情况下,系统是否稳定运行,不会出现宕机崩溃等情况。
- 安全:检查Kong和K8S在安全方面是否有漏洞,例如鉴权漏洞、SQL注入漏洞等。
- 高可用:测试Kong和K8S的高可用机制是否有效,例如在节点失效或其他异常情况下,能否平滑进行故障转移。

除此之外,在测试过程中还需要考虑自动化测试、模拟真实流量、日志收集与分析等问题。
总体来说,要全面测试Kong+K8S在功能、性能、稳定性、安全、高可用等方面的表现,并通过分析测试结果不断优化系统。

Non-functional testing aspects.

- Performance: Under high load, how does Kong+K8S perform and whether it will become a bottleneck in the system's performance.
- Stability: in long-term high load or abnormal conditions, the system is stable operation, will not be down and crash.
- Security: check Kong and K8S in the security aspects of whether there are vulnerabilities, such as authentication vulnerabilities, SQL injection vulnerabilities, etc.
- High availability: test Kong and K8S high availability mechanism is effective, for example, in the case of node failure or other abnormalities, whether smooth failover.

In addition, in the testing process also need to consider automation testing, simulation of real traffic, log collection and analysis. In general, the performance of Kong+K8S in terms of functionality, performance, stability, security, and high availability should be tested comprehensively, and the system should be continuously optimized by analyzing the test results.

通过DeepL翻译 (https://www.deepl.com/app/?utm_source=ios&utm_medium=app&utm_campaign=share-translation
