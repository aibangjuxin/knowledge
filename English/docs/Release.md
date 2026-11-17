- update DP 
``` 
We would like to perform a Splunk Index Alignment on the shared DP. Therefore, need you are required to schedule an upgrade. If possible, this operation can be performed by an SRE colleague.
``` 

Here's some of the information I've filtered for all things Python.
The filtering rules are as follows
This is just a keyword filter, it doesn't mean it doesn't work, if it does, please ask your colleagues to check and confirm.

I will summarize our simple test results.
After we modified the character encoding of the Pod to support UTF-8, by simply handling the logic at the code layer, we are currently able to upload and display Chinese. But please note that some special processing is still required in the code here. The snippet code we provided can be referred to.
Also, if our Deployment 2.0 is online, there will be no problem for users to customize Dockerfile to use the defined system language to support Chinese. Please note that code adjustment is still required.
