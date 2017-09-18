---
layout: post
title:  Event Sourcing
---

<img src="/images/event-sourcing/bugs.svg" width="1000" />

# Event Sourcing

## May the source be with you.

I recently became intrigued by the concept of _[event sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)_ as applied to back-end architecture, specifically a microservice-oriented approach. I have spent the last few years working predominantly on the front-end, and became enamored by the simplicity and elegance of this pattern as the backbone of front-end architecture, popularized by [Redux](http://redux.js.org/).

To better understand the trade-offs between a traditional, monolithic back-end, and a microservice-oriented, event sourced approach, I began sketching a toy architecture for the initial user flow of seemingly every web application: signing up for a user account, and receiving an activation email. Easy enough, right?

<img src="/images/event-sourcing/alien.svg" width="70" />

Little did I realize just how alien the event sourcing pattern would feel. I quickly developed more questions than answers. I spent the next several days reading everything I could about the subject, desperately begging Google to show me the way. I learned an incredible amount during that time, and in the spirit of the great [Julia Evans](https://jvns.ca/) I felt compelled to distill and summarize what I have learned for you, my fellow traveler.

This is by no means a guide indicating the "correct" way to do anything. My hope is that, if you're new to event sourcing, this summary might help you to start reasoning about how such a system could work.

<img src="/images/event-sourcing/devil.svg" width="40" />

## What the hell is event sourcing?

Good question! Martin Fowler [can tell you](https://martinfowler.com/eaaDev/EventSourcing.html):

> Event Sourcing ensures that all changes to application state are stored as a sequence of events. Not just can we query these events, we can also use the event log to reconstruct past states, and as a foundation to automatically adjust the state to cope with retroactive changes.

But — and this is true of most definitions of most things — this will just leave you with even more questions. So I'll try to explain event sourcing instead of defining it.

* Your application produces a *log of events*. For example, you might log a `UserAccountCreated` event for each user account that is created. The log might be split into smaller, independent logs called _topics_, to help organize your events.
* The events are the *source of truth* or [system of record](https://en.wikipedia.org/wiki/System_of_record) for your application. It is common for applications to write to a database and treat it as the source of truth, but when event sourcing we write to the event log instead.
* Other parts of the application can read from the event log. This allows for a pub/sub style of communication, where multiple listeners can react to events they are interested in.
* Listeners can reconstruct their own application state by reading from the event log and applying the events to their own, private data store, such as a database. They might apply some of the events, or all of them, depending on their use case. Events are always applied in the total order that they appear in the log.

<img src="/images/event-sourcing/overview.svg" width="430" />

## What can event sourcing do for me?

I can recommend two really good sales pitches for event sourced architectures (sometimes called _log-oriented_ architectures), and a more pragmatic overview. I recommend that you read and watch these in the following order:

1. Martin Kleppmann has an [excellent write-up](https://www.confluent.io/blog/using-logs-to-build-a-solid-data-infrastructure-or-why-dual-writes-are-a-bad-idea/) to whet your appetite.
2. Greg Young gave [a great talk](https://www.youtube.com/watch?v=8JKjvY4etTY) which really helped me to understand how event sourcing can be useful _even at small traffic scales._
3. And as always, Martin Fowler will try to talk some sense into us as a part of [his fantastic overview](https://www.youtube.com/watch?v=aweV9FLTZkU).

<img src="/images/event-sourcing/fowler-kleppmann-young.svg" width="280" />

But it's not fair for me to dump two hours of educational materials into your lap, so I'll do my best to summarize the observations of the great masters.

### Historical Queries

A typical database can answer questions about your data as it exists right now, but it struggles to answer time-series queries about the historical context and evolution of your data.

For example, you can query your database to determine the number of user accounts that exist. But what if your business stakeholder wanted to know how many users create an account, delete it, and then change their mind and create it again? Your database typically will not capture this data, since it only stores the _current_ state — it only stores the user account, and not the _steps_ that were taken to create that account. Writing events to a [log](https://www.youtube.com/watch?v=-fQGPZTECYs) naturally makes these kinds of queries possible, because the historical data is never deleted. The ability to be able to answer _any_ question that the business asks about the history of the application is incredibly valuable.

<img src="/images/event-sourcing/history-state.svg" width="300" />

Historical queries can ask, "How did we arrive at this state?", instead of, "What does the current state look like?"

### Immutable Data

Modeling your data as an immutable, append-only log of events greatly simplifies reasoning about how the application works. It is harder to get yourself into a confusing situation by accidentally mutating state. This is easier to understand when we consider the utility of time-traveling debugging.

<img src="/images/event-sourcing/append.svg" width="280" />

### Time-Traveling Debugging

Dan Abramov (creator of Redux) has [sung the praises](https://youtu.be/xsSnOQynTHs?t=18m2s) of time-traveling debugging from a front-end perspective, and the same principle applies from a back-end one.

Given that the event log is immutable, all changes to the application's state must be driven by _appending_ to the event log instead of changing it. This means that when our application behaves in a confusing way, we can simply start from the "beginning of time" and replay events one by one until we isolate the event that is triggering the confusing behavior. This is a powerful and incredibly simple tool for debugging our application.

<img src="/images/event-sourcing/time-travel.svg" width="300" />

_But that's not all!_ Just as our version control system can "check out" code at a particular point in the project's history, our event log can "check out" a particular point in time so that we can inspect how the state looked at that moment.

As Martin Fowler [pointed out](https://martinfowler.com/eaaDev/EventSourcing.html), instead of exclusively writing end-to-end tests we can explore a complementary approach: store and replay a sequence of events into the log, and then inspect the application's state to ensure that it matches what we expect.

<img src="/images/event-sourcing/testing.svg" width="600" />

These are just some examples. Retaining the time-series data in our event log opens up numerous opportunities for building [technical wealth](http://firstround.com/review/forget-technical-debt-heres-how-to-build-technical-wealth/).

<img src="/images/event-sourcing/crown.svg" width="120" />

### Easily Connect Data Consumers

An event sourced architecture features an event log as the central hub to which data producers write, and from which data consumers read. This pub/sub architecture minimizes or eliminates the need to write custom adaptors to get data out of one system and into another. All data is published in a standardized message format (JSON, or whatever you enjoy). Writing a new consumer becomes easier and more predictable, since systems share data in a consistent way. Multiple listeners can subscribe to an event log without a problem.

<img src="/images/event-sourcing/central-log.svg" width="450" />

Systems often mutate into Frankenstein architectures as new features and use cases are ~~bolted on~~ accommodated. Martin Kleppmann does a great job of [describing this phenomenon](https://www.confluent.io/blog/using-logs-to-build-a-solid-data-infrastructure-or-why-dual-writes-are-a-bad-idea/). Modeling data consumption as a log of events can mitigate this unsatisfactory result.

### Reasonable Scaling Defaults

An event sourced architecture provides reasonable defaults for common scalability challenges that applications face as load increases, and after exhausting vertical scaling strategies. It isn't a silver bullet (nothing is), but we can take comfort in the fact that we are probably not painting ourselves into a corner.

If writing to the event log is the bottleneck, we can split a single log into _partitions_ spread over multiple servers, each responsible for handling writes to its fair share of the partitions. This is how Apache Kafka works.

<img src="/images/event-sourcing/partitions.svg" width="400" />

If reading from the event log is the bottleneck, we can introduce log replication and have consumers read from the replicas.

<img src="/images/event-sourcing/replicas.svg" width="480" />

If consumers cannot keep up with the volume of events, we can add more consumers and parallelize the work of processing the events.

<img src="/images/event-sourcing/parallel-consumers.svg" width="520" />

If we run out of disk space to store the log, we can explore options for long-term storage. We could write a service to read older log messages and push them into a some kind of data warehouse. Consumers which only need to keep up with processing new-ish messages read directly from the primary log. Consumers which wish to rebuild their local state by processing all log messages from the beginning of time may do so by reading from the data warehouse until they reach the most recent warehoused message, and then switch to reading from the primary log.

<img src="/images/event-sourcing/storage.svg" width="450" />

### Fault Tolerance and Resiliency

This is my favourite feature of a log-oriented architecture, and the one that attracted me to event sourcing.

Often, one portion of an application will need to react to a change in a different subsystem. For example, when a user account is created, we might want to send an account activation email to that user.

In a traditional monolithic system, the controller which handles this logic might look something like this pseudocode:

```
user = new User('dvader@empire.gov')
user.save()
MailService.sendAccountActivationEmail(user)
```

The above logic will work 99% of the time. But every now and then the `MailService` will go offline. The new account will be created but the user will not receive their activation email. The user cannot activate their account!

<img src="/images/event-sourcing/dual-writes.svg" width="300" />

This is a tricky situation to recover from, and an example of the problem of [dual writes](https://www.confluent.io/blog/using-logs-to-build-a-solid-data-infrastructure-or-why-dual-writes-are-a-bad-idea/). It would be much better if we could build an application which simply _pauses_ when a subsystem goes down, and resumes from where it left off when that subsystem comes back online. This would provide tremendous peace of mind, save countless users from headache, and prevent us from wasting many days recovering from, debugging, and prematurely optimizing the availability problems of our `MailService`.

<img src="/images/event-sourcing/hard-drive.svg" width="220" />

Remember: we can often substitute rapid recovery for high availability. Instead of investing significant sums to achieve high availability, we can [Pareto-optimize](https://en.wikipedia.org/wiki/Pareto_principle) by investing a smaller amount into rapid recovery. For example, instead of buying the world's most reliable hard drive, we could simply make frequent backups. Our system can go down frequently, but the user will never notice as long as we can recover in a reasonable amount of time. As Gary Bernhardt [astutely points out](https://www.destroyallsoftware.com/compendium/network-protocols/97d3ba4c24d21147), TCP is so good at this that we take it for granted!

> TCP is so successful at its job [packet retransmission, rapid recovery] that we don't even think of networks as being unreliable in our daily use, even though they fail routinely under normal conditions.

This is a great example of the unreasonable effectiveness of [defense in depth](https://en.wikipedia.org/wiki/Defense_in_depth_(computing)) strategies. The first layer of defense is designing for availability, and the second layer is designing for recovery.

A log-oriented architecture can give us these benefits! Let's rewrite our pseudocode controller:

```
user = new User('dvader@empire.gov')
event = new AccountCreatedEvent(user)
EventLog.append(event)
```

Notice how we are no longer performing dual writes. Instead, we perform a single append to the event log. This is equivalent to saving the user account in the first example. If we model our writes as single log appends, they become inherently atomic.

<img src="/images/event-sourcing/single-write.svg" width="450" />

The email service would be monitoring the log for new account creation events, and would send emails in response to those events. If the email service were to go offline, it could simply pick up from where it left off. In fact, the email service could go offline for _days_, and catch up on unsent emails when it comes back online. It could also contain a memory leak which causes the system to crash every hour, but as long as the email service restarts automatically, your users will not likely perceive a service interruption.

### Mitigation of Data Inconsistencies

Kleppmann [points out](https://www.confluent.io/blog/using-logs-to-build-a-solid-data-infrastructure-or-why-dual-writes-are-a-bad-idea/) that systems which employ dual writes pretty much guarantee data consistency problems.

For example, let's say you update a user account record in the database, and then update a cache containing the now stale data. Let's further say that the cache update operation fails. Your cache is now out of sync with your database. Have fun debugging the consequences!

<img src="/images/event-sourcing/cache-out-of-sync.svg" width="250" />

A read-through cache can exhibit a similar problem. Updates to a user account in the database will not be immediately reflected in its corresponding cache entry until that entry expires. Stale cache data can be very confusing to both users and developers.

But what if we perform all writes to an event log? The cache can read and apply the events in order. The cache is always in sync with its source of truth, with the standard disclaimers about eventual consistency applying. But under normal circumstances, your cache could be quite consistent with its data source. Should anything go wrong, the cache can be rebuilt by simply starting from scratch and re-consuming the event log.

<img src="/images/event-sourcing/cache-sync.svg" width="320" />

### Simplicity

Nothing about software architecture is truly simple. But anyone who has been burned by the legacy of a bad decision will intuitively understand that simpler solutions are generally preferable. Simple solutions reduce cognitive overload, maximizing the chances that you will correctly predict the system's behavior.

An event sourced architecture really shines as a simplifying abstraction when compared to the Frankenstein architecture which tends to evolve from modest monolithic beginnings. Producers write to a log, consumers read from the log. This simple, unifying principle allows us to reason about data flow between subsystems without becoming bogged down in their idiosyncrasies.

Kleppmann [described](https://www.confluent.io/blog/apache-kafka-samza-and-the-unix-philosophy-of-distributed-data/) the event sourcing approach as Unix philosophy (specifically pipes) for distributed systems. The simplicity of Unix pipes is precisely what makes them so composable and powerful.

### Forgiving Of Mistakes

We all love that feeling when we write a piece of code and it works on the first try. That feeling is so wonderful because it is so rare. It is more common to spend as much time debugging our code as we did writing it. Mistakes are by far the normal mode of software development. Anything our architecture can do to help us recover from mistakes will have a dramatic impact on our iteration speed.

The traditional, stateful model of data persistence is very unforgiving in this regard. A bug in your code which mutates state in the wrong way will often require a one-off, compensating transaction to correct. And it's a race against time to make the correction, since subsequent operations based on bad data will only [compound the error](https://en.wikipedia.org/wiki/Garbage_in,_garbage_out).

But what if we can fix the bug and simply rebuild the state by re-consuming events via the patched system? We wouldn't need to duct tape our state. When the application is corrected, so is the state. We can reduce instances of fixing the application and then _also_ fixing the state.

Of course, there will always be exceptions. [All abstractions leak.](https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/) But in general we prefer boats with fewer leaks.

<img src="/images/event-sourcing/leaks.svg" width="240" />

### Ends Normalization Debate

Kleppmann makes an [excellent observation](https://www.confluent.io/blog/turning-the-database-inside-out-with-apache-samza/) regarding the best practice of database normalization. There is a tension between read- and write-optimized schemas. At a certain point, in order to boost read performance, we are tempted to denormalize our database. We might also attempt to cache query results from the normalized database, usually employing some kind of error-prone, dual write strategy.

<img src="/images/event-sourcing/normalization.svg" width="250" />

A log-oriented system breaks the tension by _deriving_ one or more read models from the log. We accept from the outset that one model cannot be great at everything. The log is write-optimized, and the derived read models can be denormalized to suit their specific usage pattern.

### Audit Trail

Greg Young [recalls](https://www.youtube.com/watch?v=8JKjvY4etTY) that he was initially attracted to event sourcing because he needed to implement auditing. Storing a log of every event that has occurred in the history of the application provides a natural audit trail.

If we aren't working on, say, a financial application, we tend to think that auditing will not be an important use case for our software. Then an incident occurs in production, and what do we do? We check the logs!

<img src="/images/event-sourcing/batcomputer.svg" width="280" />

### Better Business Agility

Kleppmann sees [agility enhancing](https://www.confluent.io/blog/turning-the-database-inside-out-with-apache-samza/) benefits in this approach to building software, and I think he's on to something.

Monolithic, stateful systems are optimized for consistency, not for change. At a certain point it becomes difficult to make changes, because those changes must render the system consistent when completed. Within a large system, that is no small feat! The result is that the rate of change decreases, because it becomes a huge pain to run even a small experiment.

The ability to connect new consumers to the log stream opens up the possibility of _bypassing_ existing systems to build one-off experiments. There is no need to run a migration to modify a database schema — simply deploy a new service with a different database, and store the additional data there for the duration of the experiment. The same goes for new read models, which can provide denormalized views for experimental new queries.

Have you ever noticed that _changing_ an existing system tends to trigger a bikeshedding process? _Adding_ a new system, in my experience, does not produce the same strong political reaction. My hunch is that this is because changing an existing system might break something which a colleague considers incredibly valuable, even sacrosanct. So by architecting our application to allow for the easy introduction of new subsystems, it seems reasonable to expect that we could actually reduce the amount of political debate associated with the running of experiments.

<img src="/images/event-sourcing/change.svg" width="1000" />

## What might event sourcing look like in practice?

Recall the initial user flow I described earlier: the user signs up for an account, and receives an activation email. Thinking about how to implement these features in an event sourced architecture provides a surprising amount of insight into the pattern and its subtleties. Let's work through it!

### Signing Up For An Account

Our user lands on the account sign up page and fills out the form, providing their `username`, `email`, and `password`.

<img src="/images/event-sourcing/api-gateway.svg" width="200" />

The user submits the form and an HTTP request is sent to our API Gateway service, which is the public-facing portion of our system. It might implement server-side rendered views, or it might expose an API or [Backend For Frontend (BFF)](http://samnewman.io/patterns/architectural/bff/) for a single-page or mobile application to consume.

### Immediate Feedback For The User

We want to build this application in a microservice style, and so we have decided to delegate ownership of all write-related user logic to a User Command service.

<img src="/images/event-sourcing/signup-fail.svg" width="600" />

We might be tempted to have the API Gateway publish an `AccountSignUp` event, which our User Command service would listen for and process. After all, this is how a lot of event-driven architectures behave — the user _did a thing_ that the system can react to. Unfortunately this creates a huge UX problem: we lose the ability to provide immediate feedback to the user. There is no guarantee that the User Command service is currently available — it could be overloaded, or it might have crashed. If we publish an `AccountSignUp` event and some of the form data is invalid, we have no way of informing the user. The best we can do would be to display an optimistic "success" message, _hope_ that the form data is valid, _hope_ that the user account is persisted, and _hope_ that, should any errors occur, the user would return to our website to try again.

The breakthrough approach here, for me, was when I understood that in an event sourced system, all of the _writes_ must occur to the event log. It could be interesting or useful to log some of the antecedent details (such as requests), but the only thing we really _must_ do is ensure that all writes are modeled as log appends.

<img src="/images/event-sourcing/signup-success.svg" width="620" />

If the user interface requires a synchronous response for immediate feedback, so be it. We can achieve this in the traditional, RESTful way, by having the API Gateway issue an HTTP request to the User Command service. Perhaps this would be modeled as a `POST /users` endpoint. The User Command service would perform any validations, write an `AccountCreated` event to the event log, and return a `201 Created` response to the API Gateway. The API Gateway would then render a success message for the user. The user account creation is considered to be a success — a historical fact — at the moment the log append occurs. (Greg Young [emphasizes the importance](https://www.youtube.com/watch?v=8JKjvY4etTY) of storing only facts in our event log.)

### Failure Modes

Let's think about how this part of the system would handle various failures:

* If the API Gateway's HTTP request to the User Command service fails, the API Gateway can immediately render an error message for the user. The user is then able to retry their request.
* If any of the form validations fail, the User Command service can return a `400 Bad Request` error to the API Gateway, which in turn can render field errors for the user.
* If the event log is unavailable and the User Command service cannot write to it, the User Command service can return a `500 Internal Server Error` to the API Gateway. The API Gateway can then render an error message for the user, who may retry their request.
* If the User Command service successfully writes to the event log and then dies, or its HTTP response is not delivered to the API Gateway, then the API Gateway will render an error message for the user, believing the User Command service to be unavailable. The user might then retry their request, if they don't notice their account activation email first! This could result in a second `AccountCreated` event being published to the log. It is therefore important that consumers of the event log implement their consumption in an idempotent way.

<img src="/images/event-sourcing/poops.svg" width="100" />

### Validation

Whenever we are working with user generated data, there is always some validation that must occur. We can think of a few common constraints for our account sign up form:

1. The `username` cannot be blank.
2. The `email` cannot be blank.
3. The `password` cannot be blank.
4. No two user accounts should have the same `username`.
5. No two user accounts should have the same `email`.

To accommodate some of these rules, we will need to think a bit differently than we are used to.

Ensuring that fields are not blank can be accomplished in the obvious way: the User Command service checks for the existence and length of these values and returns the appropriate error code to the API Gateway in the event of an invalid submission.

But how can we enforce the constraints that no two accounts should have the same `username` or `email`? If we were using an ACID-compliant relational database, this would be easily achievable by adding a `UNIQUE` constraint to the `username` and `email` columns — the database would thereafter refuse to insert duplicates. Since our event log is not a relational database, we will have to devise another way.

Naturally, the mind will wonder if the User Command service could first read from the database used to store its corresponding read model, searching for duplicate values — if a duplicate is found, do not write to the event log. And this approach would _appear_ to work at first, but due to the eventually consistent property of our system, writes to the event log are not immediately reflected in the various read models that our services maintain. A race condition has been introduced: it is possible to create two user accounts with duplicate data in rapid succession, because we cannot guarantee that the read model will be up to date with the first write at the time that the second write occurs.

<img src="/images/event-sourcing/race-condition.svg" width="600" />

### Maybe You Don't Need Immediate Consistency

I can't remember where I first encountered the following solution, but it struck me as a novel and contrarian approach with a lot of utility: why not simply embrace the fact that the system no longer provides an immediate consistency guarantee? We could design our system to gracefully handle some the uniqueness constraints in a different way:

1. We could allow duplicate accounts to be created with the same email address, and simply ignore all but the first creation event. If a user accidentally signs up twice, only one account will be created. The total order of our log messages ensures that these two events will always be processed in the same order. This approach has the undesirable effect of including two account creation events in the log, which might be confusing.
2. We could allow more than one user to enjoy the same username. Why not? Social networks allow users to change their names at will. A surrogate key (e.g. universally unique identifier) can be used for internal purposes. The user's email address can be used for login purposes.
3. We could shamelessly violate [CQRS](https://martinfowler.com/bliki/CQRS.html) and perform a kind of optimistic concurrency control by allowing the read model to detect when a duplicate username is about to be inserted, and then _modify the username_ to preserve its uniqueness. For example, `dvader` might be renamed to `dvader_1`. Finally, the read model would emit another event to notify the user that they should change their username. This seems like a contrived and impractical solution, but consider what happens in macOS when a file is copied and pasted on top of itself: instead of throwing an error, the operating system allows the paste, and automatically renames the second version to be `file 2`. Still, I don't like the conflation of read/write concerns.

For our user sign up flow, I think we can eliminate the uniqueness constraint for usernames. But what about email addresses? I would prefer not to have duplicate account creation events in the log if we can avoid it.

<img src="/images/event-sourcing/lock-tag.svg" width="240" />

### Locks

We could make judicious use of locks to enforce a uniqueness constraint for email addresses.

<img src="/images/event-sourcing/lock-service.svg" width="560" />

We would add a new Lock service to our ecosystem. The Lock service does what it says on the tin: other services can use it to obtain a lock on a resource before writing to it. This could be as simple as an HTTP service wrapping a transactional data store, but probably we would want to reach for an off-the-shelf solution.

When requesting a lock, services would specify a key which uniquely identifies the resource. For example, the key might be `dvader@empire.gov`. The corresponding value would be a unique identifier representing the service instance requesting the lock.

After successfully acquiring a lock on an email address, the User Command service can safely publish an event to create an account, or change a user's email address. Since only the service instance which holds the lock has permission to perform writes which involve that email address, duplicate account creation events are thereby prevented.

When the write is successful, the User Command service can release the lock by sending another request to the Lock service. If this is not done, no further writes which involve that email address could be made! The lock would be stored with a time-to-live so that, in the event that the User Command service dies before it can release its lock, the lock is automatically released, preventing a deadlock.

Unfortunately, there are problems with this approach.

### Temporal Anomalies

Kleppmann does a [great job](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html) of explaining why timing-based lock algorithms cannot prevent errors. As it turns out, as soon as we apply a time-to-live to the lock, it becomes unreliable. For example, a long GC pause in a service could actually exceed the time-to-live on our lock, allowing the same lock to be acquired twice! And even if only a small number of locking errors occur during the lifetime of the application, allowing a few duplicate writes to leak through, we will need to modify _all_ event log consumers to handle that exceptional case. If the event stream contains even _one_ duplicate, from the consumer's perspective it might as well contain a million of them.

If we remove the time-to-live from the lock, we will be okay until the User Command service dies immediately after acquiring the lock, but before writing the new user account. When the service restarts after this error, we will be deadlocked. The user will be unable to retry their account creation, because their email address is now permanently locked.

<img src="/images/event-sourcing/deadlock.svg" width="440" />

Really, what we need to do is ["squeeze all the non-determinism out of the input stream"](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying). Kleppmann provides two strategies for achieving this.

### Fencing Tokens

The first strategy is to have the Lock service implment a [fencing token](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html). Basically, each time a lock is acquired, the Lock service assigns a monotonically increasing integer to the lock. If the same lock is accidentally acquired twice due to temporal anomalies, each version of the lock will have a different integer associated with it. Requests to write must then supply the integer, and the service which handles the writes is responsible for ignoring writes whose integer is not larger than that of the previous write.

<img src="/images/event-sourcing/fencing-token.svg" width="650" />

Notice something about this strategy? It looks awfully similar to a totally ordered log! This implies that a log-oriented solution might be possible. It also requires a heck of a lot of plumbing, in my opinion. Each service responsible for writing to a locked resource must understand and correctly implement the monotonically increasing integer check.

### Filtering Duplicates

Kleppmann's [second strategy](https://www.infoq.com/presentations/event-streams-kafka) is a log-oriented one. Basically, services wishing to acquire a lock publish a request event to a topic within the event log. A consumer service (similar to our Lock service) reads those events and essentially filters out duplicates, finally publishing a different event (the actual write) to a different topic within the event log. If the consumer service dies, it can simply reconstruct its state by replaying log events.

<img src="/images/event-sourcing/deduplicator.svg" width="650" />

This is a very clever solution, built out of simple components, and it relieves the services handling writes from the responsibility of implementing a fencing token. Unfortunately the cost of this simplicity is losing the ability to provide a synchronous response to the user — we can't tell them if their write was successful, because consumption of the event log might be delayed. I wonder if we can come up with a reusable solution which allows us to provide immediate feedback to the user?

### Uniq Service

Recall the distributed-systems-as-Unix-pipes philosophy. It might be possible to create a composable Uniq service — similar to the Unix `uniq` command — which could be reused across multiple services for their event deduplication and locking needs.

<img src="/images/event-sourcing/pipes.svg" width="400" />

How would this Uniq service work? All write events subject to uniqueness constraints would be sent to Uniq for deduplication and constraint checking purposes, before being forwarded on to the event log. Uniq could expose a RESTful API for create, update, and delete operations, . An `/event` endpoint would do nicely.

<img src="/images/event-sourcing/uniq.svg" width="500" />

When performing user account creation, the User Command service would construct its desired log message and `POST` it to the Uniq service. Uniq would support a simple configuration file which maps fields of log messages to CRUD operations. For example, when Uniq receives our `AccountCreated` event, it would extract the `email` field from that event and add that email to a set it maintains in memory. If the email does not already exist in the set, Uniq writes that event to the log, and returns a `200 OK` response. In this way, Uniq can provide a synchronous response to our User Command service, which facilitates immediate feedback for the user. Uniq acts as a proxy for events — just another piece of the pipeline.

If an email address already exists in the set, Uniq would return a `409 Conflict` response, and would _not_ forward the event to the log. Use cases involving changing or deleting an existing email address are easily supported by the HTTP `PATCH` and `DELETE` semantics. Unlike the Unix `uniq`, our Uniq requires these semantics because it is stateful. It isn't simply counting unique items, but rather allowing that set of unique items to be maintained in the face of change.

Of course, given that Uniq will be maintaining a set in memory, we must consider what will happen in the event that it crashes. If this were to occur, Uniq can rebuild its set by re-consuming log messages. When Uniq has caught up with where it left off, it can accept write traffic again. Because our log is totally ordered, and because Uniq processes write requests serially, it should never commit a duplicate write to the log, even when recovering from an outage.

If availability is a concern, a second instance of Uniq can operate in follower mode, consuming from the event log to maintain a replica of the leader's state. When the leader dies, the follower can be promoted to leader.

### Relational Database Envy

So we have our strategy for handling concurrent requests for user accounts with the same email address: we will pipe all writes through a Uniq service, which enforces the uniqueness constraint.

Couldn't we have used a relational database to enforce this constraint instead? Well, yes, we could. Michael Pleod makes the [wise recommendation](https://www.youtube.com/watch?v=A0goyZ9F4bg) that we implement the level of consistency that our business domain requires. The ideal level of consistency for one subsystem may not be needed across the entire system. For example, it might be considered unacceptable for two user accounts to _ever_ accidentally share the same email address, since this would prevent users from logging in. Therefore, we can enforce a uniqueness constraint only for email addresses, paying the complexity cost because we see it as justifiable. But for other subsystems where we might traditionally enforce a uniqueness constraint, we could employ more creative solutions. We are dialing in the amount of consistency that each part of the system requires.

So it would make sense for the User Command service to write to a relational database implementing a uniqueness constraint. But this approach creates one very unfortunate side-effect: we lose atomicity. Writing a new user to the database, and _then_ writing an event to the log, opens the possibility that the first write will succeed but the second one will fail. This situation would render our data inconsistent, and a compensating transaction would be required to reconcile the two. Dual writes strike again!

<img src="/images/event-sourcing/atomicity.svg" width="400" />

It might be possible to create a second table in our relational database, and write our events to that table. We could then wrap both our user write and the event write in a transaction, regaining atomicity. But now we need a way to get those events _out_ of the database and into the event log, and ideally without implementing a polling strategy, which would increase replication lag. The amount of plumbing required to make this happen is excessive, in my opinion. And the solution wouldn't be reusable across services.

### The Read Model

So our User Command service is able to write an `AccountCreated` event to the log via the Uniq service. But how would we handle reads? One cannot simply perform queries against an event log, since query performance would decrease as the log grows in size! To support reads, we will need to implement a _read model_.

The read model consists a service wrapping a persistence mechanism. Most likely we would choose a database which provides a good fit for the types of queries we will be performing. For our User Query service we will assume a document database which stores JSON-like documents.

<img src="/images/event-sourcing/read-model.svg" width="500" />

The read model will consume relevant events from the event log, and update its database accordingly. In the case of the User Query service, every `AccountCreated` event consumed would trigger the insertion of a new user document into the database.

Where this pattern can become very powerful is in maintaining highly optimized, incrementally computed query results. One could imagine introducing a Friends service which maintains a list of frequently contacted friends for each user, entirely derived from log messages. Batch computing this contact frequency information could take a long time, and the results would quickly become stale. Incrementally computing with each new piece of information can provide a more consistent view, while maintaining fast query response times.

Another interesting property is the potential for the elimination of schema migrations. Denormalizing the read model brings the possibility of introducing NoSQL stores. The addition of a new field would be handled in application code, and a schema "rollback", if one were required, could be accomplished by reverting the application code and replaying events from the affected period.

### Sending Mail

After our user has signed up, we want to send them an account activation email. To accomplish this, we will create a Mail service which monitors the event log for `AccountCreated` events, and sends activation emails to those users, probably by calling the RESTful API of a third-party email provider.

<img src="/images/event-sourcing/mail.svg" width="500" />

But what happens if the Mail service crashes after reading a message from the log? As it turns out, this is not a problem, provided that the mail service persists the ID of the last message it consumed — a _checkpoint_. And where better to persist this ID than to a topic within the event log!

How frequently should we store checkpoints? If we store a checkpoint for every message consumed, log consumption speed will be limited by the need to write a checkpoint in between every read. If this was inadequate for our purposes, we could have the Mail service store a checkpoint every hundred writes, or every thousand, or every 60 seconds. But then wouldn't we be at risk of sending a hundred, or a thousand, or 60 seconds worth of duplicate emails if the Mail service crashes?

As it turns out, the Mail service cannot guarantee exactly-once delivery of emails to users. Let's say that the Mail service has already consumed event 1, and is now consuming event 2 from the log. If an email is sent and the service crashes before checkpoint 2 can be written, when the service restarts it will begin working from the next event after its last checkpoint. The last checkpoint was 1, so event 2 will be processed again. A duplicate email will be sent!

<img src="/images/event-sourcing/duplicates.svg" width="520" />

Writing the checkpoint before sending the email will only make things worse. If we store checkpoint 2 and then crash before sending email 2, when the service restarts it will begin working from the next event after its last checkpoint. The last checkpoint was 2, so event 3 will be processed. In this case, event 2 will be skipped!

Since we cannot prevent the Mail service from sending duplicate emails, and since it would be a Very Bad Thing™ to fail to send any account activation emails, we can feel a bit better about setting a less frequent checkpoint rate.

### Dependency Woes

It is a prudent exercise to think about what would happen if our third-party email provider were to suffer various failures.

If for any reason our Mail service does not receive a response from the provider, we can retry the request. In fact, we _need_ to retry the request, because the log-oriented nature of our system can only guarantee that all events are processed if they are handled sequentially. If we start skipping events, we would need to enqueue those skipped events into — you guessed it — another log for later processing. It's logs all the way down.

<img src="/images/event-sourcing/retries.svg" width="600" />

So the system will guarantee delivery by _pausing_ when an error occurs, polling for success, and resuming when the error condition has passed. This entails installing a [circuit breaker](https://martinfowler.com/bliki/CircuitBreaker.html) to gate calls to the email provider. If the provider becomes unresponsive, the Mail service will retry the request repeatedly until the circuit breaker trips, at which point it will retry the request at a slower rate. When the provider comes back online, a request will eventually be successful and the Mail service can catch up with its backlog.

### That's All, Folks

Our toy system is now complete. Obviously this represents merely the user signup flow for what would be a much larger application. I would go on, but as you can see, even this slice of architecture requires a lengthy description. Nevertheless, I hope this has been a useful dive into the finer details how we might go implementing such a system. I know I've learned a lot while writing it!

<img src="/images/event-sourcing/architecture.svg" />

## Where do we go from here?

Event sourcing is a radically different way of looking at software architecture. Predictably, this new approach is not without its learning curve. It also comes with tantalizing potential benefits. The question is how to sensibly proceed.

I am reminded of Spolsky's [Law of Leaky Abstractions](https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/). Event sourcing is just another abstraction which seeks to simplify the complexity of the software we write. Naturally, this abstraction will leak, creating problems for us. But it is important to keep in mind that the monolithic, relational, strongly consistent style of architecture is _also_ an abstraction. Our comfort with the abstraction we know too often spares us the terrifying advantages of new ways of doing things!

One thing I have learned over the years is that I can never predict the practical consequences of introducing an unfamiliar technique into an organization. Because something always goes wrong, we actually _need_ to implement the technique to discover where it breaks down. Only after introduction can we identify the concrete problems, and begin to devise solutions.

The knowledge that something _will_ go wrong is often used as a justification for not experimenting with new techniques at all. "We'll revisit this discussion _later_." Later effectively means never. Interestingly, this seems to be the wrong conclusion to draw from the mere possibility of risk. Problems may be unavoidable, but we have the power to control the scope of the introduction, and thereby shape the size of the problems encountered. Given that we possess a "risk knob" which we can dial down to comfortable levels, what justification remains for failing to experiment with new techniques?

I think the most sensible course of action is to treat event sourcing as an evolutionary pattern. Incorporate this pattern into a portion of your project — get your feet wet. But don't dive in, because you'll probably drown. But don't stay out of the pool, because then you'll never learn to swim! Learning takes time, so the sooner you can get started, the sooner you can determine how to incorporate the benefits while mitigating the pitfalls. As the [famous Chinese proverb](http://nicholaskuechler.com/2006/10/23/favorite-quotes-chinese-proverb-best-time-to-plant-a-tree/) says:

> "The best time to [begin reinforcing event sourcing patterns] was 20 [sprints] ago."

<img src="/images/event-sourcing/ants.svg" width="1000" />
