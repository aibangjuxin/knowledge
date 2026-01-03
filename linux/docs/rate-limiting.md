How does a Rate Limiter work?

The basic premise of a rate limiter is quite simple.

On a high level, you count the number of requests sent by a particular user, an IP address, or even a geographic location.

If the count exceeds the allowable limit, you disallow the request.

However, there are several questions to be asked if you had to design one from scratch.

For example:

[1] Where should you store the counters?

[2] What about the rate-limiting rules?

[3] How to respond to disallowed requests?

[4] How to ensure that changes in rules are applied?

[5] How to make sure that rate limiting doesn’t degrade the overall performance of the application?

To balance all of these considerations, you need several pieces that work in combination with each other.

The animated illustration attempts to show such a system:

So what’s going on in the animation?

✅ Incoming requests to the API server go to the Rate Limiter component.

✅The Rate Limiter fetches the rules from the rules engine.

✅Then, it checks the rate-limiting data stored in the cache. This data basically tells how many requests have already been served for a particular user or IP address (depending on the rule, of course)

✅The reason for using a cache is to achieve high throughput and low latency.

✅If the request falls within the acceptable threshold, the rate limiter allows it go to the API server

✅If the request exceeds the limit, the rate limiter disallows the request and informs the client or user that they have been rate limited (via HTTP status code 429)

But that’s not all. You can also put in a couple of tricks:

👉 First, instead of returning HTTP Status Code 429, you can drop the request silently. This is a useful trick to fool an attacker into thinking that the request has been accepted.

👉 Second, you can also have a cache in front of the rules engine to boost the performance. In case of updates to the rules, you could have a background worker process updating the cache with the latest set of rules.

So - have you used Rate Limiting?

How has your experience been?
