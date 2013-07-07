-time=2013-02-28 3:12
-parent=occlusion_culling
# Reshaping dataflows

Welcome back! So far, we've spent quite some time "zoomed in" on various
components of the Software Occlusion Culling demo, looking at various
micro-architectural pitfalls and individual loops. In the last two posts, we
"zoomed out" and focused on the big picture: what work runs when, and how to
keep all cores busy. Now, it's time to look at what lies in between: the
plumbing, if you will. We'll be looking at the dataflows between subsystems and
modules and how to improve them.

This is one of my favorite topics in optimization, and it's somewhat
under-appreciated. There's plenty of material on how to make loops run fast
(although a lot of it is outdated or just wrong, so beware), and at this point
there's plenty of ways of getting concurrency up and running: there's OpenMP,
Intel's TBB, Apple's GCD, Windows Thread Pools and ConcRT for CPU, there's
OpenCL, CUDA and DirectCompute for jobs that are GPU-suitable, and so forth;
you get the idea. The point being that it's not hard to find a shrink-wrap
solution that gets you up and running, and a bit of profiling (like we just
did) is usually enough to tell you what needs to be done to make it all go
smoothly.

But back to the topic at hand: improving dataflow. The problem is that, unlike
the other two aspects I mentioned, there's really no recipe to follow; it's
very much context-dependent. It basically boils down to looking at both sides
of the interface between systems and functions and figuring out if there's a
better way to handle that interaction. We've seen a bit of that earlier when
talking about frustum culling; rather than trying to define it in words, I'll
just do it by example, so let's dive right in!

### A simple example

A good example is the member variable <code>TransformedAABBoxSSE::mVisible</code>, declared like this:

```cpp
bool *mVisible;
```

A pointer to a bool. So where does that pointer come from?

```cpp
inline void SetVisible(bool *visible){mVisible = visible;}
```

It turns out that the constructor initializes this pointer to
<code>NULL</code>, and the only method that ever does anything with
<code>mVisible</code> is <code>RasterizeAndDepthTestAABBox</code>, which
executes `*mVisible = true;` if the bounding box is found to be
visible. So how does this all get used?

```cpp
mpVisible[i] = false;
mpTransformedAABBox[i].SetVisible(&mpVisible[i]);
if(...)
{
    mpTransformedAABBox[i].TransformAABBox();
    mpTransformedAABBox[i].RasterizeAndDepthTestAABBox(...);
}
```

That's it. That's the only call sites. There's really no reason for
<code>mVisible</code> to be state - semantically, it's just a return value for
<code>RasterizeAndDepthTestAABBox</code>, so that's what it should be -
<em>always</em> try to get rid of superfluous state. This doesn't even have
anything to do with optimization per se; explicit dataflow is easy for
programmers to see and reason about, while implicit dataflow (through pointers,
members and state) is hard to follow (both for humans and compilers!) and
error-prone.

Anyway, making this return value explicit is really basic, so I'm not gonna
walk through the details; you can always look at the <a
href="https://github.com/rygorous/intel_occlusion_cull/commit/36fed2dd3d098e4cace8adec67a415139a0049dd">corresponding
commit</a>. I won't bother benchmarking this change either.

### A more interesting case

In the depth test rasterizer, right after determining the bounding box, there's this piece of code:

```cpp
for(int vv = 0; vv < 3; vv++) 
{
    // If W (holding 1/w in our case) is not between 0 and 1,
    // then vertex is behind near clip plane (1.0 in our case).
    // If W < 1 (for W>0), and 1/W < 0 (for W < 0).
    VecF32 nearClipMask0 = cmple(xformedPos[vv].W, VecF32(0.0f));
    VecF32 nearClipMask1 = cmpge(xformedPos[vv].W, VecF32(1.0f));
    VecS32 nearClipMask = float2bits(or(nearClipMask0, nearClipMask1));

    if(!is_all_zeros(nearClipMask))
    {
        // All four vertices are behind the near plane (we're
        // processing four triangles at a time w/ SSE)
        return true;
    }
}
```

Okay. The transform code sets things up so that the "w" component of the
screen-space positions actually contains 1/w; the first part of this code then
tries to figure out whether the source vertex was in front of the near plane
(i.e. outside the view frustum or not). An ugly wrinkle here is that the near
plane is hard-coded to be at 1. Doing this after dividing by w adds extra
complications since the code needs to be careful about the signs. And the
second comment is outright wrong - it in fact early-outs when <em>any</em> of
the four active triangles have vertex number <code>vv</code> outside the
near-clip plane, not when all of them do. In other words, if any of the 4
active triangles get near-clipped, the test rasterizer will just punt and
return <code>true</code> ("visible").

So here's the thing: there's really no reason to do this check <em>after</em>
we're done with triangle setup. Nor do we even have to gather the 3 triangle
vertices to discover that one of them is in front of the near plane. A box has
8 vertices, and we'll know whether any of them are in front of the near plane
as soon as we're done transforming them, before we even think about triangle
setup! So let's look at the function that transforms the vertices:

```cpp
void TransformedAABBoxSSE::TransformAABBox()
{
    for(UINT i = 0; i < AABB_VERTICES; i++)
    {
        mpXformedPos[i] = TransformCoords(&mpBBVertexList[i], mCumulativeMatrix);
        float oneOverW = 1.0f/max(mpXformedPos[i].m128_f32[3], 0.0000001f);
        mpXformedPos[i] = mpXformedPos[i] * oneOverW;
        mpXformedPos[i].m128_f32[3] = oneOverW;
    }
}
```

As we can see, returning 1/w does in fact take a bit of extra work, so we'd
like to avoid it, especially since that 1/w is really only referenced by the
near-clip checking code. Also, the code seems to clamp w at some arbitrary
small positive value - which means that the part of the near clip computation
in the depth test rasterizer that worries about w&lt;0 is actually unnecessary.
This is the kind of thing I'm talking about - each piece of code in isolation
seems reasonable, but once you look at both sides it becomes clear that the
pieces don't fit together all that well.

It turns out that after <code>TransformCoords</code>, we're in "homogeneous
viewport space", i.e. we're still in a homogeneous space, but unlike the
homogeneous clip space you might be used to from vertex shaders, this one also
has the viewport transform baked in. But our viewport transform leaves z alone
(we fixed that in the previous post!), so we still have a D3D-style clip volume
for z:

$$[ 0 \le z \le w $$]

Since we're using a reversed clip volume, the z&le;w constraint is the
near-plane one. Note that <em>this</em> test doesn't need any special cases for
negative signs and also doesn't have a hardcoded near-plane location any more:
it just automatically uses <a
href="http://fgiesen.wordpress.com/2012/08/31/frustum-planes-from-the-projection-matrix/">whatever
the projection matrix says</a>, which is the right thing to do!

Even better, if we test for near-clip anyway, there's no need to clamp w at
all. We know that anything with w&le;0 is outside the near plane, and if a
vertex is outside the near plane we're not gonna rasterize the box anyway. Now
we might still end up dividing by 0, but since we're dealing with floats, this
is a well-defined operation (it might return infinities or NaNs, but that's
fine).

And on the subject of not rasterizing the box: as I said earlier, as soon as
one vertex is outside the near-plane, we know we're going to return
<code>true</code> from the depth test rasterizer, so there's no point even
starting the operation. To facilitate this, we just make
<code>TransformAABBox</code> return whether the box should be rasterized or
not. Putting it all together:

```cpp
bool TransformedAABBoxSSE::TransformAABBox()
{
    __m128 zAllIn = _mm_castsi128_ps(_mm_set1_epi32(~0));

    for(UINT i = 0; i < AABB_VERTICES; i++)
    {
        __m128 vert = TransformCoords(&mpBBVertexList[i], mCumulativeMatrix);

        // We have inverted z; z is inside of near plane iff z <= w.
        __m128 vertZ = _mm_shuffle_ps(vert, vert, 0xaa); //vert.zzzz
        __m128 vertW = _mm_shuffle_ps(vert, vert, 0xff); //vert.wwww
        __m128 zIn = _mm_cmple_ps(vertZ, vertW);
        zAllIn = _mm_and_ps(zAllIn, zIn);

        // project
        mpXformedPos[i] = _mm_div_ps(vert, vertW);
    }

    // return true if and only if all verts inside near plane
    return _mm_movemask_ps(zAllIn) == 0xf;
}
```

In case you're wondering why this code uses raw SSE intrinsics and not
<code>VecF32</code>, it's because I'm purposefully trying to keep anything
depending on the SIMD width out of <code>VecF32</code>, which makes it a lot
easier to go to 8-wide AVX should we want to at some point. But this code
really uses 4-vectors of (x,y,z,w) and needs to do shuffles, so it doesn't fit
in that model and I want to keep it separate.  But the actual logic is just
what I described.

And once we have this return value from <code>TransformAABBox</code>, we get to
remove the near-clip test from the depth test rasterizer, <em>and</em> we get
to move our early-out for near-clipped boxes all the way to the call site:

```cpp
if(mpTransformedAABBox[i].TransformAABBox())
    mpVisible[i] = mpTransformedAABBox[i].RasterizeAndDepthTestAABBox(...);
else
    mpVisible[i] = true;
```

So, the <code>oneOverW</code> hack, the clamping hack and the hard-coded near
plane are gone. That's already a victory in terms of code quality, but did it
improve the run time?

<b>Change:</b> Transform/early-out fixes
<table>
  <tr>
    <th>Depth test</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Start</td>
    <td>1.109</td><td>1.152</td><td>1.166</td><td>1.182</td><td>1.240</td><td>1.167</td><td>0.022</td>
  </tr>
  <tr>
    <td>Transform fixes</td>
    <td>1.054</td><td>1.092</td><td>1.102</td><td>1.112</td><td>1.146</td><td>1.102</td><td>0.016</td>
  </tr>
</table>

Another 0.06ms off our median depth test time, which may not sound big but is
over 5% of what's left of it at this point.

### Getting warmer

The bounding box rasterizer has one more method that's called per-box though,
and this is one that really deserves some special attention. Meet
<code>IsTooSmall</code>:

```cpp
bool TransformedAABBoxSSE::IsTooSmall(__m128 *pViewMatrix,
    __m128 *pProjMatrix, CPUTCamera *pCamera)
{
    float radius = mBBHalf.lengthSq(); // Use length-squared to
    // avoid sqrt().  Relative comparisons hold.

    float fov = pCamera->GetFov();
    float tanOfHalfFov = tanf(fov * 0.5f);

    MatrixMultiply(mWorldMatrix, pViewMatrix, mCumulativeMatrix);
    MatrixMultiply(mCumulativeMatrix, pProjMatrix, mCumulativeMatrix);
    MatrixMultiply(mCumulativeMatrix, mViewPortMatrix, mCumulativeMatrix);

    __m128 center = _mm_set_ps(1.0f, mBBCenter.z, mBBCenter.y, mBBCenter.x);
    __m128 mBBCenterOSxForm = TransformCoords(&center, mCumulativeMatrix);
    float w = mBBCenterOSxForm.m128_f32[3];
    if( w > 1.0f )
    {
        float radiusDivW = radius / w;
        float r2DivW2DivTanFov = radiusDivW / tanOfHalfFov;

        return r2DivW2DivTanFov < (mOccludeeSizeThreshold * mOccludeeSizeThreshold);
    }

    return false;
}
```

Note that <code>MatrixMultiply(A, B, C)</code> performs <code>C = A * B</code>;
the rest should be easy enough to figure out from the code. Now there's really
several problems with this function, so let's go straight to a list:

* <code>radius</code> (which is really radius squared) only depends on
  <code>mBBHalf</code>, which is fixed at initialization time. There's no need
to recompute it every time.
* Similarly, <code>fov</code> and <code>tanOfHalfFov</code> only depend on the
  camera, and absolutely do not need to be recomputed once for every box. This
is what gave us the <code>_tan_pentium4</code> cameo all the way back in
"[%](*frustum_culling_turning_crank)", by the way.
* The view matrix, projection matrix and viewport matrix are also all camera or
  global constants. Again, no need to multiply these together for every box -
the only matrix that is different between boxes is the very first one, the
world matrix, and since matrix multiplication is associative, we can just
concatenate the other three once.
* There's also no need for <code>mOccludeeSizeThreshold</code> to be squared
  every time - we can do that once.
* Nor is there a need for it to be stored per box, since it's a global constant
  owned by the depth test rasterizer.
* <code>(radius / w) / tanOfHalfFov</code> would be better computed as
  <code>radius / (w * tanOfHalfFov)</code>.
* But more importantly, since all we're doing is a compare and both
  <code>w</code> and <code>tanOfHalfFov</code> are positive, we can just
multiply through by them and get rid of the divide altogether.

All these things are common problems that I must have fixed a hundred times,
but I have to admit that it's pretty rare to see so many of them in a single
page of code. Anyway, rather than fixing these one by one, let's just cut to
the chase: instead of all the redundant computations, we just move everything
that only depends on the camera (or is global) into a single struct that holds
our setup, which I dubbed <code>BoxTestSetup</code>. Here's the code:

```cpp
struct BoxTestSetup
{
    __m128 mViewProjViewport[4];
    float radiusThreshold;

    void Init(const __m128 viewMatrix[4], const __m128 projMatrix[4], CPUTCamera *pCamera,
        float occludeeSizeThreshold);
};

void BoxTestSetup::Init(const __m128 viewMatrix[4],
    const __m128 projMatrix[4], CPUTCamera *pCamera,
    float occludeeSizeThreshold)
{
    // viewportMatrix is a global float4x4; we need a __m128[4]
    __m128 viewPortMatrix[4];
    viewPortMatrix[0] = _mm_loadu_ps((float*)&viewportMatrix.r0);
    viewPortMatrix[1] = _mm_loadu_ps((float*)&viewportMatrix.r1);
    viewPortMatrix[2] = _mm_loadu_ps((float*)&viewportMatrix.r2);
    viewPortMatrix[3] = _mm_loadu_ps((float*)&viewportMatrix.r3);

    MatrixMultiply(viewMatrix, projMatrix, mViewProjViewport);
    MatrixMultiply(mViewProjViewport, viewPortMatrix, mViewProjViewport);

    float fov = pCamera->GetFov();
    float tanOfHalfFov = tanf(fov * 0.5f);
    radiusThreshold = occludeeSizeThreshold * occludeeSizeThreshold * tanOfHalfFov;
}
```

This is initialized once we start culling and simply kept on the stack. Then we
just pass it to <code>IsTooSmall</code>, which after our <a
href="https://github.com/rygorous/intel_occlusion_cull/commit/2411249a28f9918fc574648d5c79af2fe702c1f8">surgery</a>
looks like this:

```cpp
bool TransformedAABBoxSSE::IsTooSmall(const BoxTestSetup &setup)
{
    MatrixMultiply(mWorldMatrix, setup.mViewProjViewport,
        mCumulativeMatrix);

    __m128 center = _mm_set_ps(1.0f, mBBCenter.z, mBBCenter.y, mBBCenter.x);
    __m128 mBBCenterOSxForm = TransformCoords(&center, mCumulativeMatrix);
    float w = mBBCenterOSxForm.m128_f32[3];
    if( w > 1.0f )
    {
        return mRadiusSq < w * setup.radiusThreshold;
    }

    return false;
}
```

Wow, that method sure seems to have lost a few pounds. Let's run the numbers:

<b>Change:</b> IsTooSmall cleanup
<table>
  <tr>
    <th>Depth test</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Start</td>
    <td>1.109</td><td>1.152</td><td>1.166</td><td>1.182</td><td>1.240</td><td>1.167</td><td>0.022</td>
  </tr>
  <tr>
    <td>Transform fixes</td>
    <td>1.054</td><td>1.092</td><td>1.102</td><td>1.112</td><td>1.146</td><td>1.102</td><td>0.016</td>
  </tr>
  <tr>
    <td>IsTooSmall cleanup</td>
    <td>0.860</td><td>0.893</td><td>0.908</td><td>0.917</td><td>0.954</td><td>0.905</td><td>0.018</td>
  </tr>
</table>

Another 0.2ms off the median run time, bringing our total reduction for this post to about 22%. So are we done? Not yet!

### The state police

Currently, each <code>TransformedAABBoxSSE</code> still keeps its own copy of
the cumulative transform matrix and a copy of its transformed vertices. But
it's not necessary for these to be persistent - we compute them once, use them
to rasterize the box, then don't look at them again until the next frame. So,
like <code>mVisible</code> earlier, there's really no need to keep them around
as state; instead, it's better to just store them on the stack. Less pointers
per <code>TransformedAABBoxSSE</code>, less cache misses, and - perhaps most
important of all - it makes the bounding box objects themselves stateless.
Granted, that's the case only because our world is perfectly static and nothing
is animated at runtime, but still, stateless is good! Stateless is easier to
read, easier to debug, and easier to test.

Again, this is another change that is purely mechanical - just pass in a
pointer to <code>cumulativeMatrix</code> and <code>xformedPos</code> to the
functions that want them. So this time, I'm just going to refer you directly to
the <a
href="https://github.com/rygorous/intel_occlusion_cull/commit/0fad7d4fb406eb57a45d59ed2187fbddffe08bc7">two</a>
<a
href="https://github.com/rygorous/intel_occlusion_cull/commit/028a108d36b8bdb0d883d5baf82d1e922dd00fd1">commits</a>
that implement this idea, and skip straight to the results:

<b>Change:</b> Reduce amount of state
<table>
  <tr>
    <th>Depth test</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Start</td>
    <td>1.109</td><td>1.152</td><td>1.166</td><td>1.182</td><td>1.240</td><td>1.167</td><td>0.022</td>
  </tr>
  <tr>
    <td>Transform fixes</td>
    <td>1.054</td><td>1.092</td><td>1.102</td><td>1.112</td><td>1.146</td><td>1.102</td><td>0.016</td>
  </tr>
  <tr>
    <td>IsTooSmall cleanup</td>
    <td>0.860</td><td>0.893</td><td>0.908</td><td>0.917</td><td>0.954</td><td>0.905</td><td>0.018</td>
  </tr>
  <tr>
    <td>Reduce state</td>
    <td>0.834</td><td>0.862</td><td>0.873</td><td>0.886</td><td>0.938</td><td>0.875</td><td>0.017</td>
  </tr>
</table>

Only about 0.03ms this time, but we also save 192 bytes (plus allocator
overhead) worth of memory per box, which is a nice bonus. And anyway, we're not
done yet, because I have one more!

### It's more fun to compute

There's one more piece of unnecessary data we currently store per bounding box:
the vertex list, initialized in <code>CreateAABBVertexIndexList</code>:

```cpp
float3 min = mBBCenter - bbHalf;
float3 max = mBBCenter + bbHalf;
	
//Top 4 vertices in BB
mpBBVertexList[0] = _mm_set_ps(1.0f, max.z, max.y, max.x);
mpBBVertexList[1] = _mm_set_ps(1.0f, max.z, max.y, min.x); 
mpBBVertexList[2] = _mm_set_ps(1.0f, min.z, max.y, min.x);
mpBBVertexList[3] = _mm_set_ps(1.0f, min.z, max.y, max.x);
// Bottom 4 vertices in BB
mpBBVertexList[4] = _mm_set_ps(1.0f, min.z, min.y, max.x);
mpBBVertexList[5] = _mm_set_ps(1.0f, max.z, min.y, max.x);
mpBBVertexList[6] = _mm_set_ps(1.0f, max.z, min.y, min.x);
mpBBVertexList[7] = _mm_set_ps(1.0f, min.z, min.y, min.x);
```

This is, in effect, just treating the bounding box as a general mesh. But
that's extremely wasteful - we already store center and half-extent, the
min/max corner positions are trivial to reconstruct from that information, and
all the other vertices can be constructed by splicing min/max together
componentwise using a set of masks that is the same for all bounding boxes. So
these 8*16 = 128 bytes of vertex data really don't pay their way.

But more importantly, note that the we only ever use two distinct values for x,
y and z each. Now <code>TransformAABBox</code>, which we already saw above,
uses <code>TransformCoords</code> to compute the matrix-vector product
<code>v*M</code> with the cumulative transform matrix, using the expression
<code>v.x * M.row[0] + v.y * M.row[1] + v.z * M.row[2] + M.row[3]</code> (`v.w` is assumed to be 1)
and because we know that <code>v.x</code> is either <code>min.x</code> or
<code>max.x</code>, we can multiply both by <code>M.row[0]</code> once and
store the result. Then the 8 individual vertices can skip the multiplies
altogether. Putting it all together leads to the following new code for
<code>TransformAABBox</code>:

```cpp
// 0 = use min corner, 1 = use max corner
static const int sBBxInd[AABB_VERTICES] = { 1, 0, 0, 1, 1, 1, 0, 0 };
static const int sBByInd[AABB_VERTICES] = { 1, 1, 1, 1, 0, 0, 0, 0 };
static const int sBBzInd[AABB_VERTICES] = { 1, 1, 0, 0, 0, 1, 1, 0 };

bool TransformedAABBoxSSE::TransformAABBox(__m128 xformedPos[],
    const __m128 cumulativeMatrix[4])
{
    // w ends up being garbage, but it doesn't matter - we ignore
    // it anyway.
    __m128 vCenter = _mm_loadu_ps(&mBBCenter.x);
    __m128 vHalf   = _mm_loadu_ps(&mBBHalf.x);

    __m128 vMin    = _mm_sub_ps(vCenter, vHalf);
    __m128 vMax    = _mm_add_ps(vCenter, vHalf);

    // transforms
    __m128 xRow[2], yRow[2], zRow[2];
    xRow[0] = _mm_shuffle_ps(vMin, vMin, 0x00) * cumulativeMatrix[0];
    xRow[1] = _mm_shuffle_ps(vMax, vMax, 0x00) * cumulativeMatrix[0];
    yRow[0] = _mm_shuffle_ps(vMin, vMin, 0x55) * cumulativeMatrix[1];
    yRow[1] = _mm_shuffle_ps(vMax, vMax, 0x55) * cumulativeMatrix[1];
    zRow[0] = _mm_shuffle_ps(vMin, vMin, 0xaa) * cumulativeMatrix[2];
    zRow[1] = _mm_shuffle_ps(vMax, vMax, 0xaa) * cumulativeMatrix[2];

    __m128 zAllIn = _mm_castsi128_ps(_mm_set1_epi32(~0));

    for(UINT i = 0; i < AABB_VERTICES; i++)
    {
        // Transform the vertex
        __m128 vert = cumulativeMatrix[3];
        vert += xRow[sBBxInd[i]];
        vert += yRow[sBByInd[i]];
        vert += zRow[sBBzInd[i]];

        // We have inverted z; z is inside of near plane iff z <= w.
        __m128 vertZ = _mm_shuffle_ps(vert, vert, 0xaa); //vert.zzzz
        __m128 vertW = _mm_shuffle_ps(vert, vert, 0xff); //vert.wwww
        __m128 zIn = _mm_cmple_ps(vertZ, vertW);
        zAllIn = _mm_and_ps(zAllIn, zIn);

        // project
        xformedPos[i] = _mm_div_ps(vert, vertW);
    }

    // return true if and only if none of the verts are z-clipped
    return _mm_movemask_ps(zAllIn) == 0xf;
}
```

Admittedly, quite a bit longer than the original one, but that's because we
front-load a lot of the computation; most of the per-vertex work done in
<code>TransformCoords</code> is gone. And here's our reward:

<b>Change:</b> Get rid of per-box vertex list
<table>
  <tr>
    <th>Depth test</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Start</td>
    <td>1.109</td><td>1.152</td><td>1.166</td><td>1.182</td><td>1.240</td><td>1.167</td><td>0.022</td>
  </tr>
  <tr>
    <td>Transform fixes</td>
    <td>1.054</td><td>1.092</td><td>1.102</td><td>1.112</td><td>1.146</td><td>1.102</td><td>0.016</td>
  </tr>
  <tr>
    <td>IsTooSmall cleanup</td>
    <td>0.860</td><td>0.893</td><td>0.908</td><td>0.917</td><td>0.954</td><td>0.905</td><td>0.018</td>
  </tr>
  <tr>
    <td>Reduce state</td>
    <td>0.834</td><td>0.862</td><td>0.873</td><td>0.886</td><td>0.938</td><td>0.875</td><td>0.017</td>
  </tr>
  <tr>
    <td>Remove vert list</td>
    <td>0.801</td><td>0.823</td><td>0.830</td><td>0.839</td><td>0.867</td><td>0.831</td><td>0.012</td>
  </tr>
</table>

This brings our total for this post to a nearly 25% reduction in median depth
test time, plus about 320 bytes memory reduction per
<code>TransformedAABBoxSSE</code> - which, since we have about 27000 of them,
works out to well over 8 megabytes. Such are the rewards for widening the scope
beyond optimizing functions by themselves.

And as usual, the code for this time (plus some changes I haven't discussed
yet) is up on <a
href="https://github.com/rygorous/intel_occlusion_cull/tree/blog">Github</a>.
Until next time!

