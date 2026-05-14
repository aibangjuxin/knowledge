在HTTP请求中，要判断 URL 中的一部分是 endpoint 还是 参数，需要看 URL 的结构和语义。以下是对这两部分的详细解释：

1. Endpoint (资源路径)
	•	定义：
Endpoint 是用于标识某个资源的固定路径部分，通常不包含查询字符串，也不随请求改变。它定义了用户或客户端访问的具体资源。
	•	特点：
	•	通常是固定的或预定义的。
	•	定义了访问哪个资源（比如用户、订单、产品等）。
	•	不依赖具体的请求参数。
	•	举例：
假设你的 URL 是：

https://www.abc.com/123/

	•	https://www.abc.com 是域名。
	•	/123/ 是一个可能的 endpoint，它表明客户端正在访问资源 123（如某用户的 ID 或某个特定实体）。

2. 参数
	•	定义：
参数是用来传递给服务器的动态数据。参数可以分为两种：
	•	路径参数（Path Parameters）：嵌入在 URL 路径中，用来标识某个资源的具体实例。
	•	查询参数（Query Parameters）：跟在 ? 后面，以键值对的形式存在。
	•	特点：
	•	路径参数 是资源路径的一部分（如 /123 中的 123 可能是一个路径参数，表示资源的 ID）。
	•	查询参数 通常是非固定的，位于 URL 的末尾，用于控制资源的筛选、排序或其他动态行为。
	•	举例：
	•	URL 中的 https://www.abc.com/123/abcd：
	•	如果 123 是资源 ID，而 abcd 是另一个层级的资源（如子资源），abcd 也是路径参数。
	•	查询参数举例：

https://www.abc.com/123?type=random&value=abcd

	•	这里的 type 和 value 是查询参数。

分析随机字符是否是参数还是 endpoint

判断依据是：
	1.	看是否包含 ?：
	•	https://www.abc.com/123?abcd=xyz，abcd=xyz 是查询参数。
	•	https://www.abc.com/123/abcd，abcd 是路径参数。
	2.	语义含义：
	•	如果 /abcd 是资源的一部分，它是 endpoint 的一部分。
	•	如果 /abcd 表示动态数据，通常可以看作路径参数。
	3.	API 文档或实现逻辑：
	•	API 文档通常会清楚地说明路径中哪些是固定资源路径，哪些是动态参数。

举例分析

假设以下 URL：

示例 1：https://www.abc.com/123/abcd
	•	/123/abcd 是资源路径，其中 123 和 abcd 都是路径参数。
	•	这是一个 REST 风格的路径，通常表示访问某个 ID 为 123 的资源的子资源 abcd。

示例 2：https://www.abc.com/123?name=abcd
	•	/123 是 endpoint，name=abcd 是查询参数，表示动态筛选或过滤条件。

示例 3：https://www.abc.com/products/56789
	•	/products/56789 中，products 是资源集合，56789 是路径参数，表示产品 ID。

示例 4：https://www.abc.com/users?active=true&role=admin
	•	/users 是资源路径。
	•	active=true 和 role=admin 是查询参数，表示筛选活跃状态的管理员用户。

总结：如何判断？
	1.	如果是静态或预定义的，通常是 endpoint。
	2.	如果动态变化（如 ID、标识符），通常是路径参数或查询参数。
	3.	具体含义需要结合 API 文档或具体实现。

可以用以下公式理解：

URL = [Scheme] + [Domain] + [Endpoint(Path + Path Params)] + [? Query Params]
