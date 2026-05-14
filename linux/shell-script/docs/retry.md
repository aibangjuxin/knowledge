以下是一个简单的shell脚本，用于重试访问URL地址的逻辑，最多重试3次。您可以将脚本保存为一个.sh文件并在终端中运行。

```
#!/bin/bash

retry_count=0
max_retries=3
url="http://example.com"

while [ $retry_count -lt $max_retries ]
do
    response=$(curl -s -o /dev/null -w "%{http_code}" $url)
    if [ $response -eq 200 ]
    then
        echo "Success"
        exit 0
    else
        echo "Failed to access URL. Retrying in 5 seconds..."
        sleep 5
        retry_count=$((retry_count+1))
    fi
done

echo "Failed all retries. Exiting..."
exit 1
```

这个脚本使用了curl命令来访问URL地址，并检查返回的HTTP状态码是否为200。如果访问成功，脚本将输出"Success"并退出，否则将等待5秒钟并尝试重新访问URL地址，最多重试3次。如果所有重试都失败，脚本将输出"Failed all retries. Exiting..."并以非零状态码退出。

请注意，这个脚本仅供参考，您可以根据您的需求进行修改。例如，您可以更改URL地址、重试次数、等待时间等参数。

这里是一个 shell 脚本的重试逻辑示例:

```bash
#!/bin/bash

# 设置最大重试次数
max_attempts=3  

# 设置当前尝试次数
current_attempt=1

while true; do

  # 请求 URL
  response=$(wget -qO- http://example.com)
  
  # 检查响应是否成功    
  if [[ $response == *"success"* ]]; then
    echo "Request succeeded!"
    break  
  fi
  
  # 重试次数超过最大次数则退出  
  if [ $current_attempt -gt $max_attempts ]; then
     echo "Failed after $max_attempts attempts."
     break 
  fi
  
  # 增加当前尝试次数       
  current_attempt=$((current_attempt + 1))
  
  # 打印正在重试        
  echo "Attempt $current_attempt failed, retrying..."  
  
  # 等待一段时间再重试
  sleep 5

done
```

主要逻辑为:

- 设置最大重试次数 max_attempts 为3
- 初始化当前尝试次数 current_attempt 为1
- 使用 while true 循环来实现重试
- 每次请求 URL ,检查响应是否成功
- 如果成功,则退出循环
- 检查当前尝试次数是否超过最大次数,如果超过则退出循环并报错
- 每次失败后,增加当前尝试次数
- 打印正在重试
- 等待几秒再重试

以上脚本演示了一般重试逻辑:

- 设置最大重试次数
- 初始化和增加尝试次数变量
- 检查响应是否成功,否则继续重试
- 超过最大重试次数则报错
- 每次重试前打印消息并等待一段时间再重试
