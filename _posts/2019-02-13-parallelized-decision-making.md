---
layout: post
title:  Parallelized Decision Making
---

# Parallelized Decision Making

I've noticed a common anti-pattern across teams and organizations I've been a part of: the desire to make decisions faster.

The logic seems sound at first. As team size grows it becomes increasingly difficult to reach a decision. Each additional team member we involve increases the odds that at least one person will strongly object to any given proposal. This is reminiscent of the [Birthday problem](https://en.wikipedia.org/wiki/Birthday_problem):

> For a group of 23 people, there is a 50% chance that 2 people will share the same birthday (day of the year). For a group of 70 people, there is a 99.9% chance.

This is a mind-blowing statistical phenomenon, but it's true.

Now contemplate for a moment that not only does everybody in a team have a birthday, they also have an _opinion_. It becomes easy to see why decision making becomes harder as group size increases: the odds that two contrary opinions will "collide" keep increasing.

Our initial strategy for resolving this conflict is to talk it out. This works for a while, but eventually the group becomes so large that reconciling all of our differences seems like it will take forever. Teams then desire to make decisions faster. They implement decision making heuristics which trade the consensus of the group for faster decision making. Indeed, the new system helps to mitigate the problem, and decisions are reached more rapidly than before.

This seems great, right? Why is it an anti-pattern? Why does it make things _worse_?

## You Asked For A Decision, You Needed A Solution

The subtle problem with trying to reach a decision is that a decision is not what is needed: the group needs a _solution_ to the problem they are facing.

A decision is not a solution. A decision is when a group reaches agreement regarding which approach is most likely to solve their problem. Whether or not it actually solves the problem is an _empirical_ question which can only be answered by implementing the solution and observing the results in the real world.

The real world is infinitely complex and unpredictable. Very often, ideas which seem like they cannot fail explode spectacularly when they smash into real life with all the velocity and enthusiasm of group consent. It is impossible to know in advance if something is going to work — we have to try it to find out.

When a group seeks to reach a decision faster, it accidentally switches to a subtle, insidious algorithm: it begins running its experiments in serial, rather than in parallel.

If you know anything about performance engineering, you know this approach absolutely _destroys_ performance. It obliterates the speed at which we are able to find solutions to our problems. The team thought getting to a decision faster would make everything go faster, but now everything is going slower. Whoah!

Okay that sounds reasonable, but a bit fuzzy. What does all this serial and parallel stuff _mean_? Preferably with pictures, please!

## Doing Things In Serial Is Slower Than Doing Them In Parallel

When we say that things are done in _serial_, we mean that they are done one at a time, one after the other.

When we say that things are done in _parallel_, we mean that they are all done at the same time, simultaneously.

Let's make that concrete with an example.

Imagine a hypothetical team which feels that its frontend data fetching technology has become a strategic bottleneck, and wants to replace it with something more efficient. Members of the team have proposed a variety of solutions to the problem, including the following technologies:

* GraphQL
* REST
* WebSockets
* BFF (Backend For Frontend)

If you don't know what these technologies are, don't worry. The only thing that matters is that they represent different potential solutions to the problem.

The team cannot agree on which approach would be best, and is getting frustrated with the process of settling on a solution. They built simple proofs of concept for most of these systems, but the examples did not resolve the decision making stalemate. Feeling out of time, they appeal to a single decision maker to break this deadlock. The decision maker thinks carefully and decides on REST. The team begins to make investments to integrate this technology into their process.

If we were to construct a Gantt chart illustrating the result of this decision, it would look like this:

<img src="/images/parallel-decision-making/rest.svg" width="550" class="image-left-align" alt="Gantt chart showing a 2 week period of deliberation, a decision to use REST, then a 4 month experimentation period with REST." />

_Four months_ go by. As with many technology rollouts, the team doesn't have time to stop existing work and switch all at once to use the new standard. Over these months the technology has been rolled out in various places. As usage increases, the team reaches an unsettling conclusion: the choice of REST is not working as well as they had hoped. REST looked good on the whiteboard, and the proof of concept made sense, but when it was tried in the real world a number of insurmountable problems revealed themselves.

A crisis of confidence ensues. The team debates switching to another technology. The case for doing so is made clear, and the team begins a second round of deliberation. The same technologies are available for consideration. Once again, the team cannot agree on which one will work best, and appeals to a single decision maker to break the deadlock. The single decision maker thinks carefully, and decides on BFF (Backend For Frontend) as the new standard.

The Gantt chart now looks like this:

<img src="/images/parallel-decision-making/rest_bff.svg" width="475" class="image-left-align" alt="Gantt chart showing a 2 week period of deliberation, a decision to use REST, then a 4 month experimentation period with REST. Then a crisis occurs, another 2 week deliberation period, a decision to use BFF, and a 6 month experimentation period with BFF." />

_Six months_ go by. Again, the team does not have resources to instantly migrate to the BFF standard, so the migration occurs in bits and pieces. Again, the team reaches an unsettling conclusion: the choice of BFF is not working as well as they had hoped. It showed promise to address the problems of the previous approach, but it did not work out in reality. This is getting really frustrating!

The team returns to deliberation. Deliberation is not easier than before, because so much time has passed that new technology choices have become available. This is made more complicated when some insist that the team should return to the way things were, before REST and the BFF, while others want to _move forward_ to use something like GraphQL or WebSockets. Once again, the team cannot reach a decision. One team member "goes rogue", taking the initiative and implementing a trial of GraphQL without the group's consent. The trial catches on and eventually becomes a de facto decision.

The Gantt chart now looks like this:

<img src="/images/parallel-decision-making/rest_bff_graphql.svg" width="650" class="image-left-align" alt="Gantt chart showing a 2 week period of deliberation, a decision to use REST, then a 4 month experimentation period with REST. Then a crisis occurs, another 2 week deliberation period, a decision to use BFF, and a 6 month experimentation period with BFF. Then another crisis occurs, another two week deliberation period, and a 4 month experimentation period with GraphQL, which ends up being the solution to the problem." />

_Four months_ go by. A grand total of 14 months have passed since the initial deliberations began. The team is beginning to enjoy the slow rollout of GraphQL. While it isn't perfect, it does feel clearly superior to the other technologies they have tried. Eventually GraphQL reaches enough critical mass within the team that it becomes infeasible to move away from it.

The team has finally reached a _solution_ to their problem. However, it took two official decisions, one quasi "decision", and 14 months of experimentation to reach this result.

It took more than one decision to achieve one solution.

It took 14 months to reach the solution because, as the diagrams above demonstrate, _the primary cost of reaching a solution is the duration of experiments_. Deliberation and decision making requires a negligible amount of time by comparison. If a team deliberates and decides 2 times, at a cost of 2 weeks each time, and implements 14 months (60 weeks) of experimental trials, the total time required to reach a solution was 64 weeks. Of this time, only 6% was spent deliberating and deciding. The other 94% was spent waiting for the results of experiments.

While waiting for a solution to be proven, the team and organization continued to pay a frustrating overhead cost in maintaining the old system, along with half-baked implementations of every prior experiment. This process was inefficient because these ongoing costs had to be paid until a solution could be reached.

This is the fundamental problem with running experiments in serial: because only one experiment runs at a time, the total time required to reach a solution is the _sum_ of the time spent waiting for each experiment.

So how do parallel experiments make this process faster?

Imagine that the team had _decided not to decide_. Imagine that they had internalized the idea that it was impossible to predict which technology would work best, even with a lightweight proof of concept available to study. They actually needed to _use_ every technology and observe the actual, real world consequences. Several of the approaches were expected to be ruled out due to unforeseen problems — problems which would only emerge and become visible under real world testing. A decision would then be largely unnecessary, since one approach would likely outperform the others. The "decision" is therefore not a choice that humans make, but a result that reveals itself naturally.

So the team does something incredibly counter-intuitive: they experiment with _every_ solution, simultaneously.

The team doesn't have enough bandwidth to try literally every conceivable technology, so they vote on which technology is most likely to work, and choose the top three for experimentation. WebSockets fails to make the cut. The team understands that it would be better to try more experiments, but they simply can't afford it.

After running the experiments in _parallel_, the Gantt chart looks like this:

<img src="/images/parallel-decision-making/parallelized.svg" width="650" class="image-left-align" alt="Gantt chart showing 4 month experimentation periods with REST, BFF, and GraphQL all occurring simultaneously. The REST trial is shorter than the others because it fails early. All of these are followed by a 2 week deliberation period, a decision to use GraphQL, and an implementation period for GraphQL, which extends to the end of the chart, as GraphQL is chosen as the solution. The chart is 14 months wide." />

_Four months_ go by, and although it is not perfect, the team enjoys broader consensus that GraphQL is the clear winner.

After three months the REST experiment was canceled, since a problem was discovered which would make its long-term usage impossible. Because two other experiments were ongoing, the team was less hesitant to abandon REST and gamble on another experiment. The team saved one month of experimental cost by "failing fast".

When the full four months had elapsed, the BFF had performed okay, but almost everybody agreed that GraphQL was clearly superior. Some team members wished for the BFF trial to continue, but they admitted that four months was already a reasonable length of time to trial each technology, and it seemed unreasonable to extend the experimental period. The BFF approach was therefore deprecated, and GraphQL was selected as the new standard for the team.

The team was able to accomplish all of this in 4 months (17 weeks), plus 2 weeks of deliberation to cement their decision. Compared with running the experiments in serial and making multiple decisions, the strategy of parallel experiments produced a solution 4 times faster.

The team was also able to reach a broader consensus, which was great for morale. Almost everybody was able to try their preferred technology, as well as try alternative technologies. Several people changed their opinions during this process, which increased their open-mindedness with respect to their peers' subsequent ideas, and decreased their personal sense of self-certainty.

The team and organization were able to implement the best technology and enjoy its cost savings 10 months sooner. They had less technical debt to clean up from the previous, failed experiments.

Another subtle but important benefit was realized: the team was able to extend the compound growth of their investment by an additional 10 months. Investing earlier allows the growth to compound longer. The largest gains come at the _end_ of the compound growth period.

<img src="/images/parallel-decision-making/compounding.svg" width="550" alt="Chart with time increasing on the x-axis and wealth increasing on the y-axis. An exponential curve of wealth growth is shown. The final 16% of the x-axis of the curve is shaded in, representing the 'short head' of the curve. An annotation describes this shaded area as: 10 more months of compound growth." />

Achieving an actual _solution_ earlier allows the team to receive a significantly higher return on their investment. Three years later, the team is shipping faster than ever before, due in part to their disciplined, parallelized experimental process — a process which seemed expensive in the short term, but was actually _much cheaper_ in the long term.

## Decisions Are The Problem, More Experiments Are The Solution

Hopefully I've made it clear that the goal of making a decision dramatically decreases experimental iteration speed, because it forces the experiments to occur in serial rather than in parallel.

Increasing the speed of experiments is arguably _the_ singular best way to improve team performance. Faster learning leads to faster breakthroughs, which leads to earlier benefits, which compound over time to produce massive wealth. An obsessive focus on short-term cost reduction leads directly to wealth reduction. A disciplined focus on _learning faster_ leads directly to wealth creation. Eric Ries has been [explaining this phenomenon](http://www.startuplessonslearned.com/2010/04/learning-is-better-than-optimization.html) for a long time, and I highly recommend his writing as an aid to internalizing this mindset.

## How Can I Get My Team To Do This?

The ideas in this article are counter-intuitive. Psychological experiments have pretty conclusively demonstrated that people are much more cost-averse than benefit-seeking. It will not be simple and straightforward to get your team to invest in a more scientific, empirical approach. Perhaps later I can elaborate on strategies for addressing this challenge. Please reach out if you'd like to see that, as it motivates me to write more!
