在 Airflow 中，DAG（Directed Acyclic Graph，有向无环图）是工作流的核心概念。一个 DAG 是一系列任务的有序集合，这些任务会按照特定的依赖关系执行。DAG 确保任务按照依赖顺序运行，从而实现复杂的工作流调度。

1. Airflow DAG 的核心概念

•	DAG：有向无环图，定义了一组任务以及任务之间的依赖关系。

•	Task：DAG 中的基本操作单元，可以是一个 Python 函数、Bash 脚本、SQL 查询等。

•	Operator：定义任务执行的操作，例如 PythonOperator、BashOperator 等。

•	Dependencies（依赖关系）：任务之间的依赖关系，即 Task A 需要在 Task B 之前完成，Airflow 会按照依赖顺序调度任务执行。

2. DAG 示例

以下是一个典型的 Airflow DAG 例子，表示在每日凌晨定时执行以下任务：

	1.	提取数据。

	2.	清理数据。

	3.	加载数据。

这些任务有依赖关系，需要按顺序执行。
```python
from airflow import DAG
from airflow.operators.python_operator import PythonOperator
from datetime import datetime

# 定义任务执行的函数
def extract_data():
    print("Extracting data...")

def clean_data():
    print("Cleaning data...")

def load_data():
    print("Loading data...")

# 定义 DAG
dag = DAG(
    'data_pipeline',
    description='A simple data pipeline',
    schedule_interval='0 0 * * *',  # 每日午夜执行
    start_date=datetime(2023, 11, 12),
    catchup=False
)

# 定义任务
extract_task = PythonOperator(task_id='extract', python_callable=extract_data, dag=dag)
clean_task = PythonOperator(task_id='clean', python_callable=clean_data, dag=dag)
load_task = PythonOperator(task_id='load', python_callable=load_data, dag=dag)

# 设置任务依赖关系
extract_task >> clean_task >> load_task
```
在上面的例子中：

	•	extract_task 是第一个任务，提取数据。

	•	clean_task 是第二个任务，清理数据，依赖于 extract_task 完成。

	•	load_task 是第三个任务，加载数据，依赖于 clean_task 完成。

3. 示例图示

以下是该 DAG 的可视化流程图表示：
```mermaid
graph TD
    A[extract_task: 提取数据] --> B[clean_task: 清理数据]
    B --> C[load_task: 加载数据]
```
4. Airflow DAG 的运行流程

Airflow DAG 会根据任务依赖关系依次调度和执行各任务，确保每个任务都在其依赖的任务完成后再运行。例如，上述 DAG 会先执行 extract_task，然后 clean_task，最后执行 load_task。这样可以确保数据流处理按顺序完成。


在 Markdown 中更好地展示 DAG 图表，可以通过以下几种方式来优化图形效果，使其更符合 DAG 特性：

1. Mermaid with Subgraphs

通过使用 Mermaid 的子图（subgraph） 功能，可以进一步分隔 DAG 的各阶段，增加层次感，提升可读性。Mermaid 支持 DAG 图，但需要明确节点间的方向，并避免环形关系。
```mermaid
graph TD
    subgraph ETL Process
        A[Extract Task] --> B[Clean Task] --> C[Load Task]
    end
```
2. 使用样式和颜色提升可读性

为每个任务添加颜色或样式，可以让图表更具区分度和视觉效果。示例代码如下：
```mermaid
graph TD
    style A fill:#f9f,stroke:#333,stroke-width:2px
    style B fill:#bbf,stroke:#333,stroke-width:2px
    style C fill:#8fb,stroke:#333,stroke-width:2px
    
    A[Extract Task] --> B[Clean Task]
    B --> C[Load Task]
```
3. 加入标注说明

如果每个任务执行的内容不一，可以在图中加入注释（例如任务名称或关键参数），以增强图表的语义性：
```mermaid
graph TD
    A[Extract Task: 数据提取] --> B[Clean Task: 数据清理]
    B --> C[Load Task: 数据加载]
    %% A 的说明
    A:::task
    %% B 的说明
    B:::task
    %% C 的说明
    C:::task

    classDef task fill:#ffd700,stroke:#000,stroke-width:2px;
```
4. DAG 表现方式的优劣

在 Markdown 中直接使用 Mermaid 可以实现较为简单的 DAG 展示，但在复杂工作流的情况下，不够灵活。对于更复杂的 DAG，可能考虑通过 Airflow Web 界面或外部工具 导出图像，以获得更完整和易读的展示。
