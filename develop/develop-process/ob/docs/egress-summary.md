运行在我GKE 环境里面的用户的Runtime GKE  Pod 默认是无法访问外部地址的
现在GKE  Pod需要访问外部必须走代理.GKE Squid Pod Proxy 我们会给用户生成一个比如
micro.aibang.uk.local:3128的代理比如其,目前大概的Squid配置如下
```squid.conf
acl my_proxy dstdomain login.microsoftonline.com www.office.com
cache_peer another.px.aibang parent 18080 0 no-query default
cache_peer_access another.px.aibang allow my_proxy
never_direct allow my_proxy
http_port 3128
```
这个比如特指用户需要访问login.microsoftonline.com
那么我们给用户的这个GKE  Pod增加对应的标签比如叫做micro=enabled 通过networkpolicy控制这个Pod可以连到micro.aibang.uk.local:3128所在的SVC的deployment的Squid Pod 
GKE Pod ==> GKE Squid Pod Proxy ==> 这里可以走两个cache_peer出去。  
我们现在需要拓展其实GKE Squid Pod Proxy这个需要根据用户的目的域名来决定下一跳的代理地址是什么?那么基于这个帮我去实现一个最佳方案?
如何处理比较好 生成一个新的文档 命名为squid-egress-multip.md
如果可以在文档里面增加一些markdown的mermaid的Flow
   让更容易理解这个过程 ​