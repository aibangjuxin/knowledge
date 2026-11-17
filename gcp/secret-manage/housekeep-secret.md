我理解您需要一个shell脚本来扫描Google Cloud项目中的secrets,并根据特定条件(空secret且创建于一个月前)生成报告。我会为您创建一个符合要求的脚本。让我们一步步来实现这个功能。



```bash
#!/bin/bash

# Usage: ./google_secrets_scanner.sh -e <environment>

# Function to display usage
usage() {
    echo "Usage: $0 -e <environment>"
    echo "  -e: Environment (e.g., dev-us)"
    exit 1
}

# Parse command line options
while getopts "e:" opt; do
    case $opt in
        e) ENV=$OPTARG ;;
        *) usage ;;
    esac
done

# Check if environment is provided
if [ -z "$ENV" ]; then
    usage
fi

# Function to get Google Cloud project based on environment
get_project() {
    # This is a placeholder. Replace with actual mapping logic
    case $ENV in
        "dev-us") echo "dev-project-us" ;;
        "prod-eu") echo "prod-project-eu" ;;
        *) echo "Unknown environment" && exit 1 ;;
    esac
}

# Get the project
PROJECT=$(get_project)

# Set the date one month ago
ONE_MONTH_AGO=$(date -v-1m +%Y-%m-%d)

# Scan for empty secrets created one month ago
echo "Scanning for empty secrets created one month ago in project: $PROJECT"

gcloud secrets list --project=$PROJECT --format="table(name,create_time)" | \
while read -r SECRET_NAME CREATE_TIME; do
    # Skip the header line
    if [[ $SECRET_NAME == "NAME" ]]; then continue; fi
    
    # Check if the secret was created one month ago or earlier
    if [[ $CREATE_TIME < $ONE_MONTH_AGO || $CREATE_TIME == $ONE_MONTH_AGO ]]; then
        # Check if the secret is empty
        VERSION_COUNT=$(gcloud secrets versions list $SECRET_NAME --project=$PROJECT --format="value(name)" | wc -l)
        if [[ $VERSION_COUNT -eq 0 ]]; then
            echo "Empty secret found: $SECRET_NAME (Created on: $CREATE_TIME)"
        fi
    fi
done

echo "Scan complete."
```

这个脚本实现了您要求的功能。以下是脚本的主要特点和使用方法：

1. 脚本接受一个 `-e` 参数来指定环境。

2. 它使用一个 `get_project` 函数来根据环境确定Google Cloud项目。您需要根据实际情况修改这个函数以匹配您的环境和项目映射关系。

3. 脚本计算一个月前的日期，并使用这个日期来过滤secrets。

4. 它使用 `gcloud` 命令来列出项目中的所有secrets，然后检查每个secret的创建时间和是否为空。

5. 最后，脚本会输出符合条件的空secrets（创建于一个月前且没有版本）。

使用方法：
1. 将脚本保存为 `google_secrets_scanner.sh`。
2. 给脚本添加执行权限：`chmod +x google_secrets_scanner.sh`
3. 运行脚本，指定环境：`./google_secrets_scanner.sh -e dev-us`

请注意，您可能需要根据实际情况进行一些调整：

- 确保您已经安装并配置了 `gcloud` CLI工具。
- 根据您的实际需求修改 `get_project` 函数中的环境到项目的映射。
- 如果您的 `date` 命令语法不同（例如在Linux上），您可能需要调整计算一个月前日期的命令。

这个脚本提供了一个基础框架，您可以根据需要进一步优化或扩展它。如果您需要任何修改或有任何问题，请随时告诉我。​​​​​​​​​​​​​​​​
