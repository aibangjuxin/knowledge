
Typical scenarios
- Kong DP 没有记录到分发到后端 GKE RT 请求的日志
- **比如RT启用了一个插件,但是Pod还没有启动 或者失败 或者拿不到Token的时候 Kong这里应该是都没有日志的**

Kong Data Plane (Kong DP) 的日志记录通常会包括请求的相关信息，包括请求的来源、目标、状态码等。如果 Kong DP 没有记录到分发到后端 GKE RT 请求的日志，可能是以下几种情况导致的：

1. 请求被提前拦截或拒绝：
	•	如果请求在 Kong DP 中的某个步骤（如路由、身份验证、授权等）被拦截或拒绝，Kong 可能不会将请求记录为已成功转发。例如：
	•	身份验证失败：如果请求需要身份验证（如JWT验证、API密钥检查等），而验证失败，Kong DP 可能会在拒绝请求时停止进一步处理。
	•	API 限流：如果请求超过了设置的请求速率限制（rate limiting），Kong 可能会拒绝该请求，而不会转发到后端。
	•	授权失败：如果请求没有满足访问控制列表（ACL）或其他授权策略，Kong 会拒绝请求。

2. Kong配置中的错误或缺失：
	•	日志配置问题：Kong的日志可能没有被正确配置或者配置了不记录某些类型的请求。检查 Kong 配置中的日志级别和日志目标设置，确保日志功能启用且没有被过滤掉某些请求。
	•	Kong API 或插件错误：某些插件（如身份验证插件、代理插件等）可能会在请求处理的过程中出现问题，导致请求没有被成功转发。此时，日志可能会包含错误信息，但不会记录到后续的请求。

3. Kong负载均衡器选择问题：
	•	Kong 在作为API网关时，会基于配置的负载均衡策略选择后端服务。如果配置不正确，或者后端服务无法响应，Kong可能会在尝试转发请求时失败，导致请求没有成功传递到后端RT。
	•	例如，Kong DP可能会选择一个不可用或健康检查失败的Pod，这样请求就不会被成功转发。

4. 请求过早超时：
	•	如果请求在被传递到后端RT之前就因为某些原因（如网络问题、后端服务超时等）超时，Kong可能没有时间记录成功的日志。这种情况通常出现在请求的响应超时发生在后端服务之前。

5. Kong与后端RT之间的网络问题：
	•	如果 Kong DP 与后端 GKE RT 服务之间存在网络问题（如DNS解析失败、VPC限制、访问权限问题等），请求可能未能成功转发到RT。这种情况下，Kong的日志可能记录了网络错误、连接拒绝等信息，但没有记录到实际的请求转发日志。

6. Kong的日志过滤或采样：
	•	Kong可能配置了日志采样策略或者日志过滤规则，导致只记录部分请求。比如，如果启用了日志采样（sampling），可能会仅记录一定比例的请求日志，而忽略其他请求。

7. Kong的内部错误或崩溃：
	•	如果 Kong DP 在处理请求时发生内部错误（如插件崩溃、内存溢出等），请求可能会被丢弃，日志也可能未能成功记录。

优化建议：
	•	检查日志级别和配置：确保 Kong 的日志配置没有问题，日志级别设置为足够详细（例如 debug 或 info），以便记录所有请求。
	•	检查插件和策略：确保没有插件或策略导致请求被中断或丢弃。特别是身份验证、授权和限流插件需要仔细检查其配置。
	•	确保网络畅通：确保 Kong 与后端服务之间的网络连接正常，排查可能的网络延迟或超时问题。
	•	查看Kong日志：除了请求日志外，还可以查看Kong的错误日志，可能会有相关的错误信息，帮助定位请求未转发的原因。

如果你能够提供更多具体的日志或配置细节，我可以帮助你更深入地分析潜在问题。