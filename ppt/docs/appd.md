# one page 

APPD is an advanced application performance monitoring (APM) tool. It tracks and analyzes application performance in real-time.
（APPD是一种先进的应用程序性能监测（APM）工具。它实时跟踪和分析应用程序性能。）

why Customization
in Appdynamics ,key concept of call capture is using business transaction (BT) but there is a 200BT per Appd Application limitation

- AppDynamics automatically discovers common frameworks and entry points in applications and creates them as Business Transactions (BTs).
- If there are too many BTs in the application, it can lead to performance issues and configuration limitations.
- Therefore, AppDynamics recommends adopting the "less is more" approach, focusing only on the most critical services.

在Appdynamics中，调用捕获的关键概念是使用业务事务(BT)，但每个应用程序有200BT的限制
在AppDynamics中，每个应用程序最多可以有200个Business Transaction(BT)。这是因为:
- AppDynamics会自动发现应用程序中的常见框架和入口点，并将其创建为BT
- 如果应用程序有太多的BT，可能会导致性能问题和配置限制
- 因此AppDynamics建议采用"越少越好"的理念，只关注最关键的服务


1. **Business Isolation and Independence**
   - By customizing the **Application Name** and **Tier Name**,
     - each user or team can have a dedicated namespace, avoiding data conflicts between different businesses.
     - **Application Name**和**Tier Name**自定义后，可以为每个用户或团队提供独立的命名空间，避免不同业务之间的数据冲突。
     - Customizing the **Application Name** and **Tier Name** allows for a better mapping of specific business processes
     - 自定义**Application Name**和**Tier Name**能更好地映射用户具体的业务流程
     - if future monitoring needs arise, naming rules can be adjusted without affecting existing configurations
     - 未来若平台或用户有新的监控需求，可以方便地调整命名规则，不影响现有监控配置
   
2. **Customized Monitoring Views**
   - Users can create personalized monitoring views by customizing 
     - the application and Tier names. This allows users to better organize by business logic, 
     - focusing on the performance and issues of their application, which makes optimization efforts more efficient.
   - 每个用户通过自定义应用名称和Tier名称，可以构建专属的监控视图。
   - 这样用户能更好地按业务逻辑分层，聚焦自己应用的性能和问题，
   - 优化调优变得更高效。

3. Issue Resolution and Troubleshootin
   - If all users share the same application or Tier names, locating performance issues or faults becomes more challenging. By customizing, users can quickly identify and isolate problems related to their applications without filtering through irrelevant data.
   - 如果所有用户都使用共享的应用名称或Tier名称，故障或性能问题的定位将更加困难。
     - 通过自定义，用户能快速发现并隔离与自己相关的应用问题，而无需在大量无关数据中筛选。
   - This helps speed up problem resolution and reduces response times at the platform level, 
     - especially in large-scale multi-user environments.
   - 这有助于提升问题解决速度，减少平台层面的响应时间，尤其在大规模多用户环境下非常重要。
4. Enhanced reporting and analysis
- users can generate reports that are more relevant to their business
   - 通过自定义应用和Tier的命名，用户能更好地生成与自己业务相关的报告



Definition（定义）
APPD is an advanced application performance monitoring (APM) tool. It tracks and analyzes application performance in real-time.
（APPD是一种先进的应用程序性能监测（APM）工具。它实时跟踪和分析应用程序性能。）
Purpose（目的）
APPD monitors application status, identifies bottlenecks, and optimizes performance. It's essential for maintaining smooth operations.
（APPD监测应用程序状态，识别瓶颈并优化性能。它对于维持平稳运行至关重要。）

the Benefits of Custom APPD Aggregation（自定义APPD聚合的好处）

Deep Insights（深入洞察）
Gain detailed understanding of application performance. Identify trends and patterns for optimization.
（深入了解应用程序性能。识别优化的趋势和模式。）

Accelerated Troubleshooting（加速故障排除）
Quickly pinpoint and resolve issues. Reduce downtime and improve overall system reliability.
（快速定位和解决问题。减少停机时间并提高整体系统可靠性。）

Performance Tracking（性能跟踪）
Monitor progress over time. Set benchmarks and track improvements in application efficiency.
（随着时间的推移监测进展。设置基准并跟踪应用程序效率的改进。）


Continuous Optimization（持续优化）
Use insights to fine-tune applications. Ensure peak performance and user satisfaction.
（利用洞察来微调应用程序。确保峰值性能和用户满意度。）


# How to onboarding
Raise tickets with APPD support to onboard and get started with APPD.

The technical lead communicates with the project manager about the requirements and confirms the functions to be implemented on A and the detailed information of the API to be deployed.
技术负责人与项目经理就需求进行沟通，确认在A上实现的功能和部署API的详细信息。

auto send welcome email 
1. A will auto trigger onboarding pipeline. 
2. create a team github repository. 
3. send welcome mail to team members. 

# About tier and node 



在AppDynamics中，**Tier Name**的理解可以从以下几个方面进行阐述：

## Tier Name 的定义

- **Tier Name**是应用程序架构中的一个逻辑层次，通常由一组具有相似功能的节点（Node）组成。每个Tier代表应用程序的一个特定部分，例如前端服务、后端服务或数据库服务。

## Tier Name 的作用

1. **组织结构**：Tier Name帮助组织和分类应用程序的不同部分，使得监控和管理更为清晰。例如，一个电商平台可以有多个Tier，如`WebTier`、`ServiceTier`和`DatabaseTier`。

2. **性能监控**：通过将相似功能的节点分组到同一个Tier中，AppDynamics能够更有效地收集和分析数据，提供性能指标（如响应时间、错误率等）。

3. **流量管理**：在应用程序的流量图中，Tier之间的流动可以清晰地显示出各个部分之间的交互关系，帮助开发和运维团队理解系统架构。

## 自定义 Tier Name 的好处

- **灵活性**：用户可以根据自己的业务需求自定义Tier Name，以便更好地反映业务逻辑。
- **故障排查**：当某个Tier出现问题时，可以快速定位到具体的节点，从而提高故障排查效率。
- **可维护性**：自定义名称使得团队成员能够快速识别和理解不同组件的功能，降低维护成本。

## 默认情况下的限制

在AppDynamics中，虽然没有对单个Tier Name设置硬性配额限制，但需要注意以下几点：

- **许可证限制**：不同的许可证类型可能会限制可监控的节点数量。
- **性能考虑**：过多或过于复杂的Tier结构可能会影响系统性能，因此建议合理规划。

总之，理解和使用Tier Name是有效管理和监控应用程序性能的重要组成部分。通过合理配置，可以提升系统的可视化效果和故障处理能力。

Citations:
[1] https://docs.appdynamics.com/appd/24.x/latest/en/application-monitoring/tiers-and-nodes
[2] https://www.wwt.com/article/appdynamics-implementation-reference-guide
[3] https://stackoverflow.com/questions/69104331/how-to-decide-the-node-and-tiers-in-appdynamics
[4] https://github.com/Appdynamics/appdynamics-openshift-quickstart/blob/master/AppServerAgent/conf/controller-info.xml
[5] https://community.appdynamics.com/t5/Infrastructure-Server-Network-Database/What-are-tiers-and-nodes/td-p/39407
[6] https://stackoverflow.com/questions/72967882/how-to-add-a-java-tier-in-appdynamics
[7] https://docs.appdynamics.com/appd/24.x/latest/en/application-monitoring/install-app-server-agents/agent-installer/manage-tier-naming-rules
[8] https://docs.appdynamics.com/appd/22.x/22.3/ja/application-monitoring/install-app-server-agents/net-agent/install-the-net-agent-for-windows/name-net-tiers

在AppDynamics中，**Tier Name**和**Application Name**的概念如下：

## Tier Name 和 Application Name 的定义

- **Application Name**：这是指应用程序的逻辑名称，通常用于标识一个完整的业务应用程序。例如，一个电商平台可以命名为“ACME ECommerce”。当你在Agent配置中指定一个Application Name时，如果该名称尚不存在，AppDynamics会自动创建它[2]。

- **Tier Name**：这是指应用程序中的一个逻辑层次，通常由多个具有相同功能的节点组成。每个Tier可以包含多个Node（实例），例如，一个电商平台的前端可以是一个Tier，而后端服务可以是另一个Tier[5]。

## 自定义Tier Name和Application Name的好处

1. **精细化管理**：为每个用户团队自定义Tier和Application名称，可以更好地反映其特定需求和架构，使得监控和管理更加清晰。

2. **隔离监控数据**：不同团队可以独立查看和分析自己的性能数据，避免数据混淆，提高故障排查效率。

3. **灵活配置**：用户团队可以根据自身的业务逻辑和技术栈自由配置，增加了系统的灵活性。

4. **增强可维护性**：自定义名称有助于快速识别和理解不同组件的功能，降低维护成本。

## 默认情况下的Quota限制

在AppDynamics中，默认情况下并没有对单个Tier或Application设置硬性配额限制。然而：

- 不同的许可证类型可能会限制可监控的节点数量。
- 过多的Tier和Node可能会影响系统性能，因此建议合理规划和配置。

总之，自定义Tier Name和Application Name能够提升管理效率和监控效果，同时需要注意合理配置以避免性能问题。

Citations:
[1] https://docs.appdynamics.com/appd/24.x/latest/en/application-monitoring/tiers-and-nodes
[2] https://github.com/Appdynamics/appdynamics-openshift-quickstart/blob/master/AppServerAgent/conf/controller-info.xml
[3] https://stackoverflow.com/questions/69104331/how-to-decide-the-node-and-tiers-in-appdynamics
[4] https://stackoverflow.com/questions/72967882/how-to-add-a-java-tier-in-appdynamics
[5] https://community.appdynamics.com/t5/Infrastructure-Server-Network-Database/What-are-tiers-and-nodes/td-p/39407
[6] https://docs.appdynamics.com/appd/22.x/22.3/ja/application-monitoring/install-app-server-agents/net-agent/install-the-net-agent-for-windows/name-net-tiers
[7] https://docs.appdynamics.com/appd/24.x/latest/en/application-monitoring/install-app-server-agents/node-js-agent
[8] https://docs.appdynamics.com/appd/24.x/latest/en/application-monitoring/install-app-server-agents/agent-installer/manage-tier-naming-rules


是的，您理解得很正确！在AppDynamics中，一个**Tier Name**下可以包含多个**Application Name**。以下是更详细的解释：

## Tier Name 和 Application Name 的关系

- **Tier Name**：代表应用程序的一个逻辑层次，通常由多个功能相似或相关的节点组成。一个Tier可以看作是应用程序的某一部分，负责特定的任务或功能。

- **Application Name**：代表一个完整的应用程序，可以包括多个功能模块或服务。每个Application可以在不同的Tiers中运行。

### 示例

假设您有一个电商平台，您可以设置如下结构：

- **Tier Name**：`WebTier`
  - **Application Names**：
    - `UserService`
    - `ProductService`
    - `OrderService`

在这个例子中，`WebTier`包含了多个不同的应用程序（`UserService`、`ProductService`和`OrderService`），它们共同构成了电商平台的一部分。

## 自定义的好处

1. **组织结构清晰**：通过将多个Application Names组织在同一个Tier下，可以更好地反映应用程序架构，使得监控和管理更加直观。

2. **便于故障排查**：当某个Tier出现问题时，可以快速定位到具体的Application，从而提高故障排查效率。

3. **灵活性和扩展性**：随着业务的发展，可以根据需要添加新的Application Names到现有的Tier中，而不需要重新设计整个架构。

## 注意事项

- 虽然一个Tier可以有多个Application，但建议保持合理的层次结构，以避免监控数据过于复杂。
- 确保每个Application Name能够清晰地反映其功能，以便团队成员能够快速理解和使用。

通过合理配置Tier和Application，您可以更有效地管理和监控您的平台应用。




## Tier和Node的概念

在AppDynamics中:

- **Tier**是由具有相同功能的一个或多个节点组成的单元[1][5]。Tier反映了应用程序的逻辑架构。
- **Node**是应用程序的一个实例[1][2]。每个节点都属于一个Tier。

## 为用户自定义Tier和Node的好处

1. **更好地反映应用程序的逻辑架构**。每个用户团队可以根据自己的需求定义合适的Tier和Node[1][5]。
2. **更细粒度的监控和故障排查**。每个用户团队可以针对自己的Tier和Node进行监控和分析[1][6]。
3. **更灵活的配置和管理**。每个用户团队可以独立地配置和管理自己的Tier和Node[4][6]。

## 默认情况下的限制

AppDynamics没有对单个Tier或Node设置硬性配额限制[1][2][5]。但是:

- 不同的许可证类型可能会对监控的节点数量有所限制。
- 过多的Tier和Node可能会影响性能和可用性。

因此,建议根据实际需求合理地设置Tier和Node,避免过度配置。如果需要监控大量节点,可以考虑使用集群代理(Cluster Agent)等方式[1]。

总之,为用户自定义Tier和Node可以带来更好的监控体验,但需要根据实际情况合理配置,避免资源浪费。

Citations:
[1] https://stackoverflow.com/questions/69104331/how-to-decide-the-node-and-tiers-in-appdynamics
[2] https://docs.appdynamics.com/appd/24.x/latest/en/application-monitoring/install-app-server-agents/node-js-agent
[3] https://docs.appdynamics.com/appd/24.x/latest/en/application-monitoring/install-app-server-agents/agent-installer/manage-tier-naming-rules
[4] https://docs.appdynamics.com/appd/24.x/latest/en/application-monitoring/tiers-and-nodes/move-and-rename-nodes
[5] https://docs.appdynamics.com/22.6/en/application-monitoring/tiers-and-nodes
[6] https://community.appdynamics.com/t5/Infrastructure-Server-Network-Database/What-are-tiers-and-nodes/td-p/39407
[7] https://docs.appdynamics.com/display/PRMY23/Name%2B.NET%2BNodes
[8] https://www.youtube.com/watch?v=Lh-2eFdM2z4



在AppDynamics中，**Tier Name**和**Tier Node**分别代表应用层的不同概念：

1. **Tier Name**：它表示应用程序逻辑上的一个分层，比如前端、后端、数据库层等。每个Tier包含若干个服务节点（Node），用于监控和组织不同的业务逻辑。
   
2. **Tier Node**：Node是在特定Tier中的实际实例，通常代表实际运行的服务器或服务。Tier Name和Tier Node一起帮助你组织、监控和分析应用程序的性能。

### 允许自定义Tier Name和Tier Node的好处
你现在想让特定用户使用自定义的Tier Name和Tier Node，有以下几点好处：

1. **独立性和可见性**：
   - 各个用户可以拥有自己独立的Tier Name和Tier Node，便于区分不同团队或服务的性能数据。这样可以更好地隔离不同用户的监控信息，防止混淆。
   
2. **细粒度监控**：
   - 每个用户的性能监控可以独立进行，帮助更精确地分析和调试性能问题。例如，用户可以只看到自己应用的性能情况，而不会混杂其他团队的数据。

3. **更好的优化和调优**：
   - 使用独立的Tier Name和Tier Node后，每个团队可以根据自身的需求进行个性化的监控配置，例如设置特定的警报阈值或分析规则，进行针对性优化。

### Quota限制
默认情况下，AppDynamics并没有硬性的Tier Name或Tier Node数量限制，但在以下几个方面可能会受到影响：

1. **许可和资源使用**：
   - 你的AppDynamics许可证可能会限制可以创建的Tier或Node的数量，具体取决于购买的License类型。如果节点数量超出许可范围，可能需要购买更多的License。

2. **性能和存储资源**：
   - 如果在一个Tier Name或Tier Node下有大量的节点或大量的数据收集，AppDynamics可能会增加服务器的负载，影响系统性能。因此，管理好节点的数量和监控范围也很重要。

3. **可视化与管理复杂性**：
   - 共享同一个Tier Name和Tier Node的情况下，数据可能会变得复杂且难以分析。创建过多的节点也会导致监控页面的可读性下降。因此，合理规划每个Tier下的节点数量可以减轻管理和分析上的负担。

### 总结
允许特定用户使用自定义Tier Name和Tier Node可以增强独立性、监控的精确性，同时防止混淆数据，便于用户或团队专注于自己应用的性能调优。不过需要注意的是，AppDynamics的许可、资源限制以及监控复杂性可能会影响系统的扩展和稳定性。



以下是按照段落对应翻译的内容：
1. 标题：Custom APPD Data Aggregation: Enhancing Monitoring Capabilities（自定义APPD数据聚合：增强监测能力）

Discover how custom APPD data aggregation revolutionizes application performance monitoring. This powerful tool allows users to tailor data collection to their specific needs, enhancing analysis and decision-making capabilities.（了解自定义APPD数据聚合如何革新应用程序性能监测。这个强大的工具允许用户根据其特定需求定制数据收集，增强分析和决策能力。）

2. 标题：Understanding APPD: Your Performance Monitoring Ally（理解APPD：您的性能监测盟友）

Definition（定义）
Purpose（目的）
Benefits（好处）
APPD is an advanced application performance monitoring (APM) tool. It tracks and analyzes application performance in real-time.
（APPD是一种先进的应用程序性能监测（APM）工具。它实时跟踪和分析应用程序性能。）
APPD monitors application status, identifies bottlenecks, and optimizes performance. It's essential for maintaining smooth operations.
（APPD监测应用程序状态，识别瓶颈并优化性能。它对于维持平稳运行至关重要。）
With APPD, teams can proactively address issues. It ensures optimal user experience and system efficiency.
（借助APPD，团队可以主动解决问题。它确保最佳的用户体验和系统效率。）

3. 标题：Custom APPD Aggregation: Tailored to Your Needs（自定义APPD聚合：满足您的需求）

1. Data Aggregation（数据聚合）
Users can customize data aggregation to their own Tier Name and Tier Node. This allows for precise monitoring.
（用户可以根据自己的层级名称和层级节点自定义数据聚合。这允许进行精确监测。）

2. Multi-Dimensional Monitoring（多维监测）
Supports analysis based on various metrics, time ranges, and custom conditions. It offers a comprehensive view.
（支持基于各种指标、时间范围和自定义条件的分析。它提供了一个全面的视图。）

3. User Control（用户控制）
Provides full control and flexibility. Users can define specific data points to monitor, enhancing relevance.
（提供完全的控制和灵活性。用户可以定义要监测的特定数据点，增强相关性。）

The Power of Customization: Unleashing APPD's Potential（定制的力量：释放APPD的潜力）
Improved Decision-Making（改进的决策制定）
Enhanced User Experience（增强的用户体验）
Unmatched Flexibility（无与伦比的灵活性）
Adapt to specific needs effortlessly. Adjust monitoring strategies on-the-fly to match evolving business requirements.
（轻松适应特定需求。即时调整监测策略以匹配不断变化的业务需求。）
Access real-time KPIs for quick, data-driven decisions. Stay ahead of potential issues and optimize performance proactively.
（访问实时关键绩效指标（KPI）以进行快速、数据驱动的决策。领先于潜在问题并主动优化性能。）
Discover and solve problems swiftly. Ensure smooth application performance and keep users satisfied with responsive systems.
（快速发现和解决问题。确保应用程序性能平稳，并使用响应迅速的系统让用户满意。）

4. 标题：Implementing Custom APPD Aggregation in GKE: Step 1（在GKE中实施自定义APPD聚合：步骤1）

Define Tier Name（定义层级名称）
Users determine the logical hierarchy for data aggregation. This forms the foundation of the monitoring structure.
（用户确定数据聚合的逻辑层次结构。这构成了监测结构的基础。）
Define Tier Node（定义层级节点）
Specify the nodes within the hierarchy. This allows for granular control over data collection points.
（指定层次结构中的节点。这允许对数据收集点进行精细控制。）
Customize Metrics（自定义指标）
Select relevant metrics for each tier and node. Tailor the monitoring to specific application needs.
（为每个层级和节点选择相关指标。根据特定应用需求定制监测。）

5. 标题：Implementing Custom APPD Aggregation in GKE: Steps 2 and 3（在GKE中实施自定义APPD聚合：步骤2和3）

1. Data Source Connection（数据源连接）
Establish a connection between the application and APPD's aggregation service. Ensure seamless data flow.
（在应用程序和APPD的聚合服务之间建立连接。确保无缝的数据流动。）

2. Configure Data Transmission（配置数据传输）
Set up parameters for sending performance data. Define frequency and conditions for data updates.
（设置发送性能数据的参数。定义数据更新的频率和条件。）

3. Data Visualization Setup（数据可视化设置）
Create an API or interface for viewing aggregated data. Design intuitive dashboards for easy analysis.
（创建用于查看聚合数据的API或接口。设计直观的仪表板以便于分析。）

6. 标题：Maximizing the Benefits of Custom APPD Aggregation（最大化自定义APPD聚合的好处）

Deep Insights（深入洞察）
Gain detailed understanding of application performance. Identify trends and patterns for optimization.
（深入了解应用程序性能。识别优化的趋势和模式。）
Accelerated Troubleshooting（加速故障排除）
Quickly pinpoint and resolve issues. Reduce downtime and improve overall system reliability.
（快速定位和解决问题。减少停机时间并提高整体系统可靠性。）
Performance Tracking（性能跟踪）
Monitor progress over time. Set benchmarks and track improvements in application efficiency.
（随着时间的推移监测进展。设置基准并跟踪应用程序效率的改进。）
Continuous Optimization（持续优化）
Use insights to fine-tune applications. Ensure peak performance and user satisfaction.
（利用洞察来微调应用程序。确保峰值性能和用户满意度。）

7. 标题：Embracing the Future of Application Monitoring（拥抱应用程序监测的未来）

1. Flexible Solution（灵活的解决方案）
Custom APPD aggregation offers unparalleled flexibility in performance monitoring. Adapt to any business need effortlessly.
（自定义APPD聚合在性能监测方面提供了无与伦比的灵活性。轻松适应任何业务需求。）

2. Simple Integration（简单集成）
With straightforward setup steps, users can quickly implement custom monitoring strategies. Start benefiting immediately.
（通过简单的设置步骤，用户可以快速实施自定义监测策略。立即开始受益。）

3. Continuous Innovation（持续创新）
As technology evolves, custom APPD aggregation will remain at the forefront. Stay ahead with cutting-edge monitoring capabilities.
（随着技术的发展，自定义APPD聚合将保持领先地位。凭借前沿的监测能力保持领先。）






Homepage

• Title: Custom APPD Data Aggregation to User's Tier Name and Tier Node
• Subtitle: Enhance Data Monitoring and Analysis Capabilities

Slide 1: What is APPD?

• Definition: An application performance monitoring (APM) tool used to track and analyze application performance.
• Purpose: Real-time monitoring of application status, identification of bottlenecks, and optimization of performance.

Slide 2: The Functions of Custom APPD Aggregation

• Data Aggregation and Visualization:
    • Users can customize the data aggregation to their own Tier Name and Tier Node.
• Multi-Dimensional Monitoring:
    • Supports monitoring and analysis based on different metrics, time ranges, and custom conditions.
• User Control:
    • Gives users full control and flexibility, allowing them to define specific data to be monitored.

Slide 3: The Benefits of Custom APPD Aggregation

• Improve Decision-Making Ability: Obtain key performance indicators (KPIs) in real-time and make data-driven decisions quickly.
• Optimize User Experience: Discover and solve problems in a timely manner by monitoring application performance.
• Flexibility and Scalability: Adapt to user-specific needs and adjust monitoring strategies at any time.

Slide 4: Implementing Custom APPD Aggregation in GKE

• Step 1: Define Tier Name and Tier Node
    • Users determine the logical hierarchy and nodes of the aggregated data.
• Step 2: Data Source Connection
    • Send performance data from the application to the aggregation service of APPD.
• Step 3: Data Visualization and Analysis
    • Provide an API or interface to allow users to view and analyze aggregated data.

Slide 5: Conclusion

• The custom APPD data aggregation function provides users with a more flexible performance monitoring solution.
• Through simple integration steps, users can customize monitoring strategies. 
