-title=Optimizing Software Occlusion Culling: The Reckoning
-time=2013-03-10 09:59:27
*This post is part of a series \- go [here](*optimizing-sw-occlusion-culling-index) for the index.*

Welcome back! Last time, I promised to end the series with a bit of reflection on the results. So, time to find out how far we've come!

### The results

Without further ado, here's the breakdown of per\-frame work at the end of the respective posts \(names abbreviated\), in order:

<table>
  <tbody><tr>
    <th>Post</th><th>Cull / setup</th><th>Render depth</th><th>Depth test</th><th>Render scene</th><th>Total</th>
  </tr>
  <tr>
    <td>Initial</td><td>1.988</td><td>3.410</td><td>2.091</td><td>5.567</td><td>13.056</td>
  </tr>
  <tr>
    <td>Write Combining</td><td>1.946</td><td>3.407</td><td>2.058</td><td>3.497</td><td>10.908</td>
  </tr>
  <tr>
    <td>Sharing</td><td>1.420</td><td>3.432</td><td>1.829</td><td>3.490</td><td>10.171</td>
  </tr>
  <tr>
    <td>Cache issues</td><td>1.045</td><td>3.485</td><td>1.980</td><td>3.420</td><td>9.930</td>
  </tr>
  <tr>
    <td>Frustum culling</td><td>0.735</td><td>3.424</td><td>1.812</td><td>3.495</td><td>9.466</td>
  </tr>
  <tr>
    <td>Depth buffers 1</td><td>0.740</td><td>3.061</td><td>1.791</td><td>3.434</td><td>9.026</td>
  </tr>
  <tr>
    <td>Depth buffers 2</td><td>0.739</td><td>2.755</td><td>1.484</td><td>3.578</td><td>8.556</td>
  </tr>
  <tr>
    <td>Workers 1</td><td>0.418</td><td>2.134</td><td>1.354</td><td>3.553</td><td>7.459</td>
  </tr>
  <tr>
    <td>Workers 2</td><td>0.197</td><td>2.217</td><td>1.191</td><td>3.463</td><td>7.068</td>
  </tr>
  <tr>
    <td>Dataflows</td><td>0.180</td><td>2.224</td><td>0.831</td><td>3.589</td><td>6.824</td>
  </tr>
  <tr>
    <td>Speculation</td><td>0.169</td><td>1.972</td><td>0.766</td><td>3.655</td><td>6.562</td>
  </tr>
  <tr>
    <td>Mopping up</td><td>0.183</td><td>1.940</td><td>0.797</td><td>1.389</td><td>4.309</td>
  </tr>
  <tr>
    <td><b>Total diff.</b></td><td>-90.0%</td><td>-43.1%</td><td>-61.9%</td><td>-75.0%</td><td>-67.0%</td>
  </tr>
  <tr>
    <td><b>Speedup</b></td><td>10.86x</td><td>1.76x</td><td>2.62x</td><td>4.01x</td><td>3.03x</td>
  </tr>
</tbody></table>

What, you think that doesn't tell you much? Okay, so did I. Have a graph instead:

![Time breakdown over posts](wpmedia/post_breakdown1.png)

The image is a link to the full\-size version that you probably want to look at. Note that in both the table and the image, updating the depth test pass to use the rasterizer improvements is chalked up to "Depth buffers done quick, part 2", not "The care and feeding of worker threads, part 1" where I mentioned it in the text.

From the graph, you should clearly see one very interesting fact: the two biggest individual improvements \- the write combining fix at 2.1ms and "Mopping up" at 2.2ms \- both affect the *D3D rendering code*, and don't have anything to do with the software occlusion culling code. In fact, it wasn't until "Depth buffers done quick" that we actually started working on that part of the code. Which makes you wonder...

### What\-if machine

Is the software occlusion culling actually worth it? That is, how much do we actually get for the CPU time we invest in occlusion culling? To help answer this, I ran a few more tests:

<table>
  <tbody><tr>
    <th>Test</th><th>Cull / setup</th><th>Render depth</th><th>Depth test</th><th>Render scene</th><th>Total</th>
  </tr>
  <tr>
    <td>Initial</td><td>1.988</td><td>3.410</td><td>2.091</td><td>5.567</td><td>13.056</td>
  </tr>
  <tr>
    <td>Initial, no occ.</td><td>1.433</td><td>0.000</td><td>0.000</td><td>25.184</td><td>26.617</td>
  </tr>
  <tr>
    <td>Cherry-pick</td><td>1.548</td><td>3.462</td><td>1.977</td><td>2.084</td><td>9.071</td>
  </tr>
  <tr>
    <td>Cherry-pick, no occ.</td><td>1.360</td><td>0.000</td><td>0.000</td><td>10.124</td><td>11.243</td>
  </tr><tr>
    <td>Final</td><td>0.183</td><td>1.940</td><td>0.797</td><td>1.389</td><td>4.309</td>
  </tr>
  <tr>
    <td>Final, no occ.</td><td>0.138</td><td>0.000</td><td>0.000</td><td>6.866</td><td>7.004</td>
  </tr>
</tbody></table>

Yes, the occlusion culling was a solid win both before and after. But the interesting value is the "cherry\-pick" one. This is the original code, with only the following changes applied: \(okay, and also with the timekeeping code added, in case you feel like nitpicking\)

* [Don't read back from the constant buffers we're writing](https://github.com/rygorous/intel_occlusion_cull/commit/e1839f69cf0680ad3339a5aa0f0b633bf71bcb68). Total diff: 3 lines.
* [Don't update debug counters in CPUTFrustum](https://github.com/rygorous/intel_occlusion_cull/commit/1e1b5cca743c5ce26d2d5e8570f1ac689b5ce7fb). Total diff: 2 lines.
* [Use only one dynamic constant buffer](https://github.com/rygorous/intel_occlusion_cull/commit/2504647a050e8c56ef2c4b4e03cce2ca7608343e). Total diff: 10 lines changed, 8 added.
* [Load materials only once](https://github.com/rygorous/intel_occlusion_cull/commit/b4e29b2dfb43a040a9eb5ed5c074092766fe4ba7). Total diff: 7 lines changed, 1 added.
* [Share materials instead of cloning them](https://github.com/rygorous/intel_occlusion_cull/commit/464503ca5bd657d7d6c6dc9e8a9144e1f223a278). Total diff: 3 lines changed.
* [AABBoxRasterizer traversal fix](https://github.com/rygorous/intel_occlusion_cull/commit/aa09c99a361988c1e7dd8765c0cbb9bd3bb5d527) \- keep list of models instead of going over whole database every time. Total diff: 15 lines added, 18 deleted.

In other words, "Cherry\-pick" is within a few dozen lines of the original code, all of the changes are to "framework" code not the actual sample, and none of them do anything fancy. Yet it makes the difference between occlusion culling enabled and disabled shrink to about a 1.24x speedup, down from the 2x it was before!

### A brief digression

This kind of thing is, in a nutshell, the reason why graphics papers really need to come with source code. Anything GPU\-related in particular is *full* of performance cliffs like this. In this case, I had the source code, so I could investigate what was going on, fix a few problems, and get a much more realistic assessment of the gain to expect from this kind of technique. Had it just been a paper claiming a "2x improvement", I would certainly not have been able to reproduce that result \- note that in the "final" version, the speedup goes back to about 1.63x, but that's with a considerable amount of extra work.

I mention this because it's a very common problem: whatever technique the author of a paper is proposing is well\-optimized and tweaked to look good, whereas the things that it's being compared with are often a very sloppy implementation. The end result is lots of papers that claim "substantial gains" over the prior state of the art that somehow never materialize for anyone else. At one extreme, I've had one of my professors state outright at one point that he just stopped giving out source code to their algorithms because the effort invested in getting other people to successfully replicate his old results "distracted" him from producing new ones. \(I'm not going to name names here, but he later stated a several other things along the same lines, and he's probably the number one reason for me deciding against pursuing a career in academia.\)

To that kind of attitude, I have only one thing to say: If you care only about producing results and not independent verification, then you may be brilliant, but you are not a scientist, and there's a very good chance that your life's work is useless to anyone but yourself.

Conversely, exposing your code to outside eyes might not be the optimal way to stroke your ego in case somebody finds an obvious mistake :\), but it sure makes your approach a lot more likely to actually become relevant in practice. Anyway, let's get back to the subject at hand.

### Observations

The number one lesson from all of this probably is that there's lots of ways to shoot yourself in the foot in graphics, and that it's really easy to do so without even noticing it. So don't assume, *profile*. I've used a fancy profiler with event\-based sampling \(VTune\), but even a simple tool like Sleepy will tell you when a small piece of code takes a disproportionate amount of time. You just have to be on the lookout for these things.

Which brings me to the next point: you should always have an expectation of how long things should take. A common misconception is that profilers are primarily useful to identify the hot spots in an application, so you can focus your efforts there. Let's have another look at the very first profiler screenshot I posted in this series:

![Reading from write-combined memory](wpmedia/wc_slow1.png)

If I had gone purely by what takes the largest amount of time, I'd have started with the depth buffer rasterization pass; as you should well recall, it took me several posts to explain what's even going on in that code, and as you can see from the chart above, while we got a good win out of improving it \(about 1.1ms total\), doing so took lots of individual changes. Compare with what I *actually* worked on first \- namely, the Write Combining issue, which gave us a 2.1ms win for a three\-line change.

So what's the secret? Don't use a profile exclusively to look for hot spots. In particular, if your profile has the hot spots you expected \(like the depth buffer rasterizer in this example\), they're not worth more than a quick check to see if there's any obvious waste going on. What you really want to look for are *anomalies*: code that seems to be running into execution issues \(like `SetRenderStates` with the read\-back from write\-combined memory running at over 9 cycles per instruction\), or things that just shouldn't take as much time as they seem to \(like the frustum culling code we looked at for the next few posts\). If used correctly, a profiler is a powerful tool not just for performance tuning, but also to find deeper underlying architectural issues.

### While you're at it...

Anyway, once you've picked a suitable target, I recommend that you do not just the necessary work to knock it out of the top 10 \(or some other arbitrary cut\-off\). After "[Frustum culling: turning the crank](*frustum-culling-turning-the-crank)", a commenter asked why I would spend the extra time optimizing a function that was, at the time, only at the \#10 spot in the profile. A perfectly valid question, but one I have three separate answers to:

First, the answer I gave in the comments at the time: code is not just isolated from everything else; it exists in a context. A lot of the time in optimizing code \(or even just reading it, for that matter\) is spent building up a mental model of what's going on and how it relates to the rest of the system. The best time to make changes to code is while that mental model is still current; if you drop the topic and work somewhere else for a bit, you'll have to redo at least part of that work again. So if you have ideas for further improvements while you're working on code, that's a good time to try them out \(once you've finished your current task, anyway\). If you run out of ideas, or if you notice you're starting to micro\-optimize where you really shouldn't, then stop. But by all means continue while the going is good; even if you don't need that code to be faster now, you might want it later.

Second, never mind the relative position. As you can see in the table above, the "advanced" frustum culling changes reduced the total frame time by about 0.4ms. That's about as much as we got out of our first set of depth buffer rendering changes, even though it was much simpler work. Particularly for games, where you usually have a set frame rate target, you don't particularly care where exactly you get the gains from; 0.3ms less is 0.3ms less, no matter whether it's done by speeding up one of the Top 10 functions slightly or something else substantially!

Third, relating to my comment about looking for anomalies above: unless there's a really stupid mistake somewhere, it's fairly likely that the top 10, or top 20, or top whatever hot spots are actually code that does substantial work \- certainly so for code that other people have already optimized. However, most people do tend to work on the hot spots first when looking to improve performance. My favorite sport when optimizing code is starting in the middle ranks: while everyone else is off banging their head against the hard problems, I will casually snipe at functions in the 0.05%\-1.0% total run time range. This has two advantages: first, you can often get rid of a lot of these functions entirely. Even if it's only 0.2% of your total time, if you manage to get rid of it, that's 0.2% that are gone. It's usually a lot easier to get rid of a 0.2% function than it is to squeeze an extra 2% out of a 10%\-run time function that 10 people have already looked at. And second, the top hot spots are usually in leafy code. But down in the middle ranks is "middle management" \- code that's just passing data around, maybe with some minor reformatting. That's your entry point to re\-designing data flows: this is the code where subsystems meet \- the place where restructuring will make a difference. When optimizing interfaces, it's crucial to be working on the interfaces that actually have problems, and this is how you find them.

### Ground we've covered

Throughout this series, my emphasis has been on changes that are fairly high\-yield but have low impact in terms of how much disruption they cause. I also made no substantial algorithmic changes. That was fully intentional, but it might be surprising; after all, as any \(good\) text covering optimization will tell you, it's much more important to get your algorithms right than it is to fine\-tune your code. So why this bias?

Again, I did this for a reason: while algorithmic changes are indeed the ticket when you need large speed\-ups, they're also very context\-sensitive. For example, instead of optimizing the frustum culling code the way I did \- by making the code more SIMD\- and cache\-friendly \- I could have just switched to a bounding volume hierarchy instead. And normally, I probably would have. But there's plenty of material on bounding volume hierarchies out there, and I trust you to be able to find it yourself; by now, there's also a good amount of Google\-able material on "Data\-oriented Design" \(I dislike the term; much like "Object\-oriented Design", it means everything and nothing\) and designing algorithms and data structures from scratch for good SIMD and cache efficiency.

But I found that there's a distinct lack of material for the actual problem most of us actually face when optimizing: how do I make existing code faster without breaking it or rewriting it from scratch? So my point with this series is that there's a lot you can accomplish purely using fairly local and incremental changes. And while the actual changes are specific to the code, the underlying ideas are very much universal, or at least I hope so. And I couldn't resist throwing in some low\-level architectural material too, which I hope will come in handy. :\)

### Changes I intentionally did not make

So finally, here's a list of things I did *not* discuss in this series, because they were either too invasive, too tricky or changed the algorithms substantially:

* *Changing the way the binner works*. We don't need that much information per triangle, and currently we gather vertices both in the binner and the rasterizer, which is a fairly expensive step. I did implement a variant that writes out signed 16\-bit coordinates and the set\-up Z plane equation; it saves roughly another 0.1ms in the final rasterizer, but it's a fairly invasive change. Code is [here](https://github.com/rygorous/intel_occlusion_cull/tree/blog_past_the_end) for those who are interested. \(I may end up posting other stuff to that branch later, hence the name\).
* *A hierarchical rasterizer for the larger triangles*. Another thing I [implemented](https://github.com/rygorous/intel_occlusion_cull/tree/hier_rast) \(note this branch is based off a pre\-blog version of the codebase\) but did not feel like writing about because it took a lot of effort to deliver, ultimately, fairly little gain.
* *Other rasterizer techniques or tweaks*. I could have implemented a scanline rasterizer, or a different traversal strategy, or a dozen other things. I chose not to; I wanted to write an introduction to edge\-function rasterizers, since they're cool, simple to understand and less well\-known than they should be, and this series gave me a good excuse. I did not, however, want to spend more time on actual rasterizer optimization than the two posts I wrote; it's easy to spend years of your life on that kind of stuff \(I've seen it happen!\), but there's a point to be made that this series was already too long, and I did not want to stretch it even further.
* *Directly rasterizing quads in the depth test rasterizer*. The depth test rasterizer only handles boxes, which are built from 6 quads. It's possible to build an edge function rasterizer that directly traverses quads instead of triangles. Again, I wrote the code \(not on Github this time\) but decided against writing about it; while the basic idea is fairly simple, it turned out to be really ugly to make it work in a "drop\-in" fashion with the rest of the code. See [this comment](*reshaping-dataflows#comment-2466) and my reply for a few extra details.
* *Ray\-trace the boxes in the test pass instead of rasterizing them*. Another suggestion by [Doug](*reshaping-dataflows#comment-2466). It's a cool idea and I think it has potential, but I didn't try it.
* *Render a lower\-res depth buffer using very low\-poly, conservative models*. This is how I'd actually use this technique for a game; I think bothering with a full\-size depth buffer is just a waste of memory bandwidth and processing time, and we do spend a fair amount of our total time just transforming vertices too. Nor is there a big advantage to using the more detailed models for culling. That said, changing this would have required dedicated art for the low\-poly occluders \(which I didn't want to do\); it also would've violated my "no\-big\-changes" rule for this series. Both these changes are definitely worth looking into if you want to ship this in a game.
* *Try other occlusion culling techniques*. Out of the \(already considerably bloated\) scope of this series.

And that's it! I hope you had as much fun reading these posts as I did writing them. But for now, it's back to your regularly scheduled, piece\-meal blog fare, at least for the time being! Should I feel the urge to write another novella\-sized series of posts again in the near future, I'll be sure to let you all know by the point I'm, oh, nine posts in or so.