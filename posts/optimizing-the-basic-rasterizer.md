-parent=optimizing-sw-occlusion-culling-index
-title=Optimizing the basic rasterizer
-time=2013-02-10 11:30:16

[Last time](*triangle-rasterization-in-practice), we saw how to write a simple triangle rasterizer, analyzed its behavior with regard to integer overflows, and discussed how to modify it to incorporate sub\-pixel precision and fill rules. This time, we're going to make it run fast. But before we get started, I want to get one thing out of the way:

### Why this kind of algorithm?

The algorithm we're using basically loops over a bunch of candidate pixels and checks whether they're inside the triangle. This is not the only way to render triangles, and if you've written any software rendering code in the past, chances are good that you used a scanline rasterization approach instead: you scan the triangle from top to bottom and determine, for each scan line, where the triangle starts and ends along the x axis. Then we can just fill in all the pixels in between. This can be done by keeping track of so\-called active edges \(triangle edges that intersect the current scan line\) and tracking their intersection point from line to line using what is essentially a modified line\-drawing algorithm. While the high\-level overview is easy enough, the details get fairly subtle, as for example the [first](http://chrishecker.com/images/4/41/Gdmtex1.pdf) [two](http://chrishecker.com/images/9/97/Gdmtex2.pdf) articles from Chris Hecker's 1995\-96 series on perspective texture mapping explain \(links to the whole series [here](http://chrishecker.com/Miscellaneous_Technical_Articles)\).

More importantly though, this kind of algorithm is forced to work line by line. This has a number of annoying implications for both modern software and hardware implementations: the algorithm is asymmetrical in x and y, which means that a very skinny triangle that's mostly horizontal has a very different performance profile from one that's mostly vertical. The outer scanline loop is serial, which is a serious problem for hardware implementations. The inner loop isn't very SIMD\-friendly \- you want to be processing aligned groups of several pixels \(usually at least 4\) at once, which means you need special cases for the start of a scan line \(to get up to alignment\), the end of a scan line \(to finish the last partial group of pixels\), and short lines \(scan line is over before we ever get to an aligned position\). Which makes the whole thing even more orientation\-dependent. If you're trying to do mip mapping at the same time, you typically work on "quads", groups of 2x2 pixels \(explanation for why is [here](*a-trip-through-the-graphics-pipeline-2011-part-8)\). Now you need to trace out two scan lines at the same time, which boils down to keeping track of the current scan conversion state for both even and odd edges separately. With two lines instead of one, the processing for the starts and end of a scan line gets even worse than it already is. And let's not even talk about supporting pixel sample positions that aren't strictly on a grid, as for example used in multisample antialiasing. It all goes downhill fast.

I think I've made my point: while scan\-line rasterization works great when you're working one scan line at a time anyway, it gets hairy quickly once throw additional requirements such as "aligned access", "multiple rows at a time" or "variable sample position" into the mix. And it's not very parallel, which hamstrings our ability to harness wide SIMD or build efficient hardware for it. In contrast, the algorithm we've been discussing is embarrassingly parallel \- you can test as many pixels as you want at the same time, you can use arbitrary sample locations, and if you have specific alignment requirements, you can test pixels in groups that satisfy those requirements easily. There's a lot to be said for those properties, and indeed they've proven convincing enough that by now, the edge function approach is the method of choice in high\-performance software rasterizers \- in graphics hardware, it's been in use for a good while longer, starting in the late 80s \(yes, 80s \- not a typo\). I'll talk a bit more about the history later.

Right, however, now we still perform two multiplies and five subtractions per edge, per pixel. SIMD and dedicated silicon are one thing, but that's still a lot of work for a single pixel, and it most definitely was not a practical way to perform hardware rasterization in 1988. What we need to do now is drastically simplify our inner loop. Luckily, we've seen everything we need to do that already.

### Simplifying the rasterizer

If you go back to ["The barycentric conspiracy"](*the-barycentric-conspirac), you'll notice that we already derived an alternative formulation of the edge functions by rearranging and simplifying the determinant expression:

$$F_{01}(p) = (v_{0y} - v_{1y}) p_x + (v_{1x} - v_{0x}) p_y + (v_{0x} v_{1y} - v_{0y} v_{1x})$$

Now, to reduce the amount of noise, let's give those terms in parentheses names:

$$A_{01} := v_{0y} - v_{1y}$$
<br>$$B_{01} := v_{1x} - v_{0x}$$
<br>$$C_{01} := v_{0x} v_{1y} - v_{0y} v_{1x}$$

And if we split p into its x and y components, we get:

$$F_{01}(p_x, p_y) = A_{01} p_x + B_{01} p_y + C_{01}$$

Now, in every iteration of our inner loop, we move one pixel to the right, and for every scan line, we move one pixel up or down \(depending on which way your y axis points \- note I haven't bothered to specify that yet!\) from the start of the previous scan line. Both of these updates are really easy to perform since F<sub>01</sub> is an affine function and we're stepping along the coordinate axes:

$$F_{01}(p_x + 1, p_y) - F_{01}(p_x, p_y) = A_{01}$$
<br>$$F_{01}(p_x, p_y + 1) - F_{01}(p_x, p_y) = B_{01}$$

In words, if you go one step to the right, add A<sub>01</sub> to the edge equation. If you step down/up \(whichever direction \+y is in your coordinate system\), add B<sub>01</sub>. That's it. That's *all* there is to it.

In our basic triangle rasterization loop, this turns into something like this: \(I'll keep using the original `orient2d` for the initial setup so we can see the similarity\):

```
    // Bounding box and clipping as before
    // ...

    // Triangle setup
    int A01 = v0.y - v1.y, B01 = v1.x - v0.x;
    int A12 = v1.y - v2.y, B12 = v2.x - v1.x;
    int A20 = v2.y - v0.y, B20 = v0.x - v2.x;

    // Barycentric coordinates at minX/minY corner
    Point2D p = { minX, minY };
    int w0_row = orient2d(v1, v2, p);
    int w1_row = orient2d(v2, v0, p);
    int w2_row = orient2d(v0, v1, p);

    // Rasterize
    for (p.y = minY; p.y <= maxY; p.y++) {
        // Barycentric coordinates at start of row
        int w0 = w0_row;
        int w1 = w1_row;
        int w2 = w2_row;

        for (p.x = minX; p.x <= maxX; p.x++) {
            // If p is on or inside all edges, render pixel.
            if (w0 >= 0 && w1 >= 0 && w2 >= 0)
                renderPixel(p, w0, w1, w2);     

            // One step to the right
            w0 += A12;
            w1 += A20;
            w2 += A01;
        }

        // One row step
        w0_row += B12;
        w1_row += B20;
        w2_row += B01;
    }
```

And just like that, we're down to three additions per pixel. Want proper fill rules? As we saw last time, we can do that using a single bias that we add to the edge functions, and we only have to add it once, at the start. Sub\-pixel precision? Again, a bit more work during triangle setup, but the inner loop stays the same. Different pixel center? Turns out that's just a bias applied once too. Want to sample at several locations within a pixel? That *also* turns into just another add and a sign test.

In fact, after triangle setup, it's really mostly adds and sign tests no matter what we do. That's why this is a popular algorithm for hardware implementation \- you don't even need to do the compare explicitly, you just use a bunch of adders and route the MSB \(most significant bit\) of the sum, which contains the sign bit, to whoever needs to know whether the pixel is in or not.

And on the subject of signs, there's a small trick in software implementations to simplify the sign\-testing part: as I just said, all we really need is the sign bit. If it's clear, we know the value is positive or zero, and if it's set, we know the value is negative. In fact, this is why I made the initial rasterizer test for `>= 0` in the first place \- you really want to use a test that only depends on the sign bit, and not something slightly more complicated like `> 0`. Why do we care? Because it allows us to rewrite the three sign tests like this:

```
    // If p is on or inside all edges, render pixel.
    if ((w0 | w1 | w2) >= 0)
        renderPixel(p, w0, w1, w2);     
```

To understand why this works, you only need to look at the sign bits. Remember, if the sign bit is set in a value, that means it's negative. If, after ORing the three values together, they still register as non\-negative, that means none of them had the sign bit set \- which is exactly what we wanted to test for. Rewriting the expression like this turns three conditional branches into one \- always a good idea to keep the flow control in inner loops simple if you want the optimizer to be happy, and it usually also turns out to be beneficial in terms of branch prediction, although I won't bother to profile it here.

### Processing multiple pixels at once

However, as fun as squeezing individual integer instructions is, the main reason I cited for using this algorithm is that it's embarrassingly parallel, so it's easy to process multiple pixels at the same time using either dedicated silicon \(in hardware\) or SIMD instructions \(in software\). In fact, all we really have to do is keep track of the current value of the edge equations for each pixel, and then update them all per pixel. For concreteness, let's stick with 4\-wide SIMD \(e.g. SSE2\). I'm going to assume that there's a data type `Vec4i` for 4 signed integers in a SIMD registers that overloads the usual arithmetic operations to be element\-wise, because I don't want to use the official Intel intrinsics here \(way too much clutter to see what's going on\).

For starters, let's assume we want to process 4x1 pixels at a time \- that is, in groups 4 pixels wide, but only one pixel high. But before we do anything else, let me just pull all the per\-edge setup into a single function:

```
struct Edge {
    // Dimensions of our pixel group
    static const int stepXSize = 4;
    static const int stepYSize = 1;

    Vec4i oneStepX;
    Vec4i oneStepY;

    Vec4i init(const Point2D& v0, const Point2D& v1,
               const Point2D& origin);
};

Vec4i Edge::init(const Point2D& v0, const Point2D& v1,
                 const Point2D& origin)
{
    // Edge setup
    int A = v0.y - v1.y, B = v1.x - v0.x;
    int C = v0.x*v1.y - v0.y*v1.x;

    // Step deltas
    oneStepX = Vec4i(A * stepXSize);
    oneStepY = Vec4i(B * stepYSize);

    // x/y values for initial pixel block
    Vec4i x = Vec4i(origin.x) + Vec4i(0,1,2,3);
    Vec4i y = Vec4i(origin.y);

    // Edge function values at origin
    return Vec4i(A)*x + Vec4i(B)*y + Vec4i(C);
}
```

As said, this is the setup for one edge, but it already includes all the "magic" necessary to set it up for SIMD traversal. Which is really not much \- we now step in units larger than one pixel, hence the `oneStep` values instead of using `A` and `B` directly. Also, we now return the edge function value at the specified "origin" directly; this is the value we previously computed with `orient2d`. Now that we're processing 4 pixels at a time, we also have 4 different initial values. Note that I write `Vec4i(value)` for a single scalar broadcast into all 4 SIMD lanes, and `Vec4i(a, b, c, d)` for a 4\-int vector that initializes the lanes to different values. I hope this is readable enough.

With this factored out, the SIMD version for the rest of the rasterizer is easy enough:

```
    // Bounding box and clipping again as before

    // Triangle setup
    Point2D p = { minX, minY };
    Edge e01, e12, e20;

    Vec4i w0_row = e12.init(v1, v2, p);
    Vec4i w1_row = e20.init(v2, v0, p);
    Vec4i w2_row = e01.init(v0, v1, p);

    // Rasterize
    for (p.y = minY; p.y <= maxY; p.y += Edge::stepYSize) {
        // Barycentric coordinates at start of row
        Vec4i w0 = w0_row;
        Vec4i w1 = w1_row;
        Vec4i w2 = w2_row;

        for (p.x = minX; p.x <= maxX; p.x += Edge::stepXSize) {
            // If p is on or inside all edges for any pixels,
            // render those pixels.
            Vec4i mask = w0 | w1 | w2;
            if (any(mask >= 0))
                renderPixels(p, w0, w1, w2, mask);

            // One step to the right
            w0 += e12.oneStepX;
            w1 += e20.oneStepX;
            w2 += e01.oneStepX;
        }

        // One row step
        w0_row += e12.oneStepY;
        w1_row += e20.oneStepY;
        w2_row += e01.oneStepY;
    }
```

There's a bunch of surface changes \- our edge function values are now `Vec4i`s instead of ints, and we now process multiple pixels at a time \- but the only thing that *really* changes in any way that matters is the switch from `renderPixel` to `renderPixels`: we now process multiple pixels at a time, and some of them could be in while others are out, so we can't do a single `if` anymore. Instead, we pass our `mask` to `renderPixels` \- which can then use the corresponding sign bit for each pixel to decide whether to update the frame buffer for that pixel. We only early\-out if all of the pixels are outside the triangle.

But really, the most important thing to note is that this wasn't hard at all! \(At least I hope it wasn't. Apologies if I'm going too fast.\)

### Next steps and a bit of perspective

At this point, I could spend an arbitrary amount of time tweaking our toy rasterizer, adding features, optimizing it and so forth, but I'll leave it be; it's served its purpose, which was to illustrate the underlying algorithm. We're gonna switch back to the actual rasterizer from Intel's [Software Occlusion Culling demo](http://software.intel.com/en-us/vcsource/samples/software-occlusion-culling) next. But before we go there, I want to give you some more context about this kind of algorithm, where it's coming from, and how you would modify it for practical applications.

First, as I mentioned before, the nice thing about this type of rasterizer is that it's easy to incorporate external constraints. For example, try modifying the above code so it always does "aligned" accesses, i.e. the x\-coordinate passed to `renderPixels` is always a multiple of 4. This enables the use of aligned loads and stores, which are faster. Similarly, try modifying the rasterizer to traverse groups of 2x2 pixels instead of 4x1 pixels; the code is set up in a way that should make this an easy change. Then combine the two things \- traverse groups of aligned quads, i.e. x and y coordinates passed to `renderPixels` are always even. The point is that all these changes are actually easy to make, whereas they would be relatively hard to incorporate in a scanline rasterizer. It's also easy to make use of wider instruction sets: you could do groups of 4x2 pixels, or 2x4, or even 4x4 and more if you wanted.

That said, the current outer loop we use \- always checking the whole bounding box of the triangle \- is hardly optimal. In fact, for any triangle that's not so large it gets clipped to the screen edges, at least half of the bounding box is going to be empty. There are much better ways to do this traversal, but we're not going to use any of the fancier strategies in this series \(at least, I don't plan to at this moment\) since the majority of triangles we're going to encounter in the demo are actually quite small. The better strategies are much more efficient at rasterizing large triangles, but if a triangle touches less than 10 pixels to begin with, it's just not worth the effort to spend extra time on trying to only cover the areas of the triangle that matter. So there's a fairly delicate balancing act involved. The code on Github does contain a [branch](https://github.com/rygorous/intel_occlusion_cull/tree/hier_rast) that implements a hierarchical rasterizer, and while as of this writing it is somewhat faster, it's not really enough of a win to justify the effort that went into it. But it might still be interesting if you want to see how a \(quickly hacked!\) version of that approach looks.

Which brings me to the history section: As I mentioned in the introduction, this approach is anything but new. The first full description of it in the literature that I'm aware of is Pineda's ["A Parallel Algorithm for Polygon Rasterization"](http://people.csail.mit.edu/ericchan/bib/pdf/p17-pineda.pdf). It was presented at Siggraph 1988 and already describes most of the ideas: It uses integer edge functions, has the incremental evaluation, sub\-pixel precision \(but no proper fill rule\), and it produces blocks of 4x4 pixels at a time. It also shows several smarter traversal algorithms than the basic bounding box strategy we're using. [McCormack and McNamara](http://people.csail.mit.edu/ericchan/bib/pdf/p15-mccormack.pdf) describe more efficient traversal schemes based on tiles, Greene's ["Hierarchical Polygon Tiling with Coverage Masks"](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.115.1646&rep=rep1&type=pdf) describes a hierarchical approach, Michael Abrash's ["Rasterization on Larrabee"](http://www.drdobbs.com/parallel/rasterization-on-larrabee/217200602) describes the same approach as independently discovered while working on [Larrabee](http://en.wikipedia.org/wiki/Larrabee_\(microarchitecture\)) \(I later joined that team, which is a good part of the reason for me being able to quote this list of references by heart\), and [McCool et al.](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.18.5738&rep=rep1&type=pdf) describe a combination of hierarchical rasterization and [Hilbert curve](http://en.wikipedia.org/wiki/Hilbert_curve) scan order that should be sufficient to [nerd snipe](http://xkcd.com/356/) you for at least half an hour if you're still clicking on those links. [Olano and Greer](http://www.cs.unc.edu/~olano/papers/2dh-tri/2dh-tri.pdf) even describe an algorithm that rasterizes straight from homogeneous coordinates without dividing the vertex coordinates through by w first that everyone interested either in rasterization or projective geometry should check out.

Did I mention that this approach isn't exactly new? Anyway, this tangent has gone on for long enough; let's go back to the Software Occlusion Culling demo.

### A match made in Github

I'm not going to start describing any new techniques here, but I do want to use the rest of this article to link up my description of the algorithm with the code in the Software Occlusion Culling demo, so you know what goes where. I purposefully picked our notation and terminology to be similar to the [rasterizer code](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/DepthBufferRasterizerSSEMT.cpp#L219), to minimize friction. I'll write down differences as we encounter them. One thing I'll point out right now is that this code has y pointing down, whereas all my diagrams so far had y=up \(note that I was fairly dodgy in the last 2 posts about which way y actually points \- this is why\). This is a fairly superficial change, but it does mean that the triangles with positive area are now the *clockwise* ones. Keep that in mind. Also, apologies in advance for the messed\-up spacing in the code I'm linking to \- it was written for 4\-column tabs and mixes tabs and spaces, so there's the usual display problems. \(This is why I prefer using spaces in my code, at least in code I intend to put on the net\)

The demo uses a "binning" architecture, which means the screen is chopped up into a number of rectangles \("tiles"\), each [320x90 pixels](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/Constants.h#L29). Triangles first get "binned", which means that for each tile, we build a list of triangles that \(potentially\) overlap it. This is done by the [binner](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/TransformedMeshSSE.cpp#L178).

Once the triangles are binned, this data gets handed off to the actual rasterizer. Each instance of the rasterizer processes exactly one tile. The idea is that tiles are small enough so that their depth buffer \(which is what we're rasterizing, since we want it for occlusion culling\) fits comfortably within the L2 cache of a core. By rendering one tile at a time, we should thus keep number of cache misses for the depth buffer to a minimum. And it works fairly well \- if you look at some of the profiles in earlier articles, you'll notice that the depth buffer rasterizer doesn't have a high number of last\-level cache misses, even though it's one of the main workhorse functions in the program.

Anyway, the rasterizer first tries to [grabs a group of 4 triangles from its active bin](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/DepthBufferRasterizerSSEMT.cpp#L258) \(a "bin" is a container for a list of triangles\). These triangles will be rendered sequentially, but they're all set up as a group using SIMD instructions. The first step is to [compute the A's, B's and C's](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/DepthBufferRasterizerSSEMT.cpp#L304) and determine the bounding box, complete with clipping to the tile bounds and snapping to 2x2\-aligned pixel positions. This is now written using SSE2 intrinsics, but the math should all look very familiar at this point.

It also computes the [triangle area](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/DepthBufferRasterizerSSEMT.cpp#L321) \(actually, twice its area\) which the barycentric coordinates later get divided by to normalize them.

Then, we enter the [per-triangle loop](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/DepthBufferRasterizerSSEMT.cpp#L336). Mostly, variables get broadcast into SIMD registers first, followed by a bit more setup for the increments and of course the initial evaluation of the edge functions \(this looks all scarier than it is, but it is fairly repetitive, which is why I introduced the `Edge` struct in my version of the same code\). Once we enter the [y-loop](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/DepthBufferRasterizerSSEMT.cpp#L403), things should be familiar again: we have our three edge function values at the start of the row \(incremented whenever we go down one step\), and the per\-pixel processing should look familiar too.

After the early\-out, we have the [actual depth-buffer rendering code](https://github.com/rygorous/intel_occlusion_cull/blob/97eae9a8/SoftwareOcclusionCulling/DepthBufferRasterizerSSEMT.cpp#L440) \- the part I always referred to as `renderPixels`. The interpolated depth value is computed from the edge functions using the barycentric coordinates as weights, and then there's a bit of logic to read the current value from the depth buffer and update it given the interpolated depth value. The ifs are there because this loop supports two different depth storage formats: a linear one that is used in "visualize depth buffer" mode and a \(very simply\) swizzled format that's used when "visualize depth buffer" is disabled.

So everything does, in fact, closely follow the basic code flow I showed you earlier. There's a few simple details that I haven't explained yet \(such as the way the depth buffer is stored\), but don't worry, we'll get there \- next time. No more delays \- actual changes to the rasterizer and our first hard\-won performance improvements are upcoming!
