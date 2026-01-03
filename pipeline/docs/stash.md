在 Jenkins Pipeline 中，**stash** 和 **unstash** 是用于在不同节点之间传输文件的功能。具体来说，**stash** 用于将当前目录下的文件暂时存储起来，而 **unstash** 则用于在需要时将这些文件取回。以下是详细的解释和应用场景：

## 概念

- **stash**: 将当前目录下的文件或目录压缩并存储起来，通常用于在不同的 Pipeline 步骤之间传递文件。
- **unstash**: 从存储中取回之前存储的文件或目录，并解压到当前目录。

## 应用场景

1. **跨节点传递文件**:
   在 Jenkins Pipeline 中，可能需要在不同的节点（例如不同的构建服务器）之间传递文件。例如，在一个节点上进行代码的检出和编译，然后在另一个节点上进行测试。通过 stash 和 unstash，可以方便地在这些节点之间传递构建工件或其他文件。

   ```yaml
   node('master') {
       deleteDir()
       git url: 'https://github.com/your-repo.git'
       stash name: 'source_code'
   }
   
   node('slave') {
       deleteDir()
       unstash 'source_code'
       sh 'gradle test'
   }
   ```

2. **避免重启挂起**:
   在长时间运行的 Pipeline 中，可能会遇到 Jenkins 重启的情况。通过 stash，可以在重启之前保存当前的工作状态，重启后再通过 unstash 恢复，从而避免任务挂起。

3. **分阶段构建**:
   在多阶段构建过程中，可以将每个阶段的输出通过 stash 保存起来，供后续阶段使用。例如，编译阶段生成的二进制文件可以通过 stash 保存，测试阶段通过 unstash 取回进行测试。

4. **缓存依赖**:
   在构建过程中，可能需要下载大量的依赖库。通过 stash，可以将这些依赖库缓存起来，避免每次构建都重新下载，从而加快构建速度。

## 示例

以下是一个简单的 Pipeline 示例，展示了如何使用 stash 和 unstash 在不同节点之间传递文件：

```groovy
pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps {
                script {
                    node('master') {
                        deleteDir()
                        git url: 'https://github.com/your-repo.git'
                        stash name: 'source_code'
                    }
                }
            }
        }
        stage('Test') {
            steps {
                script {
                    node('slave') {
                        deleteDir()
                        unstash 'source_code'
                        sh 'gradle test'
                    }
                }
            }
        }
    }
}
```

在这个示例中，代码首先在 `master` 节点上检出并存储（stash），然后在 `slave` 节点上取回（unstash）并进行测试。

通过上述方式，stash 和 unstash 提供了一种灵活且高效的方式来管理和传递构建过程中产生的文件和工件。

Citations:
[1] https://arasio.hatenablog.com/entry/2016/10/19/001944
[2] https://recruit.gmo.jp/engineer/jisedai/blog/jenkins-2-pipeline-as-code/
