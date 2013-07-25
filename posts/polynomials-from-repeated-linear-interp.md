-title=Polynomials from repeated linear interpolation
-time=2012-08-06 06:56:00
It's fairly well\-known that Bezier curves can be evaluated using repeated linear interpolation \- de Casteljau's algorithm. It's also fairly well\-known that a generalization of this algorithm can be used to evaluate B\-Splines: de Boor's algorithm. What's not as well known is that it's easy to construct interpolating polynomials using a very similar approach, leading to an algorithm that is, in a sense, halfway between the two.

In the following, I'll write $$l(\alpha,x,y) := (1 - \alpha)x + \alpha y$$ for linear interpolation. I'll stick with quadratic curves since they are the lowest\-order curves to show "interesting" behavior for the purposes of this article; everything generalizes to higher degrees in the obvious way.

### De Casteljau's algorithm

De Casteljau's algorithm is a well\-known algorithm to evaluate Bezier Curves. There's plenty of material on this elsewhere, so as usual, I'll keep it brief. Assume we have three control points $$x_0, x_1, x_2$$. In the first stage, we construct three constant \(degree\-0\) polynomials for the three control points:

$$p_0^{[0]}(t) = x_0$$
<br>$$p_1^{[0]}(t) = x_1$$
<br>$$p_2^{[0]}(t) = x_2$$

These are then linearly interpolated to yield two linear \(degree\-1\) polynomials:

$$p_0^{[1]}(t) = l(t, p_0^{[0]}(t), p_1^{[0]}(t))$$
<br>$$p_1^{[1]}(t) = l(t, p_1^{[0]}(t), p_2^{[0]}(t))$$

which we then interpolate linearly again to give the final result

$$p_0^{[2]}(t) = l(t, p_0^{[1]}(t), p_1^{[1]}(t)) = B(t).$$

Note I give the construction of the full polynomials here; the actual de Casteljau algorithm gets rid of them immediately by evaluating all of them as soon as they appear \(only ever doing linear interpolations\). Anyway, the general construction rule we've been following is this:

$$p_i^{[d]}(t) = l(t, p_i^{[d-1]}(t), p_{i+1}^{[d-1]}(t))$$

### De Boor's algorithm

De Boor's algorithm is the equivalent to de Casteljau's algorithm for B\-Splines. Again, there's plenty of material out there on it, so I'll keep it brief: We again start with constant functions for our data points. This time, the exact formulas depend on the degree of the spline we'll be using. I'll be using the degree $$k=2$$ \(quadratic\) here. We'll also need a *knot vector* $$(t_i)$$ which determines where our knots are; knots are \(very roughly\) the t's corresponding to the control points. I'll be using slightly different indexing from what's normally used to make the similarities more visible, and ignore issues such as picking the right set of control points to interpolate from:

$$p_0^{[0]}(t) = x_0$$
<br>$$p_1^{[0]}(t) = x_1$$
<br>$$p_2^{[0]}(t) = x_2$$

Then we linearly interpolate based on the knot vector:

$$p_0^{[1]}(t) = l((t - t_0) / (t_2 - t_0), p_0^{[0]}(t), p_1^{[0]}(t))$$
<br>$$p_1^{[1]}(t) = l((t - t_1) / (t_3 - t_1), p_1^{[0]}(t), p_2^{[0]}(t))$$

and interpolate again one more time to get the results:

$$p_0^{[2]}(t) = l((t - t_1) / (t_2 - t_1), p_0^{[1]}(t), p_1^{[1]}(t))$$

The general recursion formula for de Boor's algorithm \(with this indexing convention, which is non\-standard, so do **not** use this for reference!\) is this:

$$p_i^{[d]}(t) = l((t - t_{i+d-1}) / (t_{i+k} - t_{i+d-1}), p_i^{[d-1]}(t), p_{i+1}^{[d-1]}(t))$$

### Interpolating polynomials from linear interpolation

There's multiple constructions for interpolating polynomials; the best\-known are probably the [Lagrange polynomials](http://en.wikipedia.org/wiki/Lagrange_polynomial) \(which form a basis for the interpolating polynomials of degree n for a given set of *nodes* $$t_i$$\) and the [Newton polynomials](http://en.wikipedia.org/wiki/Newton_polynomials) \(since polynomial interpolation has unique solutions, these give the same results, but the Newton formulation is more suitable for incremental evaluation\).

What's less well known is that interpolating polynomials also obey a simple triangular scheme based on repeated linear interpolation: Again, we start the same way with constant polynomials

$$p_0^{[0]}(t) = x_0$$
<br>$$p_1^{[0]}(t) = x_1$$
<br>$$p_2^{[0]}(t) = x_2$$

and this time we have associated nodes $$t_0, t_1, t_2$$ and want to find the interpolating polynomial $$I(t)$$ such that $$I(t_0)=x_0$$, $$I(t_1)=x_1$$, $$I(t_2)=x_2$$. Same as before, we first try to find linear functions that solve part of the problem. A reasonable choice is:

$$p_0^{[1]}(t) = l((t - t_0) / (t_1 - t_0), p_0^{[0]}(t), p_1^{[0]}(t))$$
<br>$$p_1^{[1]}(t) = l((t - t_1) / (t_2 - t_1), p_1^{[0]}(t), p_2^{[0]}(t))$$

Note the construction here. $$p_0^{[1]}$$ is a linear polynomial that interpolates the data points $$(t_0,x_0), (t_1,x_1)$$, and we get it by interpolating between two simpler \(degree\-0\) polynomials that interpolate only $$(t_0,x_0)$$ and $$(t_1,x_1)$$, respectively: we simply make sure that at $$t=t_0$$, we use $$p_0^{[0]}$$, and at $$t=t_1$$, we use $$p_1^{[0]}$$. All of this is easiest to visualize when $$t_0 \le t_1 \le t_2$$, but it in facts works with them in any order. $$p_1^{[1]}$$ is constructed the same way.

To construct our final interpolating polynomial, we use the same trick again:

$$p_0^{[2]}(t) = l((t - t_0) / (t_2 - t_0), p_0^{[1]}(t), p_1^{[1]}(t)) = I(t).$$

Note this one is a bit subtle. We linearly interpolate between two polynomials that both in turn interpolate $$(t_1,x_1)$$; this means we already know that the result will also pass through this point. So $$t_1$$ is taken care of, and we only need to worry about $$t_0$$ and $$t_2$$ \- and for each of the two, one of our two polynomials does the job, so we can do the linear interpolation trick again. The generalization of this approach to higher degrees requires that we make sure that both of our input polynomials at every step interpolate all of the middle points, so we only need to fix up the ends. But this is easy to arrange \- the general pattern should be clear from the construction above. This gives us our recursive construction rule:

$$p_i^{[d]}(t) = l((t - t_i) / (t_{i+d} - t_i), p_i^{[d-1]}(t), p_{i+1}^{[d-1]}(t))$$

All of this is, of course, not new; in fact, this is just [Neville's algorithm](http://en.wikipedia.org/wiki/Neville%27s_algorithm). But in typical presentations, this is derived purely algebraically from the properties of Newton interpolation and divided differences, and it's not pointed out that the linear combination in the recurrence is, in fact, a linear interpolation \- which at least to me makes everything much easier to visualize.

### The punchline

The really interesting bit to me though is that, starting from the exact same initial conditions, we get three different important interpolation / approximation algorithms that differ only in how they choose their interpolation factors:

de Casteljau: $$p_i^{[d]}(t) = l(t, p_i^{[d-1]}(t), p_{i+1}^{[d-1]}(t))$$
<br>Neville: $$p_i^{[d]}(t) = l((t - t_i) / (t_{i+d} - t_i), p_i^{[d-1]}(t), p_{i+1}^{[d-1]}(t))$$
<br>de Boor: $$p_i^{[d]}(t) = l((t - t_{i+d-1}) / (t_{i+k} - t_{i+d-1}), p_i^{[d-1]}(t), p_{i+1}^{[d-1]}(t))$$

I think this quite pretty. B\-Splines with the right knot vector \(e.g. \[0,0,0,1,1,1\] for the quadratic curves we've been using\) are just Bezier Curves, that bit is well known. But what's less well known is that Neville's Algorithm \(and hence regular polynomial interpolation\) is just another triangular linear interpolation scheme that fits inbetween the two.