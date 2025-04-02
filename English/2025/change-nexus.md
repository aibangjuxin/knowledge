Summarize the problems of the Com Amplifier team.
Recently, Nexus was upgraded and no longer supports the Nexus apt update source. It is necessary to migrate to Nexus302.
The following is the content of the announcement.
The work we've done: Tested the new Ubuntu version and supported the installation of the corresponding Python. Here, the Python3.12 version was successfully tested.
Actual user requirements:
Continue to use the old Ubuntu Images 2004.
However, since the Nexus source is no longer supported, users need to replace the configuration in the Dockerfile to continue using the old Python3.9 and be able to use the new Nexus source.
The core modified configuration is as follows.
With the above configuration, it is possible to successfully use ubuntu20.04 + Nexus + Python3.9.


During the support process, we found that users are not very familiar with Dockerfile. They are not familiar with some slightly complex statements or debugging techniques. So, it requires us to put in a bit more effort. Moreover, our 2.0 version supports user - defined settings, which is quite different from the standard templates we provide. Therefore, debugging takes time.