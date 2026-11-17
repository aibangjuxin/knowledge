在GitHub上删除fork的仓库非常简单，只需几步即可完成：

    1.	打开你的GitHub账户并导航到fork的仓库。  找到你想删除的fork仓库，进入该仓库的主页面。
    2.	进入仓库设置。 在仓库页面的右侧，找到”Settings”标签页，点击进入。
    3.	滚动到页面底部。  在设置页面的最下方，你会找到”Danger Zone”区域。
    4.	删除仓库。  在”Danger Zone”区域，点击”Delete this repository”按钮。
    5.	确认删除操作。 系统会要求你输入仓库的名称来确认删除操作。这有助于防止意外删除。  输入完整的仓库名称（例如：your-username/repository-name），然后点击”I understand the consequences, delete this repository”按钮。

示例：

假设你的GitHub用户名是myusername，fork的仓库名称是original-repo，那么你需要输入myusername/original-repo来确认删除。

注意：

    •	删除操作是不可逆的。一旦删除，仓库及其所有内容将永久丢失。
    •	你只能删除自己fork的仓库，不能删除原始仓库。

```mermaid
graph LR
    A[打开GitHub并找到fork的仓库] --> B(进入仓库设置);
    B --> C{滚动到页面底部 "Danger Zone"};
    C --> D[点击 "Delete this repository"];
    D --> E[输入仓库名称确认];
    E --> F((仓库已删除));
```

```

```
