Summary 
``` bash
A GCE Redis whitelist setting is a security measure that allows you to specify which IP addresses or networks are allowed to connect to your Redis instance. This can help to protect your Redis instance from unauthorized access.
``` 
To create a GCE Redis whitelist setting, follow these steps:

1. Go to the Google Cloud Platform Console.
2. Click the **Menu** button (three horizontal lines) in the top left corner of the page.
3. Select **Compute Engine**.
4. In the **Compute Engine** page, click the **Redis** tab.
5. Click the **Create Redis instance** button.
6. In the **Create Redis instance** dialog, select the **Whitelist** tab.
7. In the **Whitelist** section, enter the IP addresses or networks that you want to allow to connect to your Redis instance.
8. Click the **Create** button.

Once you have created a GCE Redis whitelist setting, only the IP addresses or networks that you specified will be able to connect to your Redis instance.

To permit network for GCE Redis, you need to create a firewall rule that allows traffic to the Redis port. The firewall rule must be created in the same region as the Redis instance.

To create a firewall rule, follow these steps:

1. Go to the Google Cloud Platform Console.
2. Click the **Menu** button (three horizontal lines) in the top left corner of the page.
3. Select **Compute Engine**.
4. In the **Compute Engine** page, click the **Firewall rules** tab.
5. Click the **Create firewall rule** button.
6. In the **Create firewall rule** dialog, enter the following information:
    - **Name:** A name for the firewall rule.
    - **Network:** The network that the firewall rule applies to.
    - **Source ranges:** The IP addresses or networks that are allowed to access the Redis instance.
    - **Destination ports:** The ports that are allowed to be accessed.
    - **Target tags:** The tags that are associated with the Redis instance.
7. Click the **Create** button.

Once you have created the firewall rule, traffic to the Redis port will be allowed from the IP addresses or networks that you specified.

Here are the GCE Redis whitelist setting and network in Markdown format:

## Whitelist setting 

To enable the Redis whitelist, you need to:

1. Login to the Google Cloud Console 
2. Navigate to Compute Engine -> VM instances 
3. Click on the Redis instance 
4. Click Edit 
5. Scroll down to "Redis access control"
6. Check "Enable whitelist" 
7. Enter the IP addresses and CIDR ranges you want to whitelist in the text box 
8. Click Save

## Network 

For network connectivity, you have two options:

1. Public access (default) - Instance has a public IP address and is reachable from anywhere on the internet.  
2. Private access - Instance has only an internal IP address and can only be accessed from resources in the same VPC network or over VPN or Interconnect.

To change to private access:

1. Login to the Google Cloud Console
2. Navigate to Compute Engine -> VM instances  
3. Click on the Redis instance  
4. Click Edit 
5. Scroll down to "Network access" 
6. Select "Private access (VPC only)" from the drop-down 
7. Choose the network and subnet you want the instance in 
8. Click Save

The instance will now have only an internal IP address and will not be publicly accessible from the internet. You will need to ensure any systems or applications using the Redis instance are also on the same VPC network in order to connect.

如果在编辑Redis实例时没有找到“Redis访问控制”选项,这通常意味着实例没有开启身份验证。在这种情况下,您需要首先启用Redis身份验证,然后才能配置白名单。

启用Redis身份验证的步骤如下:

1. 登录Google Cloud Console,打开Redis实例页面
2. 点击“编辑”按钮进行编辑 
3. 向下滚动到“授权和安全”部分
4. 选择“启用身份验证” 
5. 选择一种身份验证方法,可以选择“密码”或“服务账户” 
6. 输入密码或选择服务账户,然后点击“保存”

保存设置后,该Redis实例将启用身份验证。
