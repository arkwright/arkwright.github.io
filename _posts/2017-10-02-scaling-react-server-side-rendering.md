---
layout: post
title:  Scaling React Server-Side Rendering
---

<img src="/images/scaling-react-server-side-rendering/scaling-react.svg" width="250" alt="Giant stack of React service instances in the shape of a shoddy pyramid, with the top one falling off, possibly to crush a tiny developer below. 8/10 pretty good metaphor." />

# Scaling React Server-Side Rendering

I had the opportunity to work on scaling a React rendering service, adapting a fixed hardware provision to deal with increasing load. Over the course of many months, incremental improvements were made to the system to enable it to cope with demand. I thought it might be useful to share the more interesting insights that I gained during this process.

Some of the insights here are React-specific, but many are simply generic scalability challenges, or simple mistakes that were made. React server-side performance optimization has been covered elsewhere, so I'm not going to provide an overview of React performance, generally. I'm going to focus on the "big wins" that we enjoyed, along with the subtle, fascinating [footguns](https://en.wiktionary.org/wiki/footgun). My hope is that I can give you something interesting to think about, beyond the standard advice of setting `NODE_ENV=production`. Something based on the real, honest-to-goodness challenges we had to overcome.

What I found so interesting about this project was where the investigative trail led. I assumed that improving React server-side performance would boil down to correctly implementing a number of React-specific best practices. Only later did I realize that I was looking for performance in the wrong places. With any luck, these stories will enable you to diagnose or avoid your own performance pitfalls!

<img src="/images/scaling-react-server-side-rendering/pitfall.svg" width="280" alt="Stick figure swinging on a rope over a bottomless pit, towards a shimmering React logo. Remember Pitfall?" />

## Things We Will Talk About

* [Introduction](#scaling-react-server-side-rendering)
* [The Situation](#the-situation)
* [Load Balancing](#load-balancing)
  * [I Got 99 Percentiles](#i-got-99-percentiles)
  * [Seasonality](#seasonality)
  * [Randomness](#randomness)
  * [Load Balancing Strategies](#load-balancing-strategies)
  * [Load Shedding With Random Retries](#load-shedding-with-random-retries)
  * [Round-Robin](#round-robin)
  * [Join-Shortest-Queue](#join-shortest-queue)
  * [Fabio](#fabio)
  * [Great Success](#great-success)
* [Client-Side Rendering Fallback](#client-side-rendering-fallback)
  * [Elastic Inelasticity](#elastic-inelasticity)
  * [How It Works](#how-it-works)
  * [The Results](#the-results)
* [Load Shedding](#load-shedding)
  * [Why You Need Load Shedding](#why-you-need-load-shedding)
  * [Not So Fast](#not-so-fast)
  * [Interleaved Shedding](#interleaved-shedding)
  * [I/O And Worker Processes](#io-and-worker-processes)
* [Component Caching](#component-caching)
  * [The Idea Of Caching](#the-idea-of-caching)
  * [Two Hard Things In Computer Science](#two-hard-things-in-computer-science)
  * [Caching And Interpolation](#caching-and-interpolation)
  * [Murphy's Law](#murphys-law)
  * [Oh FOUC!](#oh-fouc)
  * [Exploding Cache](#exploding-cache)
  * [Making The Opposite Mistake](#making-the-opposite-mistake)
  * [Cache Rules Everything Around Me](#cache-rules-everything-around-me)
* [Dependencies](#dependencies)
  * [Don't Get Hacked](#dont-get-hacked)
  * [Do You Like Free Things?](#do-you-like-free-things)
* [Isomorphic Rendering](#isomorphic-rendering)
  * [The Browser As Your Server](#the-browser-as-your-server)
  * [Pairs Of Pages](#pairs-of-pages)
* [The Aggregation Of Marginal Gains](#the-aggregation-of-marginal-gains)
* [All Your Servers Are Belong To Redux](#all-your-servers-are-belong-to-redux)

## The Situation

Our team was looking to revitalize the front-end architecture for our product. As tends to be the case with a many years-old monolith, the technical debt had piled up, and front-end modifications were becoming difficult. Increasingly, we were telling product managers that their requested changes were infeasible. It was time to get serious about sustainability.

Within the front-end team, a consensus was quickly reached that a component-oriented architecture built on React and Redux was the best bet for a sustainable future. Our collective experience and intuition favored separating concerns at the component level, extracting reusable components wherever possible, and embracing functional programming.

<img src="/images/scaling-react-server-side-rendering/redux-logo.svg" width="250" alt="It is surprisingly hard to draw the Redux logo! (Along with three very poorly drawn Redux logos.)" />

We were beginning with the fairly modest, spaghetti front-end that most monolithic applications seem to evolve into. Browser requests would hit a load balancer, which would forward requests to one of several instances of a Java/Spring monolith. JSP-generated HTML templates were returned, styled with CSS (LESS), and dynamic client functionality was bolted on with a gratuitous amount of jQuery.

<img src="/images/scaling-react-server-side-rendering/starting-architecture.svg" width="500" alt="Diagram of monocled, top-hatted user connecting to a Load Balancer, which forwards the request to a Monolith. Monolith responds by returning a rendered JSP document to the load balancer, which sends it to the user. Pretty boring stuff." />

The question was how to integrate our desire for a React front-end with a Java monolith. SEO was a very important consideration — we had full-time SEO consultants on staff — and we wanted to provide the best possible page load speed, so server-side rendering quickly became a requirement. We knew that React was capable of isomorphic (client- and server-side) rendering. The back-end team was already on their journey towards breaking up the monolith into a microservice architecture. It therefore seemed only natural to extract our React server-side rendering into its own Node.js service.

<img src="/images/scaling-react-server-side-rendering/final-architecture.svg" width="650" alt="Diagram of our MacGuffin, the monocled, top-hatted user, connecting once again to the Monolith via the Load Balancer. This time, Monolith requests some React component renders from the React service, which sends a response containing the rendered components, a serialized Redux store, and mounting instructions. The Monolith takes these pieces and merges them into a JSP, sending the final output through the Load Balancer and back to the user. Slightly less boring stuff." />

The idea was that the monolith would continue to render JSP templates, but would delegate some parts of the page to the React service. The monolith would send rendering requests to the React service, including the names of components to render, and any data that the component would require. The React service would render the requested components, returning embeddable HTML, React mounting instructions, and the serialized Redux store to the monolith. Finally, the monolith would insert these assets into the final, rendered template. In the browser, React would handle any dynamic re-rendering. The result was a single codebase which renders on both the client and server — a huge improvement upon the status quo.

As we gained confidence with this new approach, we would build more and more of our features using React, eventually culminating with the entire page render being delegated to the React service. This approach allowed us to migrate safely and incrementally, avoiding a big-bang rewrite.

<img src="/images/scaling-react-server-side-rendering/starting-transition-goal.svg" width="280" alt="The same web page, composed three different ways, demonstrating an incremental migration path. Starting form is entirely JSP-rendered. Transition form contains a mixture of JSP and React-rendered elements. Goal form is one huge React-rendered component." />

Our service would be deployed as a Docker container within a Mesos/Marathon infrastructure. Due to extremely complex and boring internal dynamics, we did not have much horizontal scaling capacity. We weren't in a position to be able to provision additional machines for the cluster. We were limited to approximately 100 instances of our React service. It wouldn't always be this way, but during the period of transition to isomorphic rendering, we would have to find a way to work within these constraints.

## Load Balancing

### I Got 99 Percentiles

The initial stages of this transition weren't without their hiccups, but our React service rendering performance was reasonable.

<img src="/images/scaling-react-server-side-rendering/response-latency-5-50ms.svg" width="280" alt="Graph of Response Latency (ms) over time. p50 response time is plotted as being fairly consistent at around 5ms. p99 response time is more erratic but generally around 50ms." />

As we ported more and more portions of the site to React, we noticed that our render times were increasing — which was expected — but our 99th percentile was particularly egregious.

<img src="/images/scaling-react-server-side-rendering/response-latency-30-250ms.svg" width="300" alt="Graph of Response Latency (ms) over time. p50 response time is plotted as being fairly consistent around 30ms. p99 response time is fairly erratic but generally around 250ms. Yeah, I know, graphs are boring. Drawing them was surprisingly fun, though. At least one of us is having fun." />

To make matters worse, when our traffic peaked in the evening, we would see large spikes in 99th percentile response time.

<img src="/images/scaling-react-server-side-rendering/response-latency-evening.svg" width="320" alt="Graph of Response Latency (ms) over the course of about 12 hours, from 12pm to 12am. p50 response time is plotted as being fairly consistent at around 30ms, and increases to about 50ms in the evening, starting at about 6pm. p99 response time is more erratic, hovering around 250ms, and increases to around 350ms in the evening, also starting around 6pm. By 12am response times are clearly decreasing again. If the previous graphs were boring, this graph is like the beginning of an episode of your favourite TV crime drama." />

We knew from our benchmarks that it simply does not take 400ms to render even a fairly complex page in React. We profiled and made lots of improvements to the service's rendering efficiency, including streaming responses, refactoring React component elements to DOM node elements, various Webpack shenanigans, and introducing cached renders for some components. These measures mitigated the problem, and for a while we were hovering right on the edge of acceptable performance.

### Seasonality

One day I was looking at our response latency graph, and I noticed that the problem had returned. Unusually high traffic during the previous evening had pushed our 99th percentile response times past the acceptable threshold. I shrugged it off as an outlier — we were incredibly busy, and I didn't have time to investigate.

This trend continued for a few days. Every evening when traffic peaked, we would set a new record. Zooming out to show the last few days, there was a clear trend of increasing response time.

<img src="/images/scaling-react-server-side-rendering/response-latency-week.svg" width="400" alt="Graph of Response Latency (ms) from Monday to Friday. p50 response time is plotted as being fairly consistent at around 50ms, though daily peaks and troughs are clear. p99 response time is more erratic at around 250ms, also with daily peaks and troughs. Importantly, the peak p99 response time is increasing with each passing day, and approaches 400ms on Friday. Seeing something like this in real, production graphs makes you feel like a cast member in Armageddon. Now you can't get that Aerosmith song out of your head. Look, I didn't say you would *like* the alt text." />

There was a clear correlation in the graphs between traffic volume and response time. We could attempt to duct tape the problem, but if traffic were to increase, we would be in bad shape. We needed to scale horizontally, but we couldn't. So how close were we to a calamity? I pulled up an annual traffic graph, and promptly spit out my tea.

<img src="/images/scaling-react-server-side-rendering/requests-per-minute-annual.svg" width="650" alt="Graph of Requests Per Minute over the course of one year, from January to the end of December. Y-axis goes from zero to 'lots' of requests. A single line plots requests per minute, which vary a bit through the day, so the line is slightly erratic. Still, a general trend is clear, with requests hitting a low point in December, and increasing until a high point in July. A 'You are here.' arrow points to early March, which is where I was situated when I first looked at this graph (and promptly spit out my tea)." />

Without a doubt our response times would dramatically increase with traffic. It was currently spring — roughly the annual midpoint for traffic — and by summer we would be drowning in requests. This was Very Bad.

But how could we have missed this? We thought we had solved this problem already. What gives?

I'm pretty sure we were caught off guard due to the seasonality of our traffic. Starting the previous summer — when traffic was at its peak — we began moving more and more functionality to React. If traffic had remained constant, the increased component rendering load would have caused our response times to increase. Instead, as the year progressed, traffic was decreasing. Requests were going down, but the per-request workload was going up! The result was a roughly flat response time during the fall and winter seasons. As traffic picked up again in the spring, our response times rapidly increased, and this time the effect was magnified by the increased per-request workload.

<img src="/images/scaling-react-server-side-rendering/response-latency-vs-components.svg" width="650" alt="Graph of Response Latency (ms) vs # React components. X-axis spans one year, from July to July. Y-axis ranges from 0 to 400 ms response latency. Two lines are plotted: p99 response latency and number of components. Both lines suddenly begin in mid-July. Response latency starts around 100ms (hey, this graph isn't exactly to scale, I'm drawing it from memory), and increases to around 300ms in December, then decreases during the winter, to about 250ms in February, finally increasing roughly linearly to a peak of 400ms in July. The number of components line increases purely linearly from mid-July to the following July, though I didn't provide a value for its Y-axis, simply showing that it starts from a small number of components, and increases to 'lots'. The general idea of this graph is that the number of components can increase while response times decrease, because demand for rendering can fluctuate seasonally. I think this is the biggest alt text I've ever written. In a pinch, you could use this alt text to filibuster." />

### Randomness

Out of ideas for squeezing easy performance wins out of the system, I started asking some of my colleagues for suggestions. During one one of these conversations, somebody mentioned the fact that our service discovery mechanism, Consul, returns three random service instances for every service discovery request.

I remembered reading a [fantastic Genius article](https://genius.com/James-somers-herokus-ugly-secret-annotated) several years ago, which told the story of the performance regressions that they experienced when Heroku silently switched to a randomized load balancing strategy, causing a 50x decrease in scaling efficiency. If we were using a similar load balancing strategy, then we were likely to be suffering the same fate. I did a bit of spelunking and confirmed that this was indeed the case.

Basically, when the monolith needs to make a request to the React service, it needs to know the IP address and port where it can locate an instance of that service. To get this information, a DNS request is sent to Consul, which keeps track of every active service instance. In our configuration, for each service discovery request, Consul returns three _random_ instances from the pool. This was the only load balancing mechanism within the system. Yikes!

<img src="/images/scaling-react-server-side-rendering/service-discovery.svg" width="450" alt="Diagram of how service discovery works. Monolith makes a call to Consul requesting the location of the React service. Consul responds with three different IP addresses and port number combinations, which are the locations of three random React service instances. The Monolith then sends a request to one of these React service instances, asking for a Header component to be rendered. The React service renders the component, and returns it to the Monolith." />

Before I continue, I should explain why random load balancing is inefficient.

Let's say you have a load balancer and three service instances. If the load balancer routes requests _randomly_ to those instances, the distribution of requests will always be severely uneven.

<img src="/images/scaling-react-server-side-rendering/random-load-balancing.svg" width="500" alt="Diagram showing Load Balancer routing requests randomly to three service instances. Instances receive 7, 2, and 4 requests, respectively. Random load balancing always produces a distribution like this. Yes, it does. YES IT DOES!!!1" />

I have explained this problem to many people, and it confuses a huge number of them. It reminds me of the [Monty Hall problem](https://en.wikipedia.org/wiki/Monty_Hall_problem) — even though it's true, people find it hard to believe.

But yes, it's true: random load balancing does not balance load at all! This can be easier to understand if you flip a coin, counting the number of heads and tails. The balance is almost always uneven.

<img src="/images/scaling-react-server-side-rendering/coin-tosses.svg" class="breakout" alt="Diagram of coin tosses over time, titled, 'Coin tosses are random yet uneven!' Describing this is going to be tricky, since I had to invent this visualization to make the point, but here we go. The x-axis represents time, and the y-axis represents bias in coin tosses towards heads or tails. With each coin toss, the plotted line moves incrementally upwards (towards heads), or downwards (towards tails). Each point on the line is marked with an 'H' or a 'T', respectively. When coin tosses are evenly distributed, the line remains roughly horizontal, moving up, down, up, down, etc. When coin tosses are uneven, such as when we get four heads in a row towards the end of the graph, the line moves up, up, up, up. This diagram shows that, at any given point in time, coin toss results can be unbalanced in favor of heads or tails, despite the long-term trend being towards evenness. These were actual coin tosses that I performed at like 1am, when I was suddenly inspired to draw this diagram. That's how committed I am to you. I'm here for you." />

A common response is that the load may not be balanced at the beginning, but over time the load will "average out" so that each instance will handle the same number of requests. This is correct, but unfortunately it misses the point: at almost every _moment_, the load will be unevenly distributed across instances. Virtually all of the time, some servers will be concurrently handling more requests than the others. The problem arises when a server decides what to do with those extra requests.

When a server is under too much load, it has a couple of options. One option is to drop the excess requests, such that some clients will not receive a response, a strategy known as _load shedding_. Another option is to queue the requests, such that every client will receive a response, but that response might take a long time, since it must wait its turn in the queue. To be honest, both options are unacceptable.

<img src="/images/scaling-react-server-side-rendering/load-shedding.svg" width="500" alt="Diagram of how load shedding works. Load Balancer sends 3 requests ('too many requests!') to an instance of a service. The instance sends a response for request #1, and and discards requests #2 and #3 into a bottomless pit, which is actually how servers work and not at all a metaphor." />

<img src="/images/scaling-react-server-side-rendering/queueing.svg" width="500" alt="Diagram of how queuing works. Load Balancer sends 3 requests ('too many requests!') to an instance of a service. The instance sends a response for request #1, and enqueues the remaining two requests for later processing. I drew tiny front and back doors on the service, which the queued requests can use to enter and exit. One cannot live on boxes and arrows alone." />

Our Node servers were queueing excess requests. If we have at least one service instance per concurrent request, the queue length for each instance will always be zero, and response times will be normal, provided that we are balancing the load evenly. But when we are using a random load balancing strategy, some instances will _always_ receive an unfair share of requests, forcing them to queue the excess ones. The requests at the back of a queue must wait for the _entire_ queue to be processed, dramatically increasing their response time.

<img src="/images/scaling-react-server-side-rendering/queues-increase-response-time.svg" width="500" alt="Diagram entitled 'Queues increase response time!' Load Balancer sends 3 requests ('too many requests!') to an instance of a service. The instance sends a response for request #1, and enqueues the remaining two requests for later processing. Each requests requires 10ms to process, so request #1 experiences 10ms latency. Request #2 must wait for request #1's 10ms processing, and then also its own, suffering 20ms latency in total. Request #3 accordingly must wait for 30ms. This cycle continues until either all requests are handled or your server explodes, all of your users defect, and your team disbands." />

To make matters worse, it doesn't matter how many service instances we have. The random allocation of requests guarantees that some instances will always be sitting idle, while other instances are being crushed by too much traffic. Adding more instances will reduce the probability that multiple requests will be routed to the same instance, but it doesn't eliminate it. To really fix this problem, you need load balancing.

I installed metrics to graph request queue length per service instance, and it was clear that some services were queueing more requests than others. The distribution would change over time, as the random load balancing just happened to select different instances.

<img src="/images/scaling-react-server-side-rendering/instance-queue-length.svg" width="450" alt="Graph of Request Queue Length (Per Instance). X-axis represents time, and y-axis spans from 0 to 5 requests enqueued. Three hypothetical service instances are plotted, with queue lengths that vary from 0 to 3 requests. Crucially: the queue lengths for each service are different, and constantly fluctuating, a symptom of uneven load balancing." />

### Load Balancing Strategies

So we need to ensure that the load is evenly distributed across instances. Not wishing to repeat past mistakes, I began researching load balancing strategies. This is a really fascinating topic, and if you're interested in learning more, I highly recommend Tyler McMullen's presentation, _[Load Balancing is Impossible](https://www.infoq.com/presentations/load-balancing)_.

Unfortunately, there are so many permutations of load balancing strategies that it would be impossible to test them all in a production environment. The iteration cost for each strategy would be too great. So I followed Genius' lead and wrote a simple in-memory load balancing simulator which enabled me to experiment with dozens of strategies over the course of a few hours. This gave me much greater confidence in the shortlist of solutions that would be tested in production.

### Load Shedding With Random Retries

One clever solution involves configuring our React service to shed load, returning a `503 Service Unavailable` instead of queueing excess requests. The monolith would receive the `503` more or less immediately, and would then retry its request on a different, randomly selected node. Each retry has an exponentially decreasing probability of reaching another overloaded instance.

<img src="/images/scaling-react-server-side-rendering/load-shedding-503.svg" width="500" alt="Diagram of how load shedding can be used in conjunction with random retries to achieve a kind of load balancing. Monolith sends a request to an instance of a service, which responds with a 503 Service Unavailable, because it has too many requests in its queue. Monolith then retries its requests on a different, randomly selected instance. The second instance does not have a queue and so it happily responds with a cool, sunglasses emoji, or whatever other metaphor you want to use for a successful response. If you had requested a poop emoji, the response would be a poop emoji, but then it seem look like a failed response, so I went with sunglasses emoji instead." />

Unfortunately, when I simulated this approach I discovered that it was not the most efficient. It was certainly better than a single, random attempt, but it does not perform as well as a round-robin algorithm, for example.

There are a few reasons for this. First, each retry adds additional network latency to the ultimate response time. All other things being equal, an algorithm which does not issue redundant requests will not suffer this overhead.

<img src="/images/scaling-react-server-side-rendering/latency-adds-up.svg" width="500" alt="Diagram of how load shedding with random retries adds latency with each unsuccessful retry. Assumem 5ms latency for every request or response sent. Monolith sends a request to an instance of a service, which responds with a 503 Service Unavailable. Monolith then retries on a different instance, which responds successfully. The total network cost is 20ms, instead of the 10ms you would have suffered if there had been no retry. Neutral face emoji demonstrates the unsatisfactory delay. Really, you only need a couple of emojis to handle most situations. Smiley, frowny, neutral, poop, sunglasses. I guess poop emoji is usually smiling, but that's a technicality. Definitely the person looking back at poop is not smiling. Well, I guess that also depends. It's complicated. Let's move on." />

Second, as the cluster of service instances becomes saturated with traffic, the probability that a retry will reach a healthy instance decreases! Think about a 5 instance cluster, with 4 instances at capacity, unable to handle additional requests — the odds that a retry will reach the 1 available instance are only 20%! This means that some requests will suffer many retries in order to receive a response.

<img src="/images/scaling-react-server-side-rendering/probability.svg" width="650" alt="Diagram showing Monolith choosing randomly among 5 service instances for its next request. Instances have 3, 2, 1, 0, and 4 requests in queue, respectively. Random selection has a 20% chance of picking the instance with no requests in its queue, i.e. the 'best' instance. Of course, I love all my instances equally. None of them are truly the 'best'. Some are just more enqueued than others." />

This problem is less pronounced when you can scale horizontally, but hopefully the inefficiency of this solution is clear. I wanted to do better, if possible.

### Round-Robin

A much better approach is to route each request, in turn, to the next instance in the cluster, commonly known as a _round-robin_ algorithm.

<img src="/images/scaling-react-server-side-rendering/round-robin.svg" width="500" alt="Diagram of how round-robin load balancing works. Load balancer sends 9 requests to 3 service instances. Instance #1 receives requests 1, 4, and 7. Instance #2 receives requests 2, 5, and 8. Instance #3 receives requests 3, 6, and 9. Round-robin simply picks the next instance, in order, and sends a request to it. The result is an even distribution of requests across instances. I don't know why it's called round-robin, though. It doesn't have anything to do with robins. Or even Batman & Robin, which was mediocre at best. George Clooney is too pretty to be Batman." />

Round-robin guarantees that each service instance will receive exactly its fair share of requests. This is the simplest load balancing algorithm that we can honestly say is _balancing_ load in a meaningful way. Accordingly, it vastly outperforms random, and load shedding with random retries.

Deceptively, round-robin is not the absolute most efficient approach, because requests can vary in the amount of work that they require the server to perform. One request might require 5ms to render a single React component, while another may require 50ms to render a page filled with hundreds of components. This natural variance in per-request workload means that round-robin can send requests to instances which are still processing a previous request, while other instances remain idle. This is because round-robin does not take an instance's workload into account. It _strictly_ allocates requests as a blackjack dealer would deal cards: everybody gets the same number of cards, but some cards are better than others!

<img src="/images/scaling-react-server-side-rendering/blackjack.svg" width="300" alt="Comic of a blackjack dealer talking to a single player. 'Dealer has 20. You have... 96'. Caption underneath reads, 'Distributed systems blackjack.' I really messed up the bow tie on the dealer, but I'm too lazy to draw it again." />

### Join-Shortest-Queue

Obviously we can't speak of the "best" load balancing algorithm, because the "best" choice depends on your particular circumstances. But I would be remiss not to describe what is probably the most widely useful approach, which is a _join-shortest-queue_ strategy.

I'm going to lump a few variations of this strategy together. Sometimes we might use a _least-connections_, or a _join-idle-queue_ approach, but the unifying principle is the same: try to send requests to the instance which is least overloaded. We can use different heuristics to approximate "load", including the number of requests in the instance's queue, or the number of outstanding connections, or having each instance self-report when they are ready to handle another request.

<img src="/images/scaling-react-server-side-rendering/join-shortest-queue.svg" width="550" alt="Diagram of how join-shortest-queue load balancing works. Three service instances have 2, 3, and 1 requests enqueued, respectively. Load Balancer sends the next request to the instance with only 1 request in queue. It is observed that round-robin might pick the other two instances, because round-robin is about as good at load balancing as George Clooney is at playing Batman. Great actor, just not for Batman. Great actor, though." />

The join-shortest-queue approach outperforms round-robin because it attempts to take the per-request workload into account. It does this by keeping track of the number of responses it is waiting for from each instance. If one instance is struggling to process a gigantic request, its queue length will be 1. Meanwhile, another instance might complete all of its requests, reducing its queue length to 0, at which point the load balancer will prefer to send requests to it.

### Fabio

So how did we resolve our load balancing woes? We ended up implementing a round-robin load balancer, [Fabio](https://github.com/fabiolb/fabio), as a compromise solution, trading off performance for convenience.

While Fabio does not support a join-shortest-queue load balancing strategy, it integrates seamlessly with Consul, giving us [server-side service discovery](http://microservices.io/patterns/server-side-discovery.html). This means that our monolith can simply send requests to Fabio, and Fabio figures out both how to get them to the React service, and also how to balance the load in a reasonable way.

<img src="/images/scaling-react-server-side-rendering/fabio.svg" width="550" alt="Diagram of how Fabio acts as a load balancer within the architecture. Monolith sends requests to Fabio, which then contacts Consul to get the IP addresses and port numbers of the destination service instances. Fabio then forwards the request to a service instance, using a round-robin algorithm. Service instance sends a response to Fabio, which forwards it back to the Monolith. In reality the Consul service discovery lookups are cached, otherwise too much latency would be introduced. I reserve the right to simplify things for pedagogical purposes. If you don't like it, draw your own diagrams." />

Of course, in this configuration our load balancer becomes a single point of failure — if it dies, we can't render any web pages!

To provide an availability strategy, we implemented our Fabio load balancer as just another containerized service — load balancing as a service. The monolith would use Consul to discover a _random_ Fabio instance, and send requests to that instance. If a Fabio instance dies, Consul would automatically detect this and stop offering that instance as one of the random options. We tested failover in production by sending a small amount of traffic through Fabio, and then manually killing a Fabio instance. Consul would reliably recover from this failure within a couple of seconds. Not bad!

<img src="/images/scaling-react-server-side-rendering/fabio-failover.svg" width="600" alt="Diagram of how multiple Fabio instances provide failover capability. Monolith requests the IP and port of a Fabio instance from Consul. Meanwhile, a Fabio instance has exploded. Consul quickly detects that Fabio has exploded, and does not return that Fabio instance as an option for the Monolith to connect to. The Monolith is therefore unaware of the failure, and blissfully sends its traffic to one of the remaining Fabio instances. Fabio then forwards requests to the React service, which sends responses back to Fabio, which forwards them back to the Monolith." />

We might be tempted to assume that randomly selecting a load balancer would preserve the performance issue we are trying to solve, but in practice this is not a problem. Each instance of Fabio can easily accommodate all of the traffic destined for our React service cluster. If our load balancers are sufficiently fast, it doesn't matter if the load is evenly balanced across the load balancers themselves. We have multiple load balancers purely to provide failover capability.

### Great Success

When the new round-robin load balancing strategy was productionized and ramped up to 100% of traffic, our React service instance queue lengths were a sight to behold. All of the queues converged around the same length. The system works!

<img src="/images/scaling-react-server-side-rendering/queue-length-with-load-balancing.svg" width="450" alt="Graph of Request Queue Length (Per Instance). This time, with load balancing installed! X-axis is time, and y-axis is request queue length, from 0 to 5. Three service instance request queues are plotted, and you know what? They're all sitting steady at 2 requests in queue! Ideally we would have less than 1 request in queue, but the point is that with load balancing finally installed, no instance can become overloaded. Make sure to balance your loads, people." />

Even better, our original problem was solved: peak traffic response latency spikes smoothed out, and our 99th percentile latency dropped. Everything "just worked", as we had originally hoped.

<img src="/images/scaling-react-server-side-rendering/latency-with-load-balancing.svg" width="350" alt="Graph of Response Latency (ms) during the activation of load balancing. p50 response time is about 50ms, until load balancing is activated, at which point it drops to about 40ms. p99 response time is always erratic, and hovers around 350ms until load balancing is activated, after which it drops to around 200ms. A terrific win!" />

## Client-Side Rendering Fallback

### Elastic Inelasticity

The addition of load balancing to our system effectively solved our high latency issues, and the efficiency gains provided a modest amount of additional capacity. But we were still concerned about extraordinary scenarios. Bots would scrape our website, triggering a huge surge in requests. Seasonality, including holidays, could also trigger unexpected increases in traffic. We had enough server capacity to keep up with normal traffic growth, but we could only sleep easily with the knowledge that our system would be resilient under significantly higher load.

Ideally we would build an auto-scaling system which could detect surges in traffic, and scale horizontally to accommodate them. Of course, this was not an option for us. We also couldn't simply provision 10x more capacity than required. Was there _any_ way we could add some kind of margin of safety? As it turns out, there was.

We couldn't shed load by dropping requests, but I started thinking about load shedding more generally, and I began to wonder if some kind of load _throttling_  would be possible. Late one evening, a solution popped into my head. We were using Redux, and one of the nice things about Redux is that it makes serialization of state very easy, enabling isomorphic rendering. We were rendering requests on the server, and then handling re-renders on the client, yet isomorphic rendering allows us to render on _either_ the server _or_ client. We don't always have to do both.

So the way to throttle load was profound in its simplicity: when the server is under high load, skip the server-side render, and force the browser to perform the initial render. In times of great need, our rendering capacity would automatically expand to include every single user's computer. We would trade a bit of page load speed for the ability to elastically scale on a fixed amount of hardware. Redux is the gift that just keeps on giving!

<img src="/images/scaling-react-server-side-rendering/server-side-rendering.svg" width="550" alt="Diagram of how React server-side rendering works. Browser sends a request to the Monolith, which requests some React component renders from the React service. The React service responds with the rendered components, serialized Redux store, and mounting instructions. These pieces are merged into a JSP template by the Monolith, and sent back to the browser. Pretty straightforward." />

<img src="/images/scaling-react-server-side-rendering/client-side-rendering-fallback.svg" width="550" alt="Diagram of how client-side rendering fallback works. Browser sends a request to the Monolith, which requests some React component renders from the React service. This time, the React service is under heavy load and skips the React component rendering, responding only with a serialized Redux store, and mounting instructions. These pieces are merged into a JSP template by the Monolith, and sent back to the browser. When React mounts in the browser, it performs an initial render, and the user can finally see a picture of a cat, or whatever they were looking for. That's really none of our business. We are in the React and Redux businesses, respectively." />

### How It Works

Building a client-side rendering fallback system is remarkably straightforward.

The Node server simply maintains a request queue length counter. For every request received, increment the counter, and for every error or response sent, decrement the counter. When the queue length is less than or equal to `n`, perform regular data fetching, Redux store hydration, and a server-side React render. When the queue length is greater than `n`, skip the server-side React rendering part — the browser will handle that, using the data from the Redux store.

<img src="/images/scaling-react-server-side-rendering/client-side-rendering-fallback-queue.svg" width="600" alt="Diagram of how client-side rendering fallback acts as a kind of load throttling. Monolith sends 7 requests to the React service. The first request is server-side rendered, because at that point in time, the service has 0 requests in queue. The next 6 requests are triaged and queued. The first 2 requests are queued for server-side rendering, because we have arbitrarily chosen a queue length of < 3 as our light load cutoff for server-side rendering. The next 3 requests are queued for client-side rendering, because we have arbitrarily chosen a queue length of < 6 as our heavy load cutoff for client-side rendering. The final request exceeds our maximum queue length, and is dropped in order to shed load." />

The exact value of `n` will need to be tuned to match the characteristics of your application. Generally speaking, `n` should be slightly larger than the typical queue length during peak expected load.

Of course, if SEO is a requirement, this approach contains a slight problem: if a search engine crawls the site during a traffic surge, it may not receive a server-side rendered response, and therefore it may not index your pages! Fortunately this is an easy problem to solve: provide an exception for known search engine user agent strings.

<img src="/images/scaling-react-server-side-rendering/club-react.svg" width="500" alt="Comic of people lined up to get into Club React. Google made it past the bouncer, who is speaking with the next person in line, who is arguing, 'I'm a friend of Google.'" />

There is a possibility that the search engine will punish our rankings for treating it differently than other clients. However, it is important to remember that the client-side rendering fallback exists to prevent us from dropping requests during traffic surges, or server failures. It is a safety net for rare, exceptional circumstances. The alternative is to risk sending _nothing_ to the crawler, which could also result in punishment. In addition, we aren't serving _different_ content to the search engine, we are merely providing it with priority rendering. Plenty of users will receive server-side rendered responses, but search engines will always receive one. And of course, it is easy to remove this priority if it is considered counter-productive.

### The Results

The day after we deployed client-side rendering fallback to production, a traffic spike occurred and the results were outstanding. The system performed exactly as we had hoped. Our React service instances automatically began delegating rendering to the browser. Client-side renders increased, while server-side request latency held roughly constant.

<img src="/images/scaling-react-server-side-rendering/client-side-render-requests.svg" width="350" alt="Graph of Requests Per Minute with client-side rendering fallback installed. X-axis is time, and y-axis ranges from 0 to 'lots' of requests. Two lines are plotted: total requests, and client-side rendered requests. Total requests is roughly constant until a big spike occurs, which lasts for a while, and then returns to normal levels. During the spike, client-side renders increase from 0 to a level which mirrors the increase in total requests. When the spike ends, client-side renders return to zero. The system works!" />

We benchmarked the efficiency gained through this approach, and found that it provides a roughly 8x increase in capacity. This system went on to save us multiple times over the next several months, including during a deployment error which significantly reduced the number of React service instances. I'm extremely pleased with the results, and I do recommend that you experiment with this approach in your own isomorphic rendering setup.

## Load Shedding

### Why You Need Load Shedding

Previously I mentioned that load shedding could be used in conjunction with random retries to provide an improvement over purely random load balancing. But even if a different load balancing strategy is used, it is still important to ensure that the React service can shed load by dropping excess requests.

We discovered this the hard way during a freak operations accident. A Puppet misconfiguration accidentally restarted Docker on every machine in the cluster, _simultaneously_. When Marathon attempted to restart the React service instances, the first ones to register with Consul would have 100% of the normal request load routed to them. A single instance could be swamped with 100x its normal request load. This is very bad, because the instance may then exceed the Docker container's memory limit, triggering the container's death. With one less active instance, the other instances are now forced to shoulder the additional load. If we aren't lucky, a cascade failure can occur, and the entire cluster can fail to start!

<img src="/images/scaling-react-server-side-rendering/cascade-failure.svg" width="550" alt="Diagram of how services which lack load shedding can experience a cascade failure when starting. Load Balancer sends a firehose of requests to one instance of React service, which enqueues as many as it can until its memory is exhausted and it explodes. Another instance of React service comes online, and the Load Balancer, with nowhere else to send its requests, directs the firehose toward this new instance, which promptly screams 'Crap!' The cycle continues until either you go out of business or somebody installs load shedding." />

Checking our graphs during this incident, I saw request queue lengths spike into the _thousands_ for some service instances. We were lucky the service recovered, and we immediately installed a load shedding mechanism to cap the request queue length at a reasonable number.

### Not So Fast

Unfortunately the Node event loop makes load shedding tricky. When we shed a request, we want to return a `503 Service Unavailable` response so that the client can implement its fallback plan. But we can't return a response until all earlier requests in the queue have been processed. This means that the `503` response will not be sent immediately, and could be waiting a long time in the queue. This in turn will keep the client waiting for a response, which could ruin its fallback plan, especially if that plan was to retry the request on a different instance.

<img src="/images/scaling-react-server-side-rendering/shed-queue.svg" width="400" alt="Diagram of an instance of React service which implements load shedding in conjunction with request queues. A request at the back of the queue, which is due to be shed, must wait for all of the other requests before actually being shed. Meanwhile, the developer also sheds... tears." />

If we want load shedding to be useful, we need to send the `503` response almost immediately after the doomed request is received.

### Interleaved Shedding

After a bit of brainstorming, I realized that we could provide fast shedding by interleaving request rendering and shedding.

I built a proof of concept by pushing all requests to be rendered into a rendering queue, implemented with a simple array. When a new request arrived, if the queue was smaller than `m` — where `m` is the maximum number of concurrent requests to accept — I would push the request object into the array. If the queue has grown too large, a `503` response is immediately sent.

When the server starts, I call a function which pulls a single request from the head of the rendering queue, and renders it. When the request has finished rendering, the response is sent, and the function is recursively called with `setImmediate()`. This schedules the next single request render _after_ the Node event loop processes accumulated I/O events, giving us a chance to shed the excess requests.

<img src="/images/scaling-react-server-side-rendering/interleaved-shedding.svg" class="breakout" alt="Diagram of how interleaved shedding works. 12 requests arrive as events in the Node event loop over time. If our max queue length is 3, the first 3 requests are placed into a rendering queue, which is implemented as an array. The next 3 requests are shed, with 503 responses sent for each. A setImmediate() callback, enqueued at application start, is then called, pulling request #1 from the render queue, rendering it, and sending a response to the client. The setImmediate() render callback recursively calls itself, enqueuing another render event behind requests 7 through 9, which arrived in the meantime. Request #7 is added to the render queue, bringing it back up to a maximum of 3 requests in queue. Requests #8 and #9 are shed, with 503 responses sent for each. The setImmediate() render callback is the next event in the Node event loop, and pulls request #2 from the render queue, rendering it, and sending a response. This cycle continues forever: render one request, then shed everything that doesn't fit in the render queue. This approach limits shed response latency to be approximately the processing time of the render request which lies ahead of it. This keeps our shed latency to reasonable, but not excellent, levels." />

The effect is that a single request is rendered, then _all_ excess requests are shed, then another single request is rendered, and so on. This approach limits the shed response latency to approximately the length of the request that was rendered before it.

Of course, it is possible to provide even faster shedding.

### I/O And Worker Processes

To achieve almost instantaneous load shedding, we refactored our application to spawn a [cluster](https://nodejs.org/api/cluster.html) of Node processes.

The idea was simple: dedicate one process exclusively to load shedding. When the service starts, the cluster master process forks a number of worker processes. The master process handles I/O, receiving incoming requests and immediately returning a `503` if the worker processes are too busy. If a worker is idle, the master process sends requests to it. The worker performs all of the heavy lifting, including React component rendering, and returns a response to the master. The master process finally sends the HTTP response to the client.

<img src="/images/scaling-react-server-side-rendering/io-worker.svg" width="500" alt="Diagram of how I/O and worker process architecture works, with 1 I/O process and 2 worker processes. Load Balancer sends 3 requests to the React service, which are received by its I/O process. The I/O process forwards requests #1 and #2 to each of the worker processes, but immediately sends a 503 response to shed request #3, since all of the workers are now considered busy. When the workers are finished processing requests #1 and #2, those responses are forwarded to the I/O process which sends them back to the Load Balancer for final delivery. This is a bit of a simplification: in reality, the I/O process can implement a queue so that you have a bit of elastic capacity in the event of fluctuating demand, or to implement a client-side rendering fallback threshold, etc." />

This is the approach we shipped to production. Although it is a bit more complicated, it gives us the flexibility to experiment with various numbers of worker processes. It is also important, when evolving towards a microservice architecture, to take the easy latency wins where we can have them.

## Component Caching

### The Idea Of Caching

Whenever we're attempting to improve performance, the topic of caching is going to come up. Out of the box, React server-side rendering performance is not nearly as fast as, say, a JSP template, and so there has been considerable interest in implementing caching strategies for React.

Walmart Labs has produced a very fancy [caching library](https://github.com/electrode-io/electrode-react-ssr-caching), `electrode-react-ssr-caching`, which provides caching of HTML output on a per-component basis. For dynamic rendering, prop values can either be cached or interpolated. It's a very impressive system.

And whoa, it's fast! Liberal use of caching can reduce render times to sub-millisecond levels. This is clearly the approach which offers the greatest performance gains.

### Two Hard Things In Computer Science

Unfortunately, this approach is not without its cost. To implement caching, `electrode-react-ssr-caching` relies on React private APIs, and mutates some of them. This effectively ties the library to React 15, since a complete rewrite of React's core algorithm shipped with React 16.

Even more pernicious, there is that old saw looming in the background:

> There are only two hard things in Computer Science: cache invalidation and naming things. — Phil Karlton

At it turns out, implementing caching on a per-component basis produces a lot of subtle problems.

### Caching And Interpolation

In order to cache a rendered React component, `electrode-react-ssr-caching` needs to know what to do with the component's props. Two strategies are available, "simple" and "template", but I will use the more descriptive terms, "memoization" and "interpolation".

Imagine a `<Greeting>` component, which renders a greeting for the user. To keep things simple, let's assume we only support English and French greetings. The component accepts a `language` prop, which could be either `en` or `fr`. Eventually, two versions of the component would be cached in memory.

When using the memoization strategy, the component is rendered normally, and one or more of its props are used to generate a cache key. Every time a relevant prop value changes, a different, rendered copy of the component is stored in the cache.

<img src="/images/scaling-react-server-side-rendering/memoization.svg" width="350" alt="Table illustrating that the 'Greeting_en' cache key corresponds with the '&lt;p&gt;Hello!&lt;/p&gt;' rendered component HTML, and the 'Greeting_fr' cache key corresponds with the '&lt;p&gt;Bonjour!&lt;/p&gt;' rendered component HTML." />

By contrast, the interpolation strategy treats the component as a template generation function. It renders the component once, stores the output in cache, and for subsequent renders it merges the props into the cached output.

<img src="/images/scaling-react-server-side-rendering/interpolation.svg" width="550" alt="'Greeting' cache key corresponds with the '&lt;p&gt;@1@&lt;/p&gt;' rendered component HTML template. When rendering a Greeting component with 'language' prop 'fr', the resulting HTML is '&lt;p&gt;fr&lt;/p&gt;', which is obviously not what we want. When rendering a Greeting component with 'language' prop 'Bonjour!', the resulting HTML is '&lt;p&gt;Bonjour!&lt;/p&gt;', which is the original intention." />

It is important to note that we can't simply pass a language code to the `<Greeting>` component when we are using interpolation. The _exact_ prop values are merged into the cached component template. In order to render English and French messages, we have to pass those exact messages into the component as props — conditional logic is not usable inside interpolated component `render()` methods.

### Murphy's Law

How do we choose between prop memoization and interpolation strategies for our cached components? A global configuration object stores the choice of strategy for each component. Developers must manually register components and their strategies with the caching config. This means that if, as a component evolves, its prop strategy needs to change, the developer must remember to update the strategy in the caching config. [Murphy's Law](https://en.wikipedia.org/wiki/Murphy%27s_law) tells us that sometimes we will forget to do so. The consequences of this dependence on human infallibility can be startling.

Let's say our `<Greeting>` component is using a memoization strategy for its props, and the `language` prop value is still being used to generate the cache key. We decide that we would like to display a more personalized greeting, so we add a second prop to the component, `name`.

<img src="/images/scaling-react-server-side-rendering/memoize-name.svg" width="480" alt="Rendering a memoized Greeting component which receives a 'language' prop of 'en', and a 'name' prop of 'Brutus', will result in '&lt;p&gt;Hello, Brutus!&lt;/p&gt;'." />

In order to accomplish this, we must update the component's entry in the caching config so that it uses the interpolation strategy instead.

But if we forget to update the strategy, _both prop values_ will be memoized. The first two user names to be rendered within the `<Greeting>` component will be cached, one per language, and will accidentally appear for all users!

<img src="/images/scaling-react-server-side-rendering/memoize-gone-wrong.svg" width="550" alt="Rendering a Greeting component which we intended to interpolate but accidentally memoized produces unexpected results. If the Greeting component receives a 'language' prop of 'en', and a 'name' prop of 'Brutus', and the cache key only takes the 'language' prop into account, it will result in '&lt;p&gt;Hello, Brutus!&lt;/p&gt;'. If the Greeting component is rendered a second time with 'name' prop set to 'Not Brutus', the same HTML output is produced." />

### Oh FOUC!

It gets worse. Since component caching is only used for server-side renders, and since all of our state is stored in Redux, when React mounts in the browser its virtual DOM will _not_ match the server-side rendered DOM! React will correct the situation by reconciling in favor of the virtual DOM. The user will experience something like a [flash of unstyled content (FOUC)](https://en.wikipedia.org/wiki/Flash_of_unstyled_content). The wrong name will appear for a split-second, and then the correct one will suddenly render!

<img src="/images/scaling-react-server-side-rendering/fouc.svg" width="650" alt="Diagram of how a flash-of-unstyled-content (FOUC) and SEO problems can manifest when using per-component caching. React Service renders a memoized component with the value 'Brutus', although 'Not Brutus' is the dynamic value which should have been rendered. This mistake is sent to the Monolith, which dutifully includes it in the response to the browser. The browser initially displays 'Brutus', but React detects a discrepancy between the virtual and real DOMs, and re-renders the component, finally and correctly displaying 'Not Brutus', albeit after a FOUC. Meanwhile, Google receives the cached, server-side rendered, mistaken 'Brutus' response and indexes it forever and ever." />

Now imagine that this content is being served to a search engine crawler. When a human looks at the page, they are unlikely to notice the error, because the client-side re-render fixes the issue in the blink of an eye. But search engines will index the incorrect content. We are in danger of shipping serious SEO defects, potentially for long periods of time, with no obvious symptoms.

### Exploding Cache

It gets even worse. Let's assume our application has one million users, and that we generate cache keys for the `<Greeting>` component using both `language` and `name` prop values. Accidentally forgetting to switch from memoization to interpolation means that the new `name` prop, which will be rendered with one million unique values, will generate one million cache entries. The cache has exploded in size!

<img src="/images/scaling-react-server-side-rendering/cache-explosion.svg" width="500" alt="Illustration huge explosion occurring on Earth due to passing millions of user names to an accidentally memoized component, which inflates memory usage until probably something explodes. Probably." />

If this accident exhausts available memory, the service will terminate. This failure will probably sneak up on us, as cache misses don't all occur at once.

Even if we set a maximum cache size and employ a cache replacement policy — such as _least recently used_ (LRU) — the cache explosion runs a serious risk of exhausting cache storage. Components that would have been cached are now competing for cache space with all of the other debris. Cache misses will increase, and rendering performance could severely degrade.

<img src="/images/scaling-react-server-side-rendering/warp-core.svg" width="300" alt="Comic of Star Trek bridge, with someone saying, 'Captain, our cache size has reached critical limits.' The Captain responds, 'Eject the warp core!' The caption reads, 'Don't let this happen to you.'" />

### Making The Opposite Mistake

Now let's imagine that we _do_ remember to update the caching config, changing the prop strategy to from memoization to interpolation for our `<Greeting>` component. If we do this, but forget to update the component's prop usage, we will ship a broken component to production.

Recall that interpolated prop values are merged as-is into the rendered component template. Conditional logic inside a component's `render()` method — such as the selection of a greeting based on the value of the `language` prop — will only ever execute _once_. If the first render happens to produce an English greeting, the template will be cached with the English greeting baked-in. For all subsequent renders, the user's name will be successfully interpolated, but the rest of the greeting will only ever render in English.

<img src="/images/scaling-react-server-side-rendering/broken-interpolation.svg" width="650" alt="Diagram of interpolated Greeting component with 'language' and 'name' props being rendered for the first time, with values 'en' and 'Brutus', respectively. The 'language' prop value does not appear in the rendered output, but is instead used in a conditional to select either a 'Hello' or 'Bonjour' greeting. The resulting template is '&lt;p&gt;Hello, @2@!&lt;/p&gt;'. The first interpolation of this template, using values 'en' and 'Brutus', produces the output '&lt;p&gt;Hello, Brutus!&lt;/p&gt;'. The second interpolation of this template, using values 'fr' and 'Brutus', produces the output '&lt;p&gt;Hello, Brutus!&lt;/p&gt;' again! This demonstrates how easy it is to introduce subtle bugs when using interpolation." />

### Cache Rules Everything Around Me

No matter which way we look at it, modifying the props of a cached component becomes fraught with danger. The developer must take special care to ensure that caching is correctly implemented for each component. React components experience a lot of churn as new features are added, so there are constant opportunities to make an innocuous change which destroys SEO performance, or destroys rendering performance, or renders incorrect data, or renders private user data for every user, or brings the UI down entirely.

Due to these problems, I'm not comfortable recommending per-component caching as a primary scaling strategy. The speed gains are incredible, and you should consider implementing this style of caching when you have run out of other options. But in my view, the biggest advantage of isomorphic rendering is that it unifies your codebase. Developers no longer need to cope with both client- and server-side logic, and the duplication that arrangement entails. The potential for subtle, pernicious bugs creates the need to think very carefully about both client- and server-side rendering, which is precisely the wasteful paradigm we were trying to get away from.

## Dependencies

### Don't Get Hacked

I would be remiss not to mention the disgustingly cheap performance wins we were able to achieve by keeping our dependencies up to date. Dependencies such as Node.js and React.

It is important to keep your dependencies up to date so that you don't get hacked. If you're on the fence about this, just ask Equifax [how well that worked out for them](https://www.nytimes.com/2017/09/14/business/equifax-hack-what-we-know.html).

<img src="/images/scaling-react-server-side-rendering/equifax.svg" width="250" alt="A newscaster sitting at their newscaster's desk reads the following cast of news. 'Equifax revealed that a cyberattack potentially compromised confidential information of 143 million Americans. The breach was open from mid-May to July 29. That was when Equifax first detected it. This security weakness was publicly identified in March and a patch to fix it had been available since then." />

### Do You Like Free Things?

_But that's not all!_ If you act now, your dependency upgrades will come with a free _performance boost!_

Because we were seeking to improve performance, we became interested in benchmarking upgrades to major dependencies. While your mileage may vary, upgrading from Node 4 to Node 6 decreased our response times by about 20%. Upgrading from Node 6 to Node 8 brought a 30% improvement. Finally, upgrading from React 15 to 16 yielded a 25% improvement. The cumulative effect of these upgrades is to more than _double_ our performance, and therefore our service capacity.

<img src="/images/scaling-react-server-side-rendering/dependencies.svg" width="350" alt="Bar graph entitled 'Response Latency', showing relative improvements in response latency as dependencies are upgraded to newer major versions over time. Upgrading Node 4 + React 15 to Node 6 produced a 20% improvement in response times. Upgrading to Node 8 produced a further 30% improvement. Upgrading Node 8 + React 15 to React 16 produced another 25% improvement. That's a lot of free performance! Thanks, open source buddies!" />

Profiling your code can be important, as well. But the open source community is a _vast_ ocean of talent. Very smart people are working incredibly hard, often for free, to speed up your application for you. They're standing on the corner of a busy intersection, handing out free performance chocolate bars. Take one, and thank them!

<img src="/images/scaling-react-server-side-rendering/free-performance.svg" width="350" alt="Comic of person handing out free performance chocolate bars to a turtle, saying, 'Free performance?' An arrow points out that the turtle is an 'Insecure turtle.' Slow, and without the latest dependencies, also insecure. Get it? GET IT? OH COME ON!!!1" />

## Isomorphic Rendering

### The Browser As Your Server

Isomorphic rendering is a huge simplicity booster for developers, who for too long have been forced to maintain split templates and logic for both client- and server-side rendering contexts. It also enables a dramatic reduction in server resource consumption, by offloading re-renders onto the web browser. The first page of a user's browsing session can be rendered server-side, providing a first-render performance boost along with basic SEO. All subsequent page views may then fetch their data from JSON endpoints, rendering exclusively within the browser, and managing browser history via the history API.

<img src="/images/scaling-react-server-side-rendering/ssr-csr.svg" width="550" alt="Diagram illustrating how isomorphic rendering works. For the first page viewed, the browser sends a request to the Monolith, in this case for the /home page. The Monolith then requests that a Home component be rendered by the React service, which performs a server-side render and returns the result. The Monolith integrates this result into its response to the browser, and the user can now see the first page of their session. When the user navigates to their next page, the /search page, our React client-side app notices this, fetches data from the Monolith, and renders the page entirely on the client. Client-side renders are ideally used for every page in the session, except for the first one." />

If a typical user session consists of 5 page views, rendering only the first page server-side will reduce your server resource consumption by 80%. Another way to think of this is that it would achieve a 5x increase in server-side rendering capacity. This is a huge win!

### Pairs Of Pages

Evolving toward this capability in a legacy application requires patience. A big-bang rewrite of the front-end, in addition to being incredibly risky, is usually off the table because it is a very expensive prospect. A long-term, incremental strategy is therefore required.

I think it makes sense to conceive of this problem in terms of _pairs_ of pages. Imagine a simple, e-commerce website, with home, search results, and individual product pages.

<img src="/images/scaling-react-server-side-rendering/page-flow.svg" width="330" alt="Diagram of a common web page architecture, with many users starting on the Home page, proceeding to the Search page, which displays search results, and then finally ending up on a Product page." />

If you upgrade both the home and search results pages to take advantage of isomorphic rendering, most users will hit the homepage first and can therefore render the search results page entirely within the browser. The same is true for the search results and product page combination.

<img src="/images/scaling-react-server-side-rendering/strategic-page-pairings.svg" width="380" alt="Diagram of the Home, Search, Product page user flow, with the Home-Search and Search-Product page pairings highlighted. Ideally pages will transition to an isomorphic rendering strategy in adjacent pairs, such as those identified here." />

But it's easy to miss out on these strategic pairings. Let's say your search results page is where all of the money is made, and so the product team is hesitant to modify it. If we invest our time into improving the home and product pages, making them isomorphic in the process, we won't see much uptake in client-side rendering. This is because in order to get from the homepage to a product page, most users will navigate _through_ a search results page. Because the search results page is not isomorphic, a server-side render will be required. If we're not careful, it's easy to perform a kind of inverse [Pareto optimization](https://en.wikipedia.org/wiki/Pareto_principle), investing 80% of the resources to achieve only 20% of the gains.

<img src="/images/scaling-react-server-side-rendering/inefficient-pairing.svg" width="300" alt="Diagram of the Home, Search, Product page user flow, with the Home and Product pages having transitioned to an isomorphic rendering strategy, while the Search page remains server-side only. Since few users jump from the Home page to a Product page, client-side rendering cannot do much to reduce our server-side rendering load. Since many users progress from the Home page through Search to a Product page, these users are forced to experience a server-side render and full page refresh when transitioning into and out of the Search page." />

## The Aggregation Of Marginal Gains

It is astonishing how a large number of small improvements, when compounded, can add up to produce one enormous performance boost. I recently learned that the term _aggregation of marginal gains_ describes this phenomenon. It is famously associated with Dave Brailsford, head of British Cycling, who [used this philosophy](https://hbr.org/2015/10/how-1-performance-improvements-led-to-olympic-gold) to turn the British Cycling team into a dominant force.

It is important to emphasize the _compounding_ effect of these gains. If we implement two improvements which, in isolation, double performance, combining them will _quadruple_ performance. Various fixed costs and overhead will affect the final result, but in general this principle applies.

Human psychology seems at odds with this approach. We tend to prefer quick wins, and short-term improvements. We tend not to consider a long-term roadmap of improvements in aggregate, and certainly not their compounding effects. These tendencies discourage us from exploring viable strategies. Comparing React server-side rendering to traditional server-rendered templating, React at first seems like it "doesn't scale". But as we layer performance improvement techniques, we can see that we have enormous performance headroom.

How much performance can we gain? And in which order should we pursue these techniques? Ultimately, the exact techniques and their order of implementation will depend on your specific situation. Your mileage may vary. But as a generic starting point from which to plan your journey, I recommend the following approach.

1. First, upgrade your Node and React dependencies. This is likely the easiest performance win you will achieve. In my experience, upgrading from Node 4 and React 15, to Node 8 and React 16, increased performance by approximately 2.3x.
2. Double-check your load balancing strategy, and fix it if necessary. This is probably the next-easiest win. While it doesn't improve average render times, we must always provision for the worst-case scenario, and so reducing 99th percentile response latency counts as a capacity increase in my book. I would conservatively estimate that switching from random to round-robin load balancing bought us a 1.4x improvement in headroom.
3. Implement a client-side rendering fallback strategy. This is fairly easy if you are already server-side rendering a serialized Redux store. In my experience, this provides a roughly 8x improvement in emergency, elastic capacity. This capability can give you a lot of flexibility to defer other performance upgrades. And even if your performance is fine, it's always nice to have a safety net.
4. Implement isomorphic rendering for entire pages, in conjunction with client-side routing. The goal here is to server-side render only the first page in a user's browsing session. Upgrading a legacy application to use this approach will probably take a while, but it can be done incrementally, and it can be Pareto-optimized by upgrading strategic pairs of pages. All applications are different, but if we assume an average of 5 pages visited per user session, we can increase capacity by 5x with this strategy.
5. Install per-component caching in low-risk areas. I have already outlined the pitfalls of this caching strategy, but certain rarely modified components, such as the page header, navigation, and footer, provide a better risk-to-reward ratio. I saw a roughly 1.4x increase in capacity when a handful of rarely modified components were cached.
6. Finally, for situations requiring both maximum risk and maximum reward, cache as many components as possible. A 10x or greater improvement in capacity is easily achievable with this approach. It does, however, require very careful attention to detail.

<img src="/images/scaling-react-server-side-rendering/1288x.svg" width="450" alt="Bar graph of relative capacity increase provided by compounding each successive technique. Baseline is 1x. Upgrading Dependencies produces another 2.3x improvement for 2.3x total capacity. Fixing Load Balancing produces another 1.4x improvement for 3.2x total capacity. Client-Side Fallback produces another 8x improvement for 25x total capacity. Isomorphic rendering produces another 5x improvement for 128x total capacity. Some Caching produces another 1.4x improvement for 180x total capacity. Maximum Caching produces a 10x improvement on top of all other techniques, for 1288x total capacity. All bars are rendered as precariously stacked React service instances. Maximum Caching bar contains a stick figure holding up some of the instances, in a nod to the ongoing maintenance that technique requires." />

Given reasonable estimates, when we compound these improvements, we can achieve an astounding 1288x improvement in total capacity! Your mileage will of course vary, but a three orders of magnitude improvement can easily change your technology strategy.

## All Your Servers Are Belong To Redux

I feel a lot better about the viability of React server-side rendering, now that I have waded through the fires and come out with only minor burns. As with virtually everything in the world of technology, exploring an approach for the first time carries the bulk of the cost. But even if you leave it to somebody else to blaze the trails, there will still be a first time for _you_. You can't escape that. Waiting for other people to perfect the backstroke is a very slow way to learn how to swim.

<img src="/images/scaling-react-server-side-rendering/swimming.svg" width="550" alt="Comic of a beach, with a body of water in the background. Lots of people are swimming and playing in the water, while a single person stands on the beach and addresses the reader: 'I'm not sure that swimming is production-ready yet.' The sun shines in the sky, wearing sunglasses, as suns do." />

I know so much more about this topic than I did when I first started. This isn't to say that my next attempt will be devoid of problems, but knowing exactly where many trap doors and power-ups lie could easily make the next project an order of magnitude cheaper. I'm looking forward to a world where, rather than something to aspire towards, component-oriented, isomorphic architecture is the standard approach. We're getting there!

P.S. Thank you very much for taking the time to read this far! It means a lot to me! I just happen to be in the market for new opportunities, so if you've enjoyed this article, and you'd like to work with me, please don't hesitate to [reach out](https://twitter.com/arkwrite). Have yourself an awesome day!
