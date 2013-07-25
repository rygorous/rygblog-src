-parent=optimizing-sw-occlusion-culling-index
-title=Triangle rasterization in practice
-time=2013-02-09 07:31:57

Welcome back! The [previous post](*the-barycentric-conspirac) gave us a lot of theoretical groundwork on triangles. This time, let's turn it into a working triangle rasterizer. Again, no profiling or optimization this time, but there will be code, and it should get us set up to talk actual rasterizer optimizations in the next post. But before we start optimizing, let's first try to write the simplest rasterizer that we possibly can, using the primitives we saw in the last part.

### The basic rasterizer

As we saw last time, we can calculate edge functions \(which produce barycentric coordinates\) as a 2x2 determinant. And we also saw last time that we can check if a point is inside, on the edge or outside a triangle simply by looking at the signs of the three edge functions at that point. Our rasterizer is going to work in integer coordinates, so let's assume for now that our triangle vertex positions and point coordinates are given as integers too. The orientation test that computes the 2x2 determinant looks like this in code:

```
struct Point2D {
    int x, y;
};

int orient2d(const Point2D& a, const Point2D& b, const Point2D& c)
{
    return (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x);
}
```

Now, all we have to do to rasterize our triangle is to loop over candidate pixels and check whether they're inside or not. We could do it brute\-force and loop over all screen pixels, but let's try to not be completely brain\-dead about this: we do know that all pixels inside the triangle are also going to be inside an axis\-aligned bounding box around the triangle. And axis\-aligned bounding boxes are both easy to compute and trivial to traverse. This gives:

```
void drawTri(const Point2D& v0, const Point2D& v1, const Point2D& v2)
{
    // Compute triangle bounding box
    int minX = min3(v0.x, v1.x, v2.x);
    int minY = min3(v0.y, v1.y, v2.y);
    int maxX = max3(v0.x, v1.x, v2.x);
    int maxY = max3(v0.y, v1.y, v2.y);

    // Clip against screen bounds
    minX = max(minX, 0);
    minY = max(minY, 0);
    maxX = min(maxX, screenWidth - 1);
    maxY = min(maxY, screenHeight - 1);

    // Rasterize
    Point2D p;
    for (p.y = minY; p.y <= maxY; p.y++) {
        for (p.x = minX; p.x <= maxX; p.x++) {
            // Determine barycentric coordinates
            int w0 = orient2d(v1, v2, p);
            int w1 = orient2d(v2, v0, p);
            int w2 = orient2d(v0, v1, p);

            // If p is on or inside all edges, render pixel.
            if (w0 >= 0 && w1 >= 0 && w2 >= 0)
                renderPixel(p, w0, w1, w2);           
        }
    }
}
```

And that's it. That's a fully functional triangle rasterizer. In theory anyway \- you need to write the `min` / `max` and `renderPixel` functions yourself, and I didn't actually test this code, but you get the idea. It even does 2D clipping. Now, don't get me wrong. I don't recommend that you use this code as\-is anywhere, for reasons I will explain below. But I wanted you to see this, because this is the actual heart of the algorithm. In any implementation of it that you're ever going to see in practice, the wonderful underlying simplicity of it is going to be obscured by the various wrinkles introduced by various features and optimizations. That's fine \- all these additions are worth their price. But they are, in a sense, implementation details. Hell, even limiting the traversal to a bounding box is just an optimization, if a simple and important one. The point I'm trying to make here: This is not, at heart, a hard problem that requires a complex solution. It's a fundamentally simple problem that can be solved much more efficiently if we apply some smarts \- an important distinction.

### Issues with this approach

All that said, let's list some problems with this initial implementation:

* **Integer overflows**. What if some of the computations overflow? This might be an actual problem or it might not, but at the very least we need to look into it.
* **Sub\-pixel precision**. This code doesn't have any.
* **Fill rules**. Graphics APIs specify a set of tie\-breaking rules to make sure that when two non\-overlapping triangles share an edge, every pixel \(or sample\) covered by these two triangles is lit once and only once. GPUs and software rasterizers need to strictly abide by these rules to avoid visual artifacts.
* **Speed**. While the code as given above sure is nice and short, it really isn't particularly efficient. There's a lot we can do make it faster, and we'll get there in a bit, but of course this will make things more complicated.

I'm going to address each of these in turn.

### Integer overflows

Since all the computations happen in `orient2d`, that's the only expression we actually have to look at:

`(b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x)`

Luckily, it's pretty very symmetric, so there's not many different sub\-expressions we have to look at: Say we start with p\-bit signed integer coordinates. That means the individual coordinates are in \[\-2<sup>p\-1</sup>,2<sup>p\-1</sup>\-1\]. By subtracting the upper bound from the lower bound \(and vice versa\), we can determine the bounds for the difference of the two coordinates:

$$-(2^p - 1) \le b_x - a_x \le 2^p - 1 \quad \Leftrightarrow \quad |b_x - a_x| \le 2^p - 1$$

And the same applies for the other three coordinate differences we compute. Next, we compute a product of two such values. Easy enough:

$$|(b_x - a_x) (c_y - a_y)| \le |b_x - a_x| |c_y - a_y| = (2^p - 1)^2$$

Again, the same applies to the other product. Finally, we compute the difference between the two products, which doubles our bound on the absolute value:

$$|\mathrm{Orient2D}(a,b,c)| \le 2 (2^p - 1)^2 = 2^{2p + 1} - 2^{p+2} + 2 \le 2^{2p + 1} - 2$$

since p is always nonnegative. Accounting for the sign bit, that means the result of Orient2D fits inside a \(2p\+2\)\-bit signed integer. Since we want the results to fit inside a 32\-bit integer, that means we need $$p \le (32 - 2) / 2 = 15$$ to make sure there are no overflows. In other words, we're good as long as the input coordinates are all inside \[\-16384,16383\]. Anything poking outside that area needs to be analytically clipped beforehand to make sure there's no overflows during rasterization.

Incidentally, this is shows how a typical implementation [guard band clipping](*a-trip-through-the-graphics-pipeline-2011-part-5) works: the rasterizer performs computations using some set bit width, which determines the range of coordinates that the rasterizer accepts. X/Y\-clipping only needs to be done when a triangle doesn't fall entirely within that region, which is very rare with common viewport sizes. Note that there is no need for rasterizer coordinates to agree with render\-target coordinates, and if you want to maximize the utility of your guard band region, your best bet is to translate the rasterizer coordinate system such that the center \(instead of the top\-left or bottom\-right corner\) of your viewport is near \(0,0\). Otherwise large viewports might have a much bigger guard band on the left side than they do on the right side \(and similar in the vertical direction\), which is undesirable.

Anyway. Integer overflows: Not a big deal, at least in our current setup with all\-integer coordinates. We do need to check for \(and possibly clip\) huge triangles, but they're rare in practice, so we still get away with no clipping most of the time.

### Sub\-pixel precision

For this point and the next, I'm only going to give a high\-level overview, since we're not actually going to use it for our target application.

Snapping vertex coordinates to pixels is actually quite crappy in terms of quality. It's okay for a static view of a static scene, but if either the camera or one of the visible objects moves very slowly, it's quite noticeable that the triangles only move in discrete steps once one of the vertices has moved from one pixel to the next after rounding the coordinates to integer. It looks as if the triangle is "wobbly", especially so if there's a texture on it.

Now, for the application we're concerned with in this series, we're only going to render a depth buffer, and the user is never gonna see it directly. So we can live with artifacts that are merely visually distracting, and needn't bother with sub\-pixel correction. This still means that the triangles we software\-rasterize aren't going to match up exactly with what the hardware rasterizer does, but in practice, if we mistakenly occlusion\-cull an object even though some of its pixel are *just* about visible due to sub\-pixel coordinate differences, it's not a big deal. And neither is not culling an object because of a few pixels that are actually invisible. As one of my CS professors once pointed out, there are reasonable error bounds for *everything*, and for occlusion culling, "a handful of pixels give or take" is a reasonable error bound, at least if they're not clustered together!

But suppose that you want to actually render something user\-visible, in which case you absolutely do need sub\-pixel precision. You want at least 4 extra bits in each coordinate \(i.e. coordinates are specified in 1/16ths of a pixel\), and at this point the standard in DX11\-compliant GPUs in 8 bits of sub\-pixel precision \(coordinates in 1/256ths of a pixel\). Let's assume 8 bits of sub\-pixel precision for now. The trivial way to get this is to multiply everything by 256: our \(still integer\) coordinates are now in 1/256ths of a pixel, but we still only perform one sample each pixel. Easy enough: \(just sketching the updated main loop here\)

```
    static const int subStep = 256;
    static const int subMask = subStep - 1;

    // Round start position up to next integer multiple
    // (we sample at integer pixel positions, so if our
    // min is not an integer coordinate, that pixel won't
    // be hit)
    minX = (minX + subMask) & ~subMask;
    minY = (minY + subMask) & ~subMask;

    for (p.y = minY; p.y <= maxY; p.y += subStep) {
        for (p.x = minX; p.x <= maxX; p.x += subStep) {
            // Determine barycentric coordinates
            int w0 = orient2d(v1, v2, p);
            int w1 = orient2d(v2, v0, p);
            int w2 = orient2d(v0, v1, p);

            // If p is on or inside all edges, render pixel.
            if (w0 >= 0 && w1 >= 0 && w2 >= 0)
                renderPixel(p, w0, w1, w2);           
        }
    }
```

Simple enough, and it works just fine. Well, in theory it does, anyway \- this code fragment is just as untested as the previous one, so be careful :\). By the way, this seems like a good place to note that *if you're writing a software rasterizer, this is likely not what you want*: This code samples triangle coverage at integer coordinates. This is simpler if you're writing a rasterizer without sub\-pixel correction \(as we will do, which is why I set up coordinates this way\), and it also happens to match with D3D9 rasterization conventions, but it disagrees with OpenGL and D3D10\+ rasterization rules, which turn out to be saner in several important ways for a full\-blown renderer. So consider yourselves warned.

Anyway, as said, this works, but it has a problem: doing the computation like this costs us a *lot* of bits. Our accepted coordinate range when working with 32\-bit integers is still \[\-16384,16383\], but now that's in sub\-pixel steps and boils down to approximately \[\-64,63.996\] pixels. That's tiny \- even if we center the viewport perfectly, we can't squeeze more than 128 pixels along each axis out of it this way. One way out is to decrease the level of sub\-pixel precision: at 4 bits, we can just about fit a 2048x2048 pixel render target inside our coordinate space, which isn't exactly comfortable but workable.

But there's a better way. I'm not gonna go into details here because we're already on a tangent and the details, though not hard, are fairly subtle. I might turn it into a separate post at some point. But the key realization is that we're still taking steps of one pixel at a time: all the p's we pass into `orient2d` are an integral number of pixel samples apart. This, together with the incremental evaluation we're gonna see soon, means that we only have to do a full\-precision calculation once per triangle. All the pixel\-stepping code always advances in units of integral pixels, which means the sub\-pixel size enters the computation only once, not squared. Which in turn means we can actually cover the 2048x2048 render target with 8 bits of subpixel accuracy, or 8192x8192 pixels with 4 bits of subpixel resolution. You can squeeze that some more if you traverse the triangle in 2x2 pixel blocks and not actual pixels, as our triangle rasterizer and any OpenGL/D3D\-style rasterizer will do, but again, I digress.

### Fill rules

The goal of fill rules, as briefly explained earlier, is to make sure that when two non\-overlapping triangles share an edge and you render both of them, each pixel gets processed only once. Now, if you look at an [actual description](http://msdn.microsoft.com/en-us/library/windows/desktop/cc627092\(v=vs.85\).aspx#Triangle) \(this one is for D3D10 and up\), it might seem like they're really tricky to implement and require comparing edges to other edges, but luckily it all turns out to be fairly simple to do, although I'll need a bit of space to explain it.

Remember that our core rasterizer only deals with triangles in one winding order \- let's say counter\-clockwise, as we've been using last time. Now let's look at the rules from the article I just pointed you to:

> A top edge, is an edge that is exactly horizontal and is above the other edges.
> <br>A left edge, is an edge that is not exactly horizontal and is on the left side of the triangle.

![{floatleft}A triangle.](wpmedia/tri1.png)

The "exactly horizontal" part is easy enough to find out \(just check if the y\-coordinates are different\), but the second half of these definitions looks troublesome. Luckily, it turns out to be fairly easy. Let's do top first: What does "above the other edges" mean, really? An edge connects two points. The edge that's "above the other edges" connects the two highest vertices; the third vertex is below them. In our example triangle, that edge is v<sub>1</sub>v<sub>2</sub> \(ignore that it's not horizontal for now, it's still the edge that's above the others\).  Now I claim that edge *must* be one that is going towards the left. Suppose it was going to the right instead \- then v<sub>0</sub> would be in its right \(negative\) half\-space, meaning the triangle is wound clockwise, contradicting our initial assertion that it's counter\-clockwise! And by the same argument, any horizontal edge that goes to the right must be a bottom edge, or again we'd have a clockwise triangle. Which gives us our first updated rule:

*In a counter\-clockwise triangle, a top edge is an edge that is exactly horizontal and goes towards the left, i.e. its end point is left of its start point.*

That's really easy to figure out \- just a sign test on the edge vectors. And again using the same kind of argument as before \(consider the edge v<sub>2</sub>v<sub>0</sub>\), we can see that any "left" edge must be one that's going down, and that any edge that is going up is in fact a right edge. Which gives us the second updated rule:

*In a counter\-clockwise triangle, a left edge is an edge that goes down, i.e. its end point is strictly below its start point.*

Note we can drop the "not horizontal" part entirely: any edge that goes down by our definition can't be horizontal to begin with. So this is just one sign test, even easier than testing for a top edge!

And now that we know how to identify which edge is which, what do we do with that information? Again, quoting from the D3D10 rules:

> Any pixel center which falls inside a triangle is drawn; a pixel is assumed to be inside if it passes the top\-left rule. The top\-left rule is that a pixel center is defined to lie inside of a triangle if it lies on the top edge or the left edge of a triangle.

To paraphrase: if our sample point actually falls inside the triangle \(not on an edge\), we draw it no matter what. It if happens to fall on an edge, we draw it if and only if that edge happens to be a top or a left edge.

Now, our current rasterizer code:

```
    int w0 = orient2d(v1, v2, p);
    int w1 = orient2d(v2, v0, p);
    int w2 = orient2d(v0, v1, p);

    // If p is on or inside all edges, render pixel.
    if (w0 >= 0 && w1 >= 0 && w2 >= 0)
        renderPixel(p, w0, w1, w2);           
```

Draws *all* points that fall on edges, no matter which kind \- all the tests are for greater\-or\-equals to zero. That's okay for edge functions corresponding to top or left edges, but for the other edges we really want to be testing for a proper "greater than zero" instead. We could have multiple versions of the rasterizer, one for each possible combination of "edge 0/1/2 is \(not\) top\-left", but that's too horrible to contemplate. Instead, we're going to use the fact that for integers, `x > 0` and `x >= 1` mean the same thing. Which means we can leave the tests as they are by first computing a per\-edge offset once:

```
  int bias0 = isTopLeft(v1, v2) ? 0 : -1;
  int bias1 = isTopLeft(v2, v0) ? 0 : -1;
  int bias2 = isTopLeft(v0, v1) ? 0 : -1;
```

and then changing our edge function computation slightly:

```
    int w0 = orient2d(v1, v2, p) + bias0;
    int w1 = orient2d(v2, v0, p) + bias1;
    int w2 = orient2d(v0, v1, p) + bias2;

    // If p is on or inside all edges, render pixel.
    if (w0 >= 0 && w1 >= 0 && w2 >= 0)
        renderPixel(p, w0, w1, w2);           
```

Full disclosure: this changes the barycentric coordinates we pass to `renderPixel` slightly \(as does the subpixel\-precision squeezing we did earlier!\). If you're not using sub\-pixel correction, this can be quite a big error, and you want to correct for it. With sub\-pixel correction, you might decide that being off\-by\-1 on interpolated quantities is no big deal \(remember that the edge functions are in area units, so "1" is a 1\-subpixel\-by\-1\-subpixel square, which is fairly small\). Either way, the bias values are computed once per triangle, and you can usually do the correction once per triangle too, so it's no extra per\-pixel overhead. Right now, we pay some per\-pixel cost to apply the biases too, but it turns out that will go away once we start optimizing it. And by the way, if you go back to the "integer overflow" section, you'll notice we had a bit of slack on the precision requirements; the "bias" terms will not cause us to need any extra bits. So it really does all work out, and we can get proper fill rule handling in our rasterizer.

Which reminds me: This is the part where I tell you that the depth buffer rasterizer we're going to look at doesn't bother with implementing a consistent fill rule. It has the same "fill everything inside or on the edge" behavior as our initial code does. That might be an oversight, or it might be an intentional decision to make the rasterizer slightly conservative, which would make sense given the application. I'm not sure, and I decided not to mess with it. But I figured that since I was writing a post on rasterization, it would be a sin *not* to describe how to do this properly, especially since a coherent explanation of how exactly it's done is quite hard to find on the net.

### All that's fine and good, but now how do we make it fast?

Well, that's a big question, and \- much as I hate to tell you \- one that I will try to answer in the next post. We'll also end this brief detour into software rasterization generalities and get back to the Software Occlusion Culling demo that started this series.

So what's the point of this and the previous post? Well, first off, this is still my blog, and I just felt like writing about it. :\) And just as importantly, I'm going to spend at least two posts poking around in the guts of a rasterizer, and none of the changes I'm going to describe will make *any* sense to you without this background information. Low\-hanging fruit are all nice and good, but sometimes you actually have to work for it, and this is one of those times. Besides, while optimizing code is fun, correctness isn't optional. Fast code that doesn't do what it's supposed to is no good to anyone. So I'm trying to get it right before we make it fast. I can promise you it will be worth your while, though, and I'll try to finish and upload the next post quickly. Until then, take care!
