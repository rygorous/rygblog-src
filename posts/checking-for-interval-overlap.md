-title=Checking for interval overlap
-time=2011-10-17 06:15:17
This'll be a short post, based on a short exchange I recently had with a colleague at work \(hey Per!\). It's about a few tricks for checking interval overlaps that aren't as well\-known as they should be. \(Note: This post was originally written for [AltDevBlogADay](http://altdevblogaday.com/) and posted there first\).

The problem is very simple: We have two \(closed\) intervals $$ [a_0,a_1]$$ and $$ [b_0,b_1]$$ and want to find out if they overlap \(i.e. have a non\-empty intersection\). So how would you do it? A simple solution can be obtained directly from the definition: we first compute the intersection of the two intervals, then check whether it's non\-empty.

The code for this is straightforward, and I've seen it many times in various codebases:

```
i0 = max(a0, b0); // lower bound of intersection interval
i1 = min(a1, b1); // upper bound of intersection interval
return i0 <= i1;  // interval non-empty?
```

However, doing the check this way without a native "max" operation \(which most architectures don't provide for at least some types\) requires three comparisons, and sometimes some branching \(if the architecture also lacks conditional moves\). It's not a tragedy, but neither is it particularly pretty.

### Center and Extent

If you're dealing with floating\-point numbers, one reasonably well\-known technique is using center and extents \(actually half\-extents\) for overlap checks; this is the standard technique to check for collisions using Separating Axis Tests, for example. For closed and open intervals, the intuition here is that they can be viewed as 1D balls; instead of describing them by two points on their diameter, you can equivalently express them using their center and radius. It boils down to this:

```
float center0 = 0.5f * (a0 + a1);
float center1 = 0.5f * (b0 + b1);
float radius0 = 0.5f * (a1 - a0);
float radius1 = 0.5f * (b1 - b0);
return fabsf(center1 - center0) <= (radius0 + radius1);
```

This looks like a giant step back. Lots of extra computation! However, if you're storing \(open or closed\) intervals, you might as well use the Center\-Extent form in the first place, in which case all but the last line go away: a bit of math and just one floating\-point compare, which is attractive when FP compares are expensive \(as they often are\). However, this mechanism doesn't look like it's easy to extend to non\-floats; what about the multiply by 0.5? The trick here is to realize that all of the expressions involved are linear, so we might as well get rid of the scale by 0.5 altogether:

```
center0_x2 = a0 + a1;
center1_x2 = b0 + b1;
radius0_x2 = a1 - a0;
radius1_x2 = b1 - b0;
return abs(center1_x2 - center0_x2) <= (radius0_x2 + radius1_x2);
```

No scaling anymore, so this method can be applied to integer types as well as floating\-point ones, provided there's no overflow. In case you're wondering, there's efficient branch\-less ways to implement abs\(\) for both floats and integers, so there's no hidden branches here. Of course you can also use a branch\-less min/max on the original code snippet, but  the end result here will be a bit nicer than that. Because eliminating common terms yields:

```
t0 = b1 - a0;
t1 = a1 - b0;
return abs(t0 - t1) <= (t0 + t1);
```

I thought this was quite pretty when I stumbled upon it for the first time. It only does one comparison, so it's optimal in that sense, but it still involves a bit of arithmetic.

### Rephrasing the question

The key to a better approach is inverting the sense of the question: instead of asking whether two intervals overlap, try to find out when they don't. Now, intervals don't have holes. So if two intervals $$I_a=[a_0,a_1]$$ and $$I_b=[b_0,b_1]$$ don't overlap, that means that $$I_b$$ must be either fully to the left or fully to the right of $$I_a$$ on the real number line. Now, if $$I_b$$ is fully to the left of $$I_a$$, that means in particular that b's rightmost point $$b_1$$ must be to the left of a \- that is, smaller than $$a_0$$. And again, vice versa for the right side. So the two intervals *don't* overlap if either $$b_1 < a_0$$ or $$a_1 < b_0$$. Applying that to our original problem \(which involves negating the whole expression using de Morgan's laws\), this gives the following version of the interval overlap check:

```
return a0 <= b1 && b0 <= a1;
```

Which is about as simple as it gets.

Again, it's not earth\-shattering, but it's not at all obvious from the original snippet above that the test can be done this way, so the longer version tends to come up quite often \- even when the `max` and `min` operations use branches. It's generally worthwhile to know all three forms so you can use them when appropriate \- hence this post.