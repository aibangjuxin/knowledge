In the past, due to the lack of client certificate validation support in Google’s HTTPS Load Balancer, there was a potential  security risk when handling mTLS traffic. Furthermore, Cloud Armor could not be applied for (WAF) protection in this setup.

This year, the support has become available, enabling us to adopt mTLS with full certificate validation and WAF protection through Cloud Armor, significantly enhancing our platform’s security posture.   

  

In May, all our Non - prod (non - production) environments have been deployed. 

Last week, we released all of them to the PRD (production) environment.