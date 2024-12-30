I have a doubt about the network problem here and I want to consult you. I wonder if it's convenient for you to help me?
My core purpose is that if our destination email service requires a whitelist authentication, then I want to obtain the corresponding outbound IP of the hosts in our GCP project.
Although the data packet has gone through multiple hops (through network segments such as 10.118.x.x, 130.219.x.x, 130.45.x.x, etc.)
But when it finally reaches the destination server, the original source IP address 10.98.2.222 is maintained.

This is likely because:

The GCP network uses the source NAT retention mode
Or a policy to retain the source IP is configured on the routing path


So which one is my outbound IP?
