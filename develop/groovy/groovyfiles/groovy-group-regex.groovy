Groovy 可以通过 GitHub API 获取 pull request 的评论信息和审核信息。在获取这些信息后，可以使用 Groovy 代码来解析它们以查找某个组的成员是否进行了评论或审核。
以下是一些示例代码，可以用来获取 pull request 的评论和审核信息，并检查是否来自特定组的成员：
获取 pull request 的评论信息：
import groovy.json.JsonSlurper
import org.apache.http.client.methods.HttpGet
import org.apache.http.impl.client.HttpClientBuilder
import org.apache.http.util.EntityUtils

def getPullRequestComments(String owner, String repo, Integer pullRequestNumber) {
    def url = "https://api.github.com/repos/${owner}/${repo}/pulls/${pullRequestNumber}/comments"
    def client = HttpClientBuilder.create().build()
    def request = new HttpGet(url)
    request.setHeader("Authorization", "Bearer <token>")
    def response = client.execute(request)
    def json = new JsonSlurper().parseText(EntityUtils.toString(response.entity))
    return json
}

def comments = getPullRequestComments("owner", "repo", 123)
comments.each { comment ->
    def user = comment.user.login
    def body = comment.body
    def groupMembers = ["group_member_1", "group_member_2", "group_member_3"]
    if (groupMembers.contains(user)) {
        println("The comment '${body}' was made by a member of the group.")
    }
}

获取 pull request 的审核信息
import groovy.json.JsonSlurper
import org.apache.http.client.methods.HttpGet
import org.apache.http.impl.client.HttpClientBuilder
import org.apache.http.util.EntityUtils

def getPullRequestReviews(String owner, String repo, Integer pullRequestNumber) {
    def url = "https://api.github.com/repos/${owner}/${repo}/pulls/${pullRequestNumber}/reviews"
    def client = HttpClientBuilder.create().build()
    def request = new HttpGet(url)
    request.setHeader("Authorization", "Bearer <token>")
    def response = client.execute(request)
    def json = new JsonSlurper().parseText(EntityUtils.toString(response.entity))
    return json
}

def reviews = getPullRequestReviews("owner", "repo", 123)
reviews.each { review ->
    def user = review.user.login
    def state = review.state
    def groupMembers = ["group_member_1", "group_member_2", "group_member_3"]
    if (groupMembers.contains(user)) {
        println("The review is '${state}' and was made by a member of the group.")
    }
}

在这些示例中，您需要替换 <token>, owner, repo, pullRequestNumber 和 group_member_X，以便与您自己的 GitHub 帐户和存储库匹配。请注意，您需要提供一个有效的 GitHub 访问令牌以进行 API 调用。

使用groovy 对获取的review.json文件分析 是否某个组的成员进行了评论或者审核

可以使用Groovy语言读取review.json文件并解析其中的内容，判断是否某个组的成员进行了评论或审核。以下是一个示例代码：
import groovy.json.JsonSlurper

// 读取review.json文件并解析成JSON对象
def jsonSlurper = new JsonSlurper()
def reviewJson = jsonSlurper.parseText(new File("review.json").text)

// 获取评论或审核人列表
def reviewers = []
reviewJson.each { review ->
    if (review.state == "COMMENTED" || review.state == "APPROVED") {
        reviewers << review.user.login
    }
}

// 判断某个组的成员是否进行了评论或审核
def groupName = "example-group"
def isGroupReviewer = reviewers.any { reviewer ->
    reviewer in groupName
}

// 输出结果
println "Group $groupName has " + (isGroupReviewer ? "" : "not ") + "reviewed or commented on this review."

在这个示例代码中，我们使用Groovy语言中的JsonSlurper类读取review.json文件，并将其解析成JSON对象。然后，我们遍历每个审核记录，将评论或审核的人添加到一个名为reviewers的列表中。接下来，我们判断列表中是否存在来自指定组的成员，
如果存在则表示该组的成员进行了评论或审核，否则表示没有进行评论或审核。最后，我们输出结果


groovy 分析获取的github review json文件,然后判断approve或者commont的用户是不是定义的特殊组内的成员

To analyze the GitHub review JSON file and determine if the approving or commenting user is a member of a specific group, you can use the following steps:

1. Parse the JSON file: Use a JSON parser to parse the review JSON file and extract the relevant information, such as the approving and commenting users.

2. Check if the user is a member of the group: Use the GitHub API to check if the user is a member of the specific group. You can do this by sending a GET request to the following endpoint: https://api.github.com/orgs/{org}/teams/{team_slug}/memberships/{username}. Replace {org} with the name of your organization, {team_slug} with the slug of the team you want to check membership for, and {username} with the username of the user you want to check.

3. Handle the response: The response from the API will contain a state field, which can be active, pending, or inactive. If the user is a member of the group, the state will be active. If the user is not a member of the group, the state will be pending or inactive.

Here's an example of how you can implement this in Groovy:
import groovy.json.JsonSlurper
import java.net.URL

def json = new JsonSlurper().parseText(reviewJson)

def approvingUser = json.pull_request.user.login
def commentingUser = json.user.login

def isApprovingUserInGroup = isUserInGroup(approvingUser, "my-group")
def isCommentingUserInGroup = isUserInGroup(commentingUser, "my-group")

def isUserInGroup(username, groupSlug) {
    def url = "https://api.github.com/orgs/my-org/teams/${groupSlug}/memberships/${username}"
    def connection = new URL(url).openConnection()
    connection.setRequestProperty("Authorization", "Bearer ${accessToken}")
    def response = new JsonSlurper().parse(connection.getInputStream())
    return response.state == "active"
}

Replace reviewJson with the JSON string you want to parse, my-group with the slug of the group you want to check membership for, and accessToken with your GitHub access token.

可以使用Groovy的JSON解析器来解析GitHub Review JSON文件，并使用Groovy的集合和条件语句来判断审批或评论的用户是否属于特定组。

以下是一个示例代码，它假设你已经从GitHub API获取了一个Review JSON文件，并将其存储在一个名为`reviewJson`的字符串变量中。它还假设你已经定义了一个名为`specialGroup`的字符串列表，其中包含特殊组的成员。

```
import groovy.json.JsonSlurper

// 解析JSON文件
def review = new JsonSlurper().parseText(reviewJson)

// 获取审批和评论
def approvals = review.events.findAll { it.event == 'APPROVE' }
def comments = review.events.findAll { it.event == 'COMMENT' }

// 获取所有审批和评论的用户
def users = (approvals + comments).collect { it.user.login }

// 检查特殊组的成员是否在用户列表中
def isSpecialGroupMember = users.any { specialGroup.contains(it) }

// 打印结果
if (isSpecialGroupMember) {
    println "At least one member of the special group has approved or commented on this review"
} else {
    println "No members of the special group have approved or commented on this review"
}
```

这个代码首先使用`JsonSlurper`解析JSON文件，并使用`findAll`方法获取所有的审批和评论。然后，它使用`collect`方法获取所有审批和评论的用户，并使用`any`方法检查特殊组的成员是否在用户列表中。最后，它打印结果。



Using groovy get github review request .and make sure the review owner at special group
To get GitHub review requests using Groovy, you can use the GitHub API to fetch the pull requests that have review requests. Here's an example code block that demonstrates how to do this:
import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import org.apache.http.client.methods.HttpGet
import org.apache.http.impl.client.HttpClients
import org.apache.http.util.EntityUtils

// Set up the GitHub API endpoint and authentication
def apiUrl = "https://api.github.com"
def authToken = "YOUR_AUTH_TOKEN"
def headers = ["Authorization": "token ${authToken}"]

// Get the pull requests with review requests
def url = "${apiUrl}/search/issues?q=is:pr+review-requested:${YOUR_GITHUB_USERNAME}"
def client = HttpClients.createDefault()
def request = new HttpGet(url)
headers.each { header ->
    request.addHeader(header.key, header.value)
}
def response = client.execute(request)
def responseBody = EntityUtils.toString(response.getEntity())
def jsonSlurper = new JsonSlurper()
def json = jsonSlurper.parseText(responseBody)

// Filter the pull requests by review owner at special group
def specialGroup = "SPECIAL_GROUP_NAME"
def filteredPullRequests = json.items.findAll { pr ->
    pr.requested_reviewers.any { reviewer ->
        reviewer.login in specialGroup
    }
}

// Print the filtered pull requests
println(JsonOutput.prettyPrint(JsonOutput.toJson(filteredPullRequests)))
This code block uses the GitHub API to search for pull requests that have review requests for your GitHub username. It then filters the pull requests by the review owner at a special group, which you can specify by setting the specialGroup variable. Finally, it prints the filtered pull requests in a pretty-printed JSON format.



Here's an example of how to use Groovy to get GitHub pull requests that have review requests and ensure that the reviewers are in a specific group:

```groovy
@Grab('org.kohsuke.github:github-api:1.123')

import org.kohsuke.github.*

def github = GitHub.connect()

// Replace with your GitHub username and repository name
def user = 'my-username'
def repo = 'my-repo'

// Get the repository object
def repository = github.getRepository("$user/$repo")

// Get all pull requests with review requests
def pullRequests = repository.queryPullRequests()
    .state(GHIssueState.OPEN)
    .reviewRequested()
    .list()

// Replace with the name of the group you want to check for
def groupName = 'my-group'

// Loop through each pull request
pullRequests.each { pullRequest ->
    // Get the list of requested reviewers
    def requestedReviewers = pullRequest.getRequestedReviewers()

    // Loop through each requested reviewer
    requestedReviewers.each { reviewer ->
        // Get the user object for the reviewer
        def user = github.getUser(reviewer.getLogin())

        // Check if the user is a member of the specified group
        if (user.isMemberOf(groupName)) {
            println "Pull request #${pullRequest.getNumber()} has a review request from a member of $groupName"
        }
    }
}
```

In this example, we first connect to the GitHub API using the `GitHub.connect()` method. We then get the repository object for the specified repository using the `github.getRepository()` method.

Next, we use the `queryPullRequests()` method to get all open pull requests with review requests. We then loop through each pull request and get the list of requested reviewers using the `getRequestedReviewers()` method.

For each requested reviewer, we get the user object using the `github.getUser()` method. We then check if the user is a member of the specified group using the `isMemberOf()` method. If the user is a member of the group, we print a message indicating that the pull request has a review request from a member of the group.


Here's an example of how you can use Groovy to check if a pull request review status is "APPROVED" and ensure that the reviewer is a member of a specific team:

import groovy.json.JsonSlurper
import javax.net.ssl.HttpsURLConnection

def owner = "your-username"
def repo = "your-repository"
def pullRequestNumber = 1 // Replace with the number of your pull request
def teamSlug = "your-team-slug" // Replace with the slug of your team

// Set up the API URL
def apiUrl = "https://api.github.com/repos/$owner/$repo/pulls/$pullRequestNumber/reviews"

// Set up the API request
def connection = apiUrl.toURL().openConnection() as HttpsURLConnection
connection.setRequestProperty("Accept", "application/vnd.github.v3+json")

// Parse the API response
def reviews = new JsonSlurper().parse(connection.inputStream)

// Loop through the reviews and check if any are approved by a team member
def approvedByTeamMember = false
reviews.each { review ->
    if (review.state == "APPROVED") {
        def reviewer = review.user.login
        def teamMembers = getTeamMembers(teamSlug)
        if (teamMembers.contains(reviewer)) {
            approvedByTeamMember = true
        }
    }
}

// Print the result
if (approvedByTeamMember) {
    println("The pull request has been approved by a member of the $teamSlug team.")
} else {
    println("The pull request has not been approved by a member of the $teamSlug team.")
}

// Helper function to get the members of a team
def getTeamMembers(teamSlug) {
    def apiUrl = "https://api.github.com/orgs/$owner/teams/$teamSlug/members"
    def connection = apiUrl.toURL().openConnection() as HttpsURLConnection
    connection.setRequestProperty("Accept", "application/vnd.github.v3+json")
    def members = new JsonSlurper().parse(connection.inputStream)
    return members.collect { it.login }
}
Note that this code assumes that you have already authenticated with GitHub and have the necessary permissions to access the pull request and team information. You may need to modify the API URLs or add authentication
 headers depending on your use case.


Here's an example of how to use utilsFile().parseJsonByFile() to parse the response from the GitHub API and check if the review status is "APPROVED" and if the approver is in a list defined in the script:
def owner = "owner"
def repo = "repo"
def pullNumber = "1"
def reviewStatus = "APPROVED"
def approvers = ["user1", "user2", "user3"]

def command = "curl -H 'Accept: application/vnd.github.v3+json' https://api.github.com/repos/${owner}/${repo}/pulls/${pullNumber}/reviews"
def process = command.execute()
process.waitFor()
def response = process.text

def reviews = utilsFile().parseJsonByFile(response)

def approvedReview = reviews.find { it.state == reviewStatus }
if (approvedReview) {
  def approver = approvedReview.user.login
  if (approvers.contains(approver)) {
    println("The pull request has been approved by an approver in the list.")
  } else {
    println("The pull request has been approved, but the approver is not in the list.")
  }
} else {
  println("The pull request has not been approved.")
}
This script is very similar to the previous one, but instead of using JsonSlurper to parse the JSON response, it uses utilsFile().parseJsonByFile(). This method takes a string containing JSON data as input and returns a parsed JSON object.

The rest of the script is the same as before: it finds the first review with a status of "APPROVED", checks if the approver is in the list of approvers, and prints a message accordingly.



