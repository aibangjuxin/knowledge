# 智能纪要：System Solution Discussion 2026年9月22日

录音时间：2026\-09\-22 15:31 \- 2026\-09\-22 15:56

# 总结

This meeting discusses internal traffic gateway solution selection, Mesh rollout planning and Kong gateway support specifications for the platform, details are as follows:

- **Internal Traffic Gateway Solution Strategy**

    - **Core Solution Alignment**

        - Default onboarding rule: All new tenants under the March solution framework will be onboarded to the no\-gateway Mesh solution as the preferred default path\.

        - Existing tenant arrangement: Tenants currently using Kong gateway can retain the service temporarily, and will be migrated to the Mesh solution in subsequent batches\.

    - **Kong Gateway Response Mechanism**

        - Requirement matching: Most existing Kong usage scenarios \(authentication, cross\-domain plug\-ins\) can be covered by Mesh capabilities, and simple traffic control can also be implemented via Mesh\.

        - Alternative solutions: Multiple temporary options including common Kong gateway on IP and sidecar Kong gateway are proposed for tenants who explicitly insist on using Kong\.

        - Resource principle: No long\-term dedicated development and maintenance resources will be invested in Kong\-related solutions to avoid extra operational workload\.

![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=YTdjOTY1MWU5YTBlM2QyOGIyMzYyMzUyZDU1MmZiNGFfZWUyYTczMDczNmVkZWM4ZDEyMGVkMTM2OWFkZGZjZjhfSUQ6NzY4ODI2NjIwODA1NTU0NDc3OV8xNzkwMDY0Nzk5OjE3OTAxNTExOTlfVjM)

![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=OGNmOTkzYzRiYTVmMmQyNDRiMzY5MjdlMTFkYjBiNmFfNzRiOTgyM2E2OTdiNTk1OGM2YmYxZjg2NzU0ZTUyMzlfSUQ6NzY4ODI2NjIwNjUyMDc3Mzg1NV8xNzkwMDY0Nzk5OjE3OTAxNTExOTlfVjM)

    - **Supporting Arrangement Clarification**

        - Scope exclusion: Public ingress capability discussion and internal/external namespace division rules are not covered in this meeting, and will be arranged as separate topics\.

        - Naming confirmation: The naming specification for relevant namespaces has been fully confirmed, and only the namespace tagging logic remains to be finalized\.

- **Mesh Solution Rollout Arrangement**

    - **Near\-term Delivery Target**

        - Timeline requirement: The Mesh solution is planned to be enabled for the ET customer by the end of the current month, with relevant template and environment review work ongoing\.

        - Capacity coordination: Relevant personnel will coordinate with Rita to confirm available development capacity, and re\-prioritize tasks if necessary to meet the timeline\.

    - **Subsequent Rollout Plan**

        - Regional coverage: After the ET customer adaptation is completed, full rollout of the Mesh solution across all regions will be officially launched from October\.

        - Migration preparation: The team will sort out standardized migration rules and support mechanisms for existing tenants during the Mesh rollout process\.

![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=OWEyNmUxZmM1ZTVhYWUxODc1ZTFkZDJhNmQ4ZWYyMDhfNDQxNTRhYzY3OGRiNTU0Nzk2YTU3MWRlZTYxOTAxNzdfSUQ6NzY4ODI2NjIwNTg3OTExMDg2Nl8xNzkwMDY0Nzk5OjE3OTAxNTExOTlfVjM)

- **Pending Follow\-up Arrangements**

    - **Kong Gateway Rule Confirmation**

        - Discussion arrangement: A follow\-up meeting will be arranged after the upcoming public holiday \(around next week\) to discuss with Benny on the formal support rule for Kong gateway requests\.

        - POC arrangement: No dedicated POC for Kong\-related solutions will be launched for the time being, pending the conclusion of the above follow\-up discussion\.

    - **Ad\-hoc Requirement Handling**: For temporary ad\-hoc tenant requests for gateway capabilities, the team will evaluate specific requirements on a case\-by\-case basis for targeted response\.



# 智能章节

00:25**  Discussion on Internal Traffic Solutions and Current Kong Gateway Related Capabilities**

> This meeting focuses on internal traffic related Kong Gateway solutions, clarifying its scope excludes north\-south public ingress which will be discussed separately\. Current agreed scheme for internal traffic is no\-Kong gateway solution, the team will explore future capability support ways, sort out existing Kong use cases covering authentication plugins, DSP cross\-domain plugin integration etc, to verify if these demands can be satisfied without Kong\.
> 
> 

05:08**  Discussions on Namespace Naming Schemes and Internal Environment Alignment Pending Public Inquiry**

> This chapter centers on two key topics\. First, the namespace arrangement is not fully finalized yet, though the naming itself is confirmed, pending decisions on how to tag different namespaces\. Second, the internal traffic isolation for public\-related matters in grass remains to be discussed, as the team will build 3 new early environments in grass and needs to align on relevant limit commission, and all related discussions are currently limited to internal members only\.
> 
> 

06:17**  Discussion on Kong, Mesh Adaptation and Tenant Migration to Etna**

> This session clarifies the incompatible issue between Kong and mesh\. The agreed solution is retaining Kong gateway for existing tenants that do not require mesh \(mostly batch job scenarios\) temporarily, while halting new tenant onboarding to Kong\. Most tenants will eventually be migrated to Etna first, then enable mesh after Etna passes relevant testing, no DSP plugin will be developed for this demand\.
> 
> 

09:24**  Discussion on New Users' Gateway Usage Rules and Alternative Solutions**

> This meeting clarifies the new user/tenant onboarding rule: all new users default to the March solution, the preferred option is mesh without gateway\. If users insist on using Kong gateway, they can adopt the common Kong gateway on IP, since setting it up on GCP is incompatible with mesh and wastes extra effort\. Relevant follow\-up actions include verifying the feasibility of the proposed scheme, and processing tenant gateway demands by checking specific requirements respectively\.
> 
> 

15:21**  Discussion on POC, Technical Solution Selection and Next Step Arrangement**

> The team discussed necessary POC options including RKP/TTP, deemed common KDP as high\-maintenance with big structural impact and not a proper long\-term solution\. They agreed to provide users with available solutions for their own choice, focused on rolling out the preferred default solution next, and will arrange a post\-holiday follow\-up meeting to confirm whether to support the convenient solution for insisting users, plus related effort assessment\.
> 
> 

21:59**  Discussion on Timeline and Prioritization of Enabling the Solution for the ET Customer**

> This section mainly discusses the timeline of the nice solution: Thomas will present the timeline tomorrow, the core current target is to enable the function for the ET customer, the team aims to get the corresponding machine ready by the end of this month, and will roll out the solution to all regions starting from October\. The team notes they are facing tight multi\-release pressure with a public holiday this Friday, and will check remaining capacity with Rita, discuss offline to adjust task priorities to hit the target\.
> 
> 



# 关键决策

## Key Decision

- **Problem**: Determine the onboarding and support rules for Kong gateway for new tenants during the migration to the mesh solution\.

- **Discussion Plan**:

    - Speaker 1 states that the default preferred onboarding method for new users is the mesh solution without a gateway, and if users insist on using Kong gateway, a temporary solution needs to be provided\.

    - Speaker 2 proposes that existing Kong gateway users can retain the service temporarily and migrate to Etna later, and new tenants should be prioritized to use the non\-gateway solution as the team is migrating away from Kong\.

    - Speaker 3 suggests that new onboarding tenants should not be provided with Kong gateway services, and this rule should be raised as core strategy\.

- **Decision Basis**: The team is in the process of migrating away from Kong gateway to the mesh solution, and additional maintenance effort on Kong should be minimized\.

- **Other Decisions**:

    1. Arrange a meeting after the public holiday to discuss with Benny on whether to support Kong gateway for users who insist on using it\.

    2. Target to enable the mesh solution for relevant customers by the end of the current month\.

    3. Plan to roll out the mesh solution to all regions starting from October\.

    4. Conduct an offline discussion to re\-prioritize work items to meet the end\-of\-month mesh solution delivery target\.

    5. Verify the feasibility of the proposed Kong gateway support solutions before the meeting with Benny\.

---



# 金句时刻

「But the Kong, the problem with Kong is that we have to keep it for a while because we will migrate out of Kong\.」

—— It clearly states the core background of the current gateway solution adjustment, which is the key premise for all subsequent discussion of onboarding rules\.



「No idea for my opinion is for existing user, we can keep good way, but for new awarding talents, we don't out good way any actually that should raise to the core strategy\.」

—— It puts forward a clear differentiated management strategy for existing and new tenants, which is an important reference for the final decision of gateway support rules\.



「So by the end of the month, I really would like to have machine able for that then\.」

—— It clarifies the clear delivery timeline of the core mesh solution, which is a key time node for the subsequent work arrangement of the whole team\.

> （注：部分内容可能由 AI 生成）
