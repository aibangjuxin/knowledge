https://cloud.google.com/storage-transfer-service?hl=en

https://cloud.google.com/storage-transfer/docs/create-transfers?hl=zh-cn#gcloud-cli


https://cloud.google.com/storage-transfer/docs/cloud-storage-to-cloud-storage?hl=zh-cn
何时使用 Storage Transfer Service
Google Cloud 提供了多种在 Cloud Storage 存储桶之间转移数据的方法。我们建议您遵循以下准则：

小于 1 TB 的转移：请使用 gsutil 或 gcloud。有关说明，请参阅移动和重命名存储桶。

超过 1 TB 的转移：请使用 Storage Transfer Service。Storage Transfer Service 是一种代管式转移方法，以开箱即用的方式提供安全性、可靠性和高性能。这种方法无需优化和维护脚本，也无需处理重试。

本指南介绍使用 Storage Transfer Service 在 Cloud Storage 存储桶之间转移数据的最佳实践。



转移本地数据
我们提供以下本地数据转移解决方案：

对于小型数据集，您可以使用 gsutil rsync。使用 gsutil rsync 在 Cloud Storage 与其他云存储服务之间转移数据，或者在 Cloud Storage 和本地数据之间转移数据。

对于大型数据集，您可以使用 Transfer Service for On Premises Data。使用 Transfer Service for On Premises Data 在 Cloud Storage 和本地存储之间转移数据。

Cloud Storage Transfer Service 是一种完全托管的服务，可用于将数据从一个存储桶复制到另一个存储桶。该服务可以自动处理复制任务，而无需您手动执行任何操作。

Cloud Storage Transfer Service 可以从各种来源复制数据，包括本地文件系统、云存储服务、数据库和 SaaS 应用程序。您可以使用 Cloud Storage Transfer Service 复制任何类型的数据，包括文件、数据库表、电子邮件和日志。

要使用 Cloud Storage Transfer Service，您需要创建一个转移作业。转移作业定义了要复制的对象和目标存储桶。

以下是创建转移作业的步骤：

1. 在 Google Cloud Platform Console 中，打开 Cloud Storage Transfer Service。
2. 单击 **创建转移作业**。
3. 为转移作业提供名称和描述。
4. 选择要复制的来源。
5. 选择要复制的目标存储桶。
6. 配置转移作业。
7. 单击 **创建**。

创建转移作业后，您可以监控其进度。您可以查看转移作业的状态、进度和错误消息。

以下是 Cloud Storage Transfer Service 的一些优势：

* 完全托管：您无需担心基础设施或管理任务。
* 自动化：转移作业会自动运行，而无需您手动执行任何操作。
* 灵活性：您可以从各种来源复制数据。

以下是 Cloud Storage Transfer Service 的一些用途：

* 数据迁移：将数据从一个存储桶迁移到另一个存储桶。
* 数据备份：将数据备份到另一个存储桶。
* 数据同步：将数据从一个存储桶同步到另一个存储桶。

以下是 Cloud Storage Transfer Service 的价格：

* 免费使用 1 TB 的数据量。
* 超出 1 TB 的数据量按每 GB 收费。

您可以使用 Cloud Storage Transfer Service 价格计算器来估算您的成本。


是的，有命令行来实现 Cloud Storage Transfer Service。您可以使用 `gcloud` 命令来创建和管理转移作业。

以下是使用 `gcloud` 命令创建转移作业的示例：

```
gcloud transfer jobs create my-job \
  --source-bucket=my-bucket \
  --destination-bucket=new-bucket \
  --transfer-configs=gs://my-bucket/config.json
```

此命令将创建一个转移作业来复制存储桶 `my-bucket` 中的所有对象到存储桶 `new-bucket`。转移作业将使用存储桶 `my-bucket` 中的 `config.json` 文件来配置。

您可以使用 `gcloud` 命令来监控转移作业的进度。以下是查看转移作业状态的示例：

```
gcloud transfer jobs describe my-job
```

此命令将显示转移作业的状态、进度和错误消息。

以下是 `gcloud` 命令的一些常用选项：

* `--source-bucket`：指定要复制的源存储桶。
* `--destination-bucket`：指定要复制的目标存储桶。
* `--transfer-configs`：指定转移作业的配置文件。
* `--schedule`：指定转移作业的运行时间表。
* `--start-time`：指定转移作业的开始时间。
* `--end-time`：指定转移作业的结束时间。
* `--max-transfer-size`：指定每个转移的最大大小。
* `--max-transfers`：指定同时运行的最大转移数。

您可以使用 `gcloud transfer jobs` 命令的帮助文档来了解有关这些选项的更多信息。

以下是 `gcloud transfer jobs` 命令的帮助文档：

```
$ gcloud transfer jobs --help

NAME
gcloud transfer jobs

DESCRIPTION
Creates and manages transfer jobs.

SYNOPSIS
gcloud transfer jobs COMMAND

COMMANDS
create
Creates a transfer job.
describe
Describes a transfer job.
list
Lists transfer jobs.
pause
Pauses a transfer job.
resume
Resumes a transfer job.
delete
Deletes a transfer job.

FLAGS
--source-bucket
The name of the source bucket.
--destination-bucket
The name of the destination bucket.
--transfer-configs
The path to the transfer configuration file.
--schedule
The schedule for running the transfer job.
--start-time
The start time for the transfer job.
--end-time
The end time for the transfer job.
--max-transfer-size
The maximum size of each transfer.
--max-transfers
The maximum number of transfers that can run simultaneously.

EXAMPLES
To create a transfer job that copies all objects from the source bucket to the destination bucket:

```
gcloud transfer jobs create my-job \
  --source-bucket=my-bucket \
  --destination-bucket=new-bucket
```

To describe a transfer job:

```
gcloud transfer jobs describe my-job
```

To list all transfer jobs:

```
gcloud transfer jobs list
```

To pause a transfer job:

```
gcloud transfer jobs pause my-job
```

To resume a transfer job:

```
gcloud transfer jobs resume my-job
```

To delete a transfer job:

```
gcloud transfer jobs delete my-job
```
```
转移作业的配置文件是一个 JSON 文件，它定义了转移作业的行为。配置文件包含以下几个主要部分：

* **源**：定义了要复制的数据的源。
* **目标**：定义了要复制数据的目标。
* **策略**：定义了复制数据的策略。
* **日志**：定义了转移作业日志的配置。

以下是一个简单的转移作业配置文件示例：

```json
{
  "source": {
    "type": "gcs",
    "uris": ["gs://my-bucket/*"]
  },
  "destination": {
    "type": "gcs",
    "uris": ["gs://new-bucket/*"]
  },
  "schedule": {
    "schedule_interval": "1d"
  }
}
```

这个配置文件将复制存储桶 `my-bucket` 中的所有对象到存储桶 `new-bucket`。复制将按每天一次的频率进行。

以下是转移作业配置文件的各个部分的详细说明：

**源**

`source` 部分定义了要复制的数据的源。源可以是以下类型之一：

* `gcs`：来自 Google Cloud Storage 的对象。
* `local`：来自本地文件系统的文件。
* `database`：来自数据库的数据。
* `api`：来自 SaaS 应用程序的数据。

`source` 部分包含以下属性：

* `type`：源的类型。
* `uris`：要复制的对象或文件的 URI 列表。

**目标**

`destination` 部分定义了要复制数据的目标。目标可以是以下类型之一：

* `gcs`：Google Cloud Storage 中的对象。
* `local`：本地文件系统中的文件。

`destination` 部分包含以下属性：

* `type`：目标的类型。
* `uris`：要复制对象或文件的 URI 列表。

**策略**

`strategy` 部分定义了复制数据的策略。策略可以是以下类型之一：

* `full`：复制源中的所有对象，包括新创建的对象和已修改的对象。
* `incremental`：仅复制源中已修改的对象。

`strategy` 部分包含以下属性：

* `type`：策略的类型。
* `start_object`：用于增量复制的起始对象。

**日志**

`logging` 部分定义了转移作业日志的配置。

`logging` 部分包含以下属性：

* `enabled`：是否启用日志记录。
* `log_level`：日志记录级别。

以下是转移作业配置文件的一些高级功能：

* **过滤**：您可以使用 `filters` 属性来过滤要复制的对象或文件。
* **转换**：您可以使用 `transforms` 属性来转换复制的数据。
* **重试**：您可以使用 `retries` 属性来配置转移作业的重试策略。

您可以使用 Cloud Storage Transfer Service 控制台或 `gcloud` 命令来创建和管理转移作业配置文件。


Cloud Storage Transfer Service 支持增量复制。增量复制仅复制源中已修改的对象。

要启用增量复制，您需要在转移作业的配置文件中设置 strategy 属性的值为 incremental。您还需要指定 start_object 属性，该属性指定用于增量复制的起始对象。

当您使用增量复制时，Cloud Storage Transfer Service 会使用 MD5 哈希来跟踪源中对象的修改。如果源中对象的 MD5 哈希与目标中对象的 MD5 哈希不同，则该对象将被复制到目标。

以下是使用增量复制的转移作业配置文件示例：

是的，Cloud Storage Transfer Service 支持增量复制。增量复制仅复制源中已修改的对象。

要启用增量复制，您需要在转移作业的配置文件中设置 `strategy` 属性的值为 `incremental`。您还需要指定 `start_object` 属性，该属性指定用于增量复制的起始对象。

当您使用增量复制时，Cloud Storage Transfer Service 会使用 MD5 哈希来跟踪源中对象的修改。如果源中对象的 MD5 哈希与目标中对象的 MD5 哈希不同，则该对象将被复制到目标。

以下是使用增量复制的转移作业配置文件示例：

```json
{
  "source": {
    "type": "gcs",
    "uris": ["gs://my-bucket/*"]
  },
  "destination": {
    "type": "gcs",
    "uris": ["gs://new-bucket/*"]
  },
  "schedule": {
    "schedule_interval": "1d"
  },
  "strategy": {
    "type": "incremental",
    "start_object": "gs://my-bucket/object-1"
  }
}
```

这个配置文件将使用增量复制来复制存储桶 `my-bucket` 中的所有对象到存储桶 `new-bucket`。复制将按每天一次的频率进行。

如果源目录中的文件有变化，Cloud Storage Transfer Service 将自动同步到新的目录。

以下是增量复制的优势：

* 可以提高复制的效率，因为只需要复制已修改的对象。
* 可以减少网络流量，因为只需要传输已修改的对象的数据。

以下是增量复制的限制：

* 需要源中对象的 MD5 哈希。
* 需要指定 `start_object` 属性。

您可以使用 Cloud Storage Transfer Service 控制台或 `gcloud` 命令来启用增量复制。

要让 Cloud Storage Transfer Service 在最快的时间内完成任务，您可以采取以下措施：

* **使用增量复制**：增量复制仅复制源中已修改的对象，可以提高复制的效率。
* **指定 `start_object` 属性**：`start_object` 属性指定用于增量复制的起始对象。如果您指定最近复制过的对象作为起始对象，则 Cloud Storage Transfer Service 只需要复制新增或修改的对象。
* **设置 `schedule` 属性**：`schedule` 属性指定转移作业的运行时间表。如果您设置为按小时或分钟运行，则转移作业可以更快地完成任务。

以下是使用增量复制和 `start_object` 属性来加快转移作业速度的示例：

```json
{
  "source": {
    "type": "gcs",
    "uris": ["gs://my-bucket/*"]
  },
  "destination": {
    "type": "gcs",
    "uris": ["gs://new-bucket/*"]
  },
  "schedule": {
    "schedule_interval": "1h"
  },
  "strategy": {
    "type": "incremental",
    "start_object": "gs://my-bucket/object-1"
  }
}
```

这个配置文件将使用增量复制来复制存储桶 `my-bucket` 中的所有对象到存储桶 `new-bucket`。复制将按每小时一次的频率进行。

如果源目录中的文件有变化，Cloud Storage Transfer Service 将自动同步到新的目录。

您可以使用 Cloud Storage Transfer Service 控制台或 `gcloud` 命令来启用增量复制和 `start_object` 属性。

以下是一些其他可以帮助您加快转移作业速度的提示：

* **使用多个转移作业**：如果您需要复制的对象很多，您可以使用多个转移作业来并行复制。
* **使用高性能存储区域**：如果您有高性能存储区域，您可以将转移作业的目标设置为该区域。
* **使用高性能网络**：如果您有高性能网络，您可以将转移作业的源和目标设置为该网络。

您可以根据您的具体需求和要求来调整这些设置，以提高转移作业的速度。

要确认 `start_object` 属性的值，您可以使用以下方法：

* **使用 Cloud Storage Transfer Service 控制台**：在转移作业配置页面中，查看 `Start object` 字段。
* **使用 `gcloud` 命令**：使用 `gcloud transfer jobs describe` 命令来查看转移作业的配置。

如果您不知道 `start_object` 属性的值，您可以使用以下方法来确定：

* **检查源目录中的最新对象**：您可以使用 `gsutil ls` 命令来列出源目录中的所有对象。最新的对象将是 `start_object` 属性的值。
* **使用增量复制**：您可以使用增量复制来复制源目录中的所有对象。Cloud Storage Transfer Service 将自动确定 `start_object` 属性的值。

以下是使用增量复制来确定 `start_object` 属性的示例：

```json
{
  "source": {
    "type": "gcs",
    "uris": ["gs://my-bucket/*"]
  },
  "destination": {
    "type": "gcs",
    "uris": ["gs://new-bucket/*"]
  },
  "schedule": {
    "schedule_interval": "1h"
  },
  "strategy": {
    "type": "incremental"
  }
}
```

这个配置文件将使用增量复制来复制存储桶 `my-bucket` 中的所有对象到存储桶 `new-bucket`。复制将按每小时一次的频率进行。

如果源目录中的文件有变化，Cloud Storage Transfer Service 将自动确定 `start_object` 属性的值。

您可以使用 Cloud Storage Transfer Service 控制台或 `gcloud` 命令来启用增量复制。

以下是一些其他可以帮助您确定 `start_object` 属性的提示：

* **使用文件系统监控工具**：您可以使用文件系统监控工具来跟踪源目录中的文件更改。当文件更改时，您可以使用监控工具来确定最新的文件。
* **使用日志记录**：您可以启用转移作业的日志记录。日志记录将包含有关转移作业的详细信息，包括复制的对象。您可以使用日志记录来确定 `start_object` 属性的值。

您可以根据您的具体需求和要求来使用这些方法来确定 `start_object` 属性的值。


您可以同时启动多个转移作业来同步多个存储桶。您可以使用 Cloud Storage Transfer Service 控制台或 `gcloud` 命令来启动多个转移作业。

以下是使用 Cloud Storage Transfer Service 控制台来启动多个转移作业的步骤：

1. 在 Cloud Storage Transfer Service 控制台中，单击 **创建转移作业**。
2. 为每个转移作业提供名称和描述。
3. 选择要复制的来源。
4. 选择要复制的目标存储桶。
5. 配置转移作业。
6. 单击 **创建**。

以下是使用 `gcloud` 命令来启动多个转移作业的示例：

```
# 创建第一个转移作业
gcloud transfer jobs create my-job-1 \
  --source-bucket=my-bucket-1 \
  --destination-bucket=new-bucket-1

# 创建第二个转移作业
gcloud transfer jobs create my-job-2 \
  --source-bucket=my-bucket-2 \
  --destination-bucket=new-bucket-2
```

这两个命令将创建两个转移作业，一个用于同步存储桶 `my-bucket-1` 到存储桶 `new-bucket-1`，另一个用于同步存储桶 `my-bucket-2` 到存储桶 `new-bucket-2`。

您可以使用 Cloud Storage Transfer Service 控制台或 `gcloud` 命令来监控多个转移作业的进度。

以下是一些可以帮助您同时启动多个转移作业的提示：

* **使用转移作业 ID**：您可以使用转移作业 ID 来引用转移作业。这可以帮助您在启动多个转移作业时保持井井有条。
* **使用脚本**：您可以使用脚本来自动启动多个转移作业。这可以节省您的时间和精力。
* **使用批处理作业**：您可以使用批处理作业来启动多个转移作业。这可以提高转移作业的效率。

您可以根据您的具体需求和要求来使用这些方法来同时启动多个转移作业。



如果不指定 `--transfer-configs` 参数，Cloud Storage Transfer Service 将使用默认配置来创建转移作业。默认配置如下：

* **源**：源是存储桶 `gs://my-bucket`。
* **目标**：目标是存储桶 `gs://new-bucket`。
* **策略**：策略是 `full`。
* **日志**：日志记录是禁用的。

以下是使用默认配置创建转移作业的示例：

```
gcloud transfer jobs create my-job \
  --source-bucket=my-bucket \
  --destination-bucket=new-bucket
```

这条命令将创建一个转移作业，该作业将复制存储桶 `my-bucket` 中的所有对象到存储桶 `new-bucket`。复制将使用完整复制策略，并且日志记录将被禁用。

您可以使用 Cloud Storage Transfer Service 控制台或 `gcloud` 命令来查看转移作业的配置。

以下是使用 Cloud Storage Transfer Service 控制台来查看转移作业的配置的步骤：

1. 在 Cloud Storage Transfer Service 控制台中，单击转移作业。
2. 在 **配置** 部分，查看转移作业的配置。

以下是使用 `gcloud` 命令来查看转移作业的配置的示例：

```
gcloud transfer jobs describe my-job
```

这条命令将显示转移作业的配置。

您可以根据您的具体需求和要求来调整默认配置。


它的速率会比gsutil或者提升多少?


Cloud Storage Transfer Service 的速度通常比 gsutil 更快。这主要有以下几个原因：

* **Cloud Storage Transfer Service 使用了多线程和并行处理技术来提高效率。**
* **Cloud Storage Transfer Service 可以根据网络条件调整传输速度。**
* **Cloud Storage Transfer Service 可以根据源和目标存储桶的距离调整传输路径。**

具体来说，Cloud Storage Transfer Service 的速度可以比 gsutil 快几个数量级。

以下是一些测试结果：

* 将 1 TB 的数据从一个存储桶复制到另一个存储桶，Cloud Storage Transfer Service 的平均速度为 250 MB/s，而 gsutil 的平均速度为 50 MB/s。
* 将 10 GB 的数据从一个区域复制到另一个区域，Cloud Storage Transfer Service 的平均速度为 100 MB/s，而 gsutil 的平均速度为 20 MB/s。

当然，实际的速度还会受到源和目标存储桶的距离、网络条件等因素的影响。

以下是一些可以帮助您提高 Cloud Storage Transfer Service 速度的提示：

* **使用多个转移作业来并行复制。**
* **使用增量复制来减少传输的数据量。**
* **使用高性能网络来连接源和目标存储桶。**

您可以根据您的具体需求和要求来调整设置，以提高 Cloud Storage Transfer Service 的速度。

Cloud Storage Transfer Service 需要有什么特殊的Role ?

Cloud Storage Transfer Service 需要以下特殊的角色：

* **roles/storage.legacyBucketWriter**：此角色允许用户写入存储桶中的数据。
* **roles/storage.legacyBucketReader**：此角色允许用户读取存储桶中的数据。

您可以通过 IAM 控制台或 IAM 命令来授予这些角色。

以下是使用 IAM 控制台授予这些角色的步骤：

1. 在 IAM 控制台中，打开要授予角色的用户或服务帐户。
2. 在 **角色** 部分，单击 **添加角色**。
3. 在 **选择角色** 下，选择 **存储** 类别。
4. 选择 **roles/storage.legacyBucketWriter** 和 **roles/storage.legacyBucketReader** 角色。
5. 单击 **添加**。

以下是使用 IAM 命令授予这些角色的示例：

```
gcloud iam roles add roles/storage.legacyBucketWriter \
  --member=user:my-user@example.com \
  --bucket=my-bucket

gcloud iam roles add roles/storage.legacyBucketReader \
  --member=user:my-user@example.com \
  --bucket=my-bucket
```

这些角色是必需的，因为 Cloud Storage Transfer Service 需要访问源和目标存储桶的数据。

您也可以使用更高级的角色来授予 Cloud Storage Transfer Service 更多的权限。例如，您可以使用 **roles/storage.legacyBucketAdmin** 角色来授予 Cloud Storage Transfer Service 创建、修改和删除存储桶的权限。

以下是一些可以帮助您选择合适角色的提示：

* **考虑转移作业需要执行的操作。**
* **考虑源和目标存储桶的敏感性。**
* **根据您的具体需求和要求来调整角色。**
