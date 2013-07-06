-time=2013-01-31 0:28
-parent=occlusion_culling
# Cores don't like to share

Two posts ago, I explained write combining and used a real-world example to
show how badly it can go wrong if you're not careful. The last part was an
out-of-turn rant about some string and memory management insanity that was
severely hurting the loading times of that same program. That program was
Intel's [Software Occlusion Culling](http://software.intel.com/en-us/vcsource/samples/software-occlusion-culling)
sample, which I've been playing around with for the last
two weekends.

Well, it turns out that there's even more common performance problems where
those two came from. Now, please don't walk away with the impression that I'm
doing this to pick on either Intel or the authors of that sample. What I'm
really trying to do here is talk about common performance problems you might
find in a typical game code base. Now, I've worked on (and in) several such
projects before, and *every* one of them had its share of skeletons in
the closet. But this time, the problems happen to be in an open-source example
with a permissive license, written by a third party. Which means I can post the
code and my modifications freely, a big plus if I'm going to blog about it -
real code is a lot more interesting than straw man examples. And to be honest,
I'm a lot more comfortable with publicly talking about performance problems in
"abstract code I found on the internet" than I would be doing the same with
code that I know a friend hammered out quickly two days before trying to get a
milestone out.

What I'm trying to say here is, don't let this discourage you from looking at
the actual occlusion culling code that is, after all, the point of the whole
example. And no hard feelings to the guys at Intel who went through the trouble
of writing and releasing it in the first place!

### Our problem of the day

That said, we're still not going to see any actual occlusion culling
performance problems or optimizations today. Because before we get there, it
turns out we have some more low-hanging fruit to pick. As usual, here's a
profile - of the rendering this time.

![Another profiling run](hotspots_frustum.png)

All the functions with SSE in their names relate to the actual depth buffer
rasterizer that's at the core of the demo (as said, we're gonna see it
eventually). `XdxInitXopAdapterServices` is actually the user-mode
graphics driver, the `tbb_graphics_samples` thing is the TBB
scheduler waiting for worker threads to finish (this sample uses Intel's TBB to
dispatch jobs to multiple worker threads), `dxgmms1.sys` is the
video memory manager / GPU scheduler, and `atikmdag.sys` is the
kernel-mode graphics driver. In short, the top 10 list is full of the kinds of
things you would expect in an example that renders lots of small models with
software occlusion culling.

Except for that spot up at #2, that is. This function -
`CPUTFrustum::IsVisible` - simply checks whether an axis-aligned
bounding box intersects the view frustum, and is used for coarse frustum
culling before occlusion is even considered. And it's a *major* time
sink.

Now, instead of the hierarchical callstack profiling I used last time to look
at the loading, this profile was made using hardware event counters, same as in
the write combining article. I've taken the liberty of spoiling the initial
investigation and going straight to the counters that matter: see that blue bar
in the "Machine Clears" column? That bar is telling us that the
`IsVisible` function apparently spends 23.6% of its total running
time performing machine clears! Yikes, but what does that mean?

### Understanding machine clears

What Intel calls a "machine clear" on its current architectures is basically a
panic mode: the CPU core takes all currently pending operations (i.e. anything
that hasn't completed yet), cancels them, and then starts over. It needs to do
this whenever some implicit assumption that those pending instructions were
making turns out to be wrong.

On the Sandy Bridge i7 I'm running this example on, there's event counters for
three kinds of machine clears. Two of them we can safely ignore in this article
- one of them deals with self-modifying code (which we don't have) and one can
occur during execution of AVX masked load operations (which we don't use). The
third, however, bears closer scrutiny: its official name is
`MACHINE_CLEAR.MEMORY_ORDERING`, and it's the event that ends up
consuming 23.6% of all CPU cycles during `IsVisible`.

A memory ordering machine clear gets triggered whenever the CPU core detects a
"memory ordering conflict". Basically, this means that some of the currently
pending instructions tried to access memory that we just found out some other
CPU core wrote to in the meantime. Since these instructions are still flagged
as pending while the "this memory just got written" event means some other core
successfully finished a write, the pending instructions - and everything that
depends on their results - are, retroactively, incorrect: when we started
executing these instructions, we were using a version of the memory contents
that is now out of date. So we need to throw all that work out and do it over.
That's the machine clear.

Now, I'm not going to go into the details of how exactly a core knows when
other cores are writing to memory, or how the cores make sure that whenever
multiple cores try to write to a memory locations, there's always one (and only
one) winner. Nor will I explain how the cores make sure that they learn these
things in time to cancel all operations that might depend on them. All these
are deep and fascinating questions, but the details are unbelievably gnarly
(once you get down to the bottom of how it all works within a core), and
they're well outside the scope of this post. What I will say here is that cores
track memory "ownership" on cache line granularity. So when a memory ordering
conflict happens, that means *something* in a cache line that we just
accessed changed in the mean time. Might be some data we actually looked at,
might be something else - the core doesn't know. Ownership is tracked at the
cache line level, not the byte level.

So the core issues a machine clear whenever something in a cache line we just
looked at changed. It might be due to actual shared data, or it might be two
unrelated data items that just happen to land in the same cache line in memory
- this latter case is normally referred to as "false sharing". And to clear up
something that a lot of people get wrong, let me point out that "false sharing"
is purely a software concept. CPUs really only track ownership on a cache line
level, and a cache line is either shared or it's not, it's never "falsely
shared". So "false sharing" is purely a property of your data's layout in
memory; it's not something the CPU knows (or can do anything) about.

Anyway, I digress. Evidently, we're sharing *something*, intentionally
or not, and that something is causing *a lot* of instructions to get
cancelled and re-executed. The question is: what is it?

### Finding the culprit

And this is where it gets icky. With a lot of things like cache misses or slow
instructions, a profiler can tell us *exactly* which instruction is
causing the problem. Memory ordering problems are much harder to trace, for two
reasons: First, they necessarily involve multiple cores (which tends to make it
much harder to find the corresponding causal chain of events), and second,
because of the cache line granularity, even when they show up as events in one
thread, they do so on an arbitrary instruction that happens to access memory
near the actual shared data. Might be the data that is actually being modified
elsewhere, or it might be something else. There's no easy way to find out.
Looking at these events in a source-level profile is almost completely useless
- in optimized code, a completely unrelated instruction that logically belongs
to another source line might cause a spike. In an assembly-level profile, you
at least get to see the actual instruction that triggers the event, but for the
reasons stated above that's not necessarily very helpful either.

So it boils down to this: a profiler will tell you where to look, and it will
usually point you to some code *near* the code that's actually causing
the problem, and some data *near* the data that is being shared. That's
a good starting point, but from there on it's manual detective work - staring
at the code, staring at the data structures, and trying to figure out what case
is causing the problem. It's annoying work, but you get better at it over time,
and there's some common mistakes - one of which we're going to see in a minute.

But first, some context. `IsVisible` is called in parallel on
multiple threads (via TBB) in a global, initial frustum-cull pass. This is
where we're seeing the slowdown. Evidently, those threads are writing to shared
data somewhere: it must be writes - as long as the memory doesn't change, you
can't get any memory ordering conflicts.

Here's the declaration of the `CPUTFrustum` class (several methods
omitted for brevity):

```cpp
class CPUTFrustum
{
public:
    float3 mpPosition[8];
    float3 mpNormal[6];

    UINT mNumFrustumVisibleModels;
    UINT mNumFrustumCulledModels;

    void InitializeFrustum( CPUTCamera *pCamera );

    bool IsVisible(
        const float3 &center,
        const float3 &half
    );
};
```

And here's the full code for `IsVisible`, with some minor formatting
changes to make it fit inside the layout (excerpting it would spoil the
reveal):

```cpp
bool CPUTFrustum::IsVisible(
    const float3 &center,
    const float3 &half
){
    // TODO:  There are MUCH more efficient ways to do this.
    float3 pBBoxPosition[8];
    pBBoxPosition[0] = center + float3(  half.x,  half.y,  half.z );
    pBBoxPosition[1] = center + float3(  half.x,  half.y, -half.z );
    pBBoxPosition[2] = center + float3(  half.x, -half.y,  half.z );
    pBBoxPosition[3] = center + float3(  half.x, -half.y, -half.z );
    pBBoxPosition[4] = center + float3( -half.x,  half.y,  half.z );
    pBBoxPosition[5] = center + float3( -half.x,  half.y, -half.z );
    pBBoxPosition[6] = center + float3( -half.x, -half.y,  half.z );
    pBBoxPosition[7] = center + float3( -half.x, -half.y, -half.z );

    // Test each bounding box point against each of the six frustum
    // planes.
    // Note: we need a point on the plane to compute the distance
    // to the plane. We only need two of our frustum's points to do
    // this. A corner vertex is on three of the six planes.  We
    // need two of these corners to have a point on all six planes.
    UINT pPointIndex[6] = {0,0,0,6,6,6};
    UINT ii;
    for( ii=0; ii<6; ii++ )
    {
        bool allEightPointsOutsidePlane = true;
        float3 *pNormal = &mpNormal[ii];
        float3 *pPlanePoint = &mpPosition[pPointIndex[ii]];
        float3 planeToPoint;
        float distanceToPlane;
        UINT jj;
        for( jj=0; jj<8; jj++ )
        {
            planeToPoint = pBBoxPosition[jj] - *pPlanePoint;
            distanceToPlane = dot3( *pNormal, planeToPoint );
            if( distanceToPlane < 0.0f )
            {
                allEightPointsOutsidePlane = false;
                break; // from for.  No point testing any
                // more points against this plane.
            }
        }
        if( allEightPointsOutsidePlane )
        {
            mNumFrustumCulledModels++;
            return false;
        }
    }

    // Tested all eight points against all six planes and
    // none of the planes had all eight points outside.
    mNumFrustumVisibleModels++;
    return true;
}
```

Can you see what's going wrong? Try to figure it out yourself. It's a far more
powerful lesson if you discover it yourself. Scroll down if you think you have
the answer (or if you give up).

<div style="height:90em;">&nbsp;</div>

### The reveal

As I mentioned, what it takes for memory ordering conflicts to occur is writes.
The function arguments are const, and `mpPosition` and
`mpNormal` aren't modified either. Local variables are either in
registers or on the stack; either way, they're far enough away between
different threads not to conflict. Which only leaves two variables:
`mNumFrustumCulledModels` and `mNumFrustumVisibleModels`.
And indeed, both of these global (debugging) counters get stored per instance.
All threads happen to use the same instance of `CPUTFrustum`, so the
write locations are shared, and we have our culprit. Now, in a multithreaded
scenario, these counters aren't going to produce the right values anyway,
because the normal C++ increments aren't an atomic operation. As I mentioned
before, these counters are only there for debugging (or at least nothing else
in the code looks at them), so we might as well just remove the two increments
altogether.

So how much does it help to get rid of two meager increments?

![Frustum culling, conflict-free](hotspots_frustum_fixed.png)

Again, the two runs have somewhat different lengths (because I manually
start/stop them after loading is over), so we can't compare the cycle counts
directly, but we can compare the ratios. `CPUTFrustum::IsVisible`
used to take about 60% as much time as our #1 function, and was in the #2 spot.
Now it's at position 5 in the top ten and takes about 32% as much time as our
main workhorse function. In other words, removing these two increments just
about doubled our performance - and that's in a function that does a fair
amount of other work. It can be even more drastic in shorter functions.

Just like we saw with write combining, this kind of mistake is easy to make,
hard to track down and can cause serious performance and scalability issues.
Everyone I know that has seriously used threads has fallen into this trap at
least once - take it as a rite of passage.

Anyway, the function is now running smoothly, not hitting any major stalls and
in fact completely bound by backend execution time - that is, the expensive
part of that function is now the actual computational work. As the TODO comment
mentions, there's better ways to solve this problem. I'm not gonna go into it
here, because as it turns out, I already wrote a post about efficient ways to
solve this problem using SIMD instructions <a
href="http://fgiesen.wordpress.com/2010/10/17/view-frustum-culling/">a bit more
than two years ago</a> - using Cell SPE intrinsics, not SSE intrinsics, but the
idea remains the same.

I won't bother walking through the code here - it's all
[on GitHub](https://github.com/rygorous/intel_occlusion_cull/blob/dev/SoftwareOcclusionCulling/CPUT/CPUT/CPUTFrustum.cpp)
if you want to check it out. But suffice to say that, with the
sharing bottleneck gone, `IsVisible` can be made *much*
faster indeed. In the final profile I took (using the SSE), it shows up at spot
number 19 in the top twenty.

### Two steps forward, one step back

All is not well however, because the method
`AABBoxRasterizerSSEMT::IsInsideViewFrustum`, which you can (barely)
see in some of the earlier profiles, suddenly got a lot slower in relation:

![And the bottleneck has moved](hotspots_isinside_slower.png)

Again, I'm not going to dig into it here now deeply, but it turns out that the
this is the function that calls `IsVisible`. No, it's not what you
might be thinking - `IsVisible` didn't get inlined or anything like
that. In fact, its code looks exactly like it did before. And more to the
point, the problem actually isn't in
`AABBoxRasterizerSSEMT::IsInsideViewFrustum`, it's inside the
function `TransformedAABBoxSSE::IsInsideViewFrustum`, which it
calls, and which does get inlined into
`AABBoxRasterizerSSEMT::IsInsideViewFrustum`:

```cpp
void TransformedAABBoxSSE::IsInsideViewFrustum(CPUTCamera *pCamera)
{
    float3 mBBCenterWS;
    float3 mBBHalfWS;
    mpCPUTModel->GetBoundsWorldSpace(&mBBCenterWS, &mBBHalfWS);
    mInsideViewFrustum = pCamera->mFrustum.IsVisible(mBBCenterWS,
        mBBHalfWS);
}
```

No smoking guns here either - a getter call to retrieve the bounding box center
and half-extents, followed by the call to `IsVisible`. And no, none
of the involved code changed substantially, and there's nothing weird going on
in `GetBoundsWorldSpace`. It's not a virtual call, and it gets
properly inlined. All it does is copy the 6 floats from
`mpCPUTModel` to the stack.

What we do have in this method, however, is lots of L3 cache misses (or
Last-Level Cache misses / LLC misses, as Intel likes to call them) during this
copying. Now, the code doesn't have any more cache misses now than it did
before I added some SSE code to `IsVisible`. But it generates them a
lot faster than it used to. Before, some of the long-taking memory fetches
overlapped with the slower execution of the visibility test for an earlier box.
Now, we're going through instructions fast enough for the code to starve
waiting for the bounding boxes to arrive.

That's how it is dealing with Out-of-Order cores: They're really quite good at
making the best of a bad situation. Which also means that often, fixing a
performance problem just immediately moves the bottleneck somewhere else,
without any substantial speed-up. It often takes several attempts to tackle the
various bottlenecks one by one until, finally, you get to cut the Gordian Knot.
And to get this one faster, we'll have to improve our cache usage. Which is a
topic for another post. Until next time!

