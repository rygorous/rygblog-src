-time=2013-03-04 3:16
-parent=occlusion_culling
# Speculatively speaking

Welcome back! Today, it's time to take a closer look at the triangle binning
code, which we've only seen mentioned briefly so far, and we're going to see a
few more pitfalls that all relate to <a
href="http://en.wikipedia.org/wiki/Speculative_execution">speculative
execution</a>.

### Loads blocked by what?

There's one more micro-architectural issue this program runs into that I
haven't talked about before. Here's the obligatory profiler screenshot:

![Store-to-load forwarding issues](hotspots_stlf.png)

The full column name reads "Loads Blocked by Store Forwarding". So, what's
going on there? For this one, I'm gonna have to explain a bit first.

So let's talk about stores in an out-of-order processor. In this series, we
already saw how conditional branches and memory sharing between cores get
handled on modern x86 cores: namely, with <em>speculative execution</em>. For
branches, the core tries to predict which direction they will go, and
automatically starts fetching and executing the corresponding instructions.
Similarly, memory accesses are assumed to not conflict with what other cores
are doing at the same time, and just march on ahead. But if it later turns out
that the branch actually went in the other direction, that there was a memory
conflict, or that some exception / hardware interrupt occurred, all the
instructions that were executed in the meantime are invalid and their results
must be discarded --- the speculation didn't pan out. The implicit assumption is
that our speculation (branches behave as predicted, memory accesses generally
don't conflict and CPU exceptions/interrupts are rare) is right most of the
time, so it generally pays off to forge ahead, and the savings are worth the
occasional extra work of undoing a bunch of instructions when we turned out to
be wrong.

But wait, how does the CPU "undo" instructions? Well, conceptually it takes a
"snapshot" of the current machine state every time it's about to start an
operation that it might later have to undo. If that instructions makes it all
the way through the pipeline without incident, it just gets retired normally,
the snapshot gets thrown away and we know that our speculation was successful.
But if there is a problem somewhere, the machine can just throw away all the
work it did in the meantime, rewind back to the snapshot and retry.

Of course, CPUs don't actually take full snapshots. Instead, they make use of
the out-of-order machinery to do things much more efficiently: out-of-order
CPUs have more registers internally than are exposed in the ISA (Instruction
Set Architecture), and use a technique called "register renaming" to map the
small set of architectural registers onto the larger set of physical registers.
The "snapshotting" then doesn't actually need to save register contents; it
just needs to keep track of what the current register mapping at the snapshot
point was, and make sure that the associated physical registers from the
"before" snapshot don't get reused until the instruction is safely retired.

This takes care of register modifications. We already know what happens with
loads from memory --- we just run them, and if it later turns out that the memory
contents changed between the load instruction's execution and its retirement,
we need to re-run that block of code. Stores are the tricky part: we can't
easily do "memory renaming" since memory (unlike registers) is a shared
resource, and also unlike registers rarely gets written in whole "accounting
units" (cache lines) at a time.

The solution are <em>store buffers</em>: when a store instruction is executed,
we do all the necessary groundwork --- address translation, access right checking
and so forth --- but don't actually write to memory just yet; rather, the target
address and the associated data bits are written into a store buffer, where
they just sit around for a while; the store buffers form a log of all pending
writes to memory. Only after the core is sure that the store instruction will
actually be executed (branch results etc. are known and no exceptions were
triggered) will these values <em>actually</em> be written back to the cache.

Buffering stores this way has numerous advantages (beyond just making
speculation easier), and is a technique not just used in out-of-order
architectures; there's just one problem though: what happens if I run code like
this?

```
  mov  [x], eax
  mov  ebx, [x]
```

Assuming no other threads writing to the same memory at the same time, you
would certainly hope that at the end of this instruction sequence,
<code>eax</code> and <code>ebx</code> contain the same value. But remember that
the first instruction (the store) just writes to a store buffer, whereas the
second instruction (the load) normally just references the cache. At the very
least, we have to detect that this is happening --- i.e., that we are trying to
load from an address that currently has a write logged in a store buffer --- but
there's numerous things we could do with that information.

One option is to simply stall the core and wait until the store is done before
the load can start. This is fairly cheap to implement in hardware, but it does
slow down the software running on it. This option was chosen by the in-order
cores used in the current generation of game consoles, and the result is the
dreaded "Load Hit Store" stall. It's a way to solve the problem, but let's just
say it won't win you many friends.

So x86 cores normally use a technique called "store to load forwarding" or just
"store forwarding", where loads can actually read data directly from the store
buffers, at least under certain conditions. This is much more expensive in
hardware --- it adds a <em>lot</em> of wires between the load unit and the store
buffers --- but it is far less finicky to use on the software side.

So what are the conditions? The details depend on the core in question.
Generally, if you store a value to a naturally aligned location in memory, and
do a load with the same size as the store, you can expect store forwarding to
work. If you do trickier stuff --- span multiple cache lines, or use mismatched
sizes between the loads and stores, for example --- it really does depend. Some
of the more recent Intel cores can also forward larger stores into smaller
loads (e.g. a DWord read from a location written with <code>MOVDQA</code>)
under certain circumstances, for example. The dual case (large load overlapping
with smaller stores) is substantially harder though, because it can involved
multiple store buffers at the same time, and I currently know of no processor
that implements this. And whenever you hit a case where the processor can't
perform store forwarding, you get the "Loads Blocked by Store Forwarding" stall
above (effectively, x86's version of a Load-Hit-Store).

### Revenge of the cycle-eaters

Which brings us back to the example at hand: what's going on in those
functions, <code>BinTransformedTrianglesMT</code> in particular? Some
investigation of the compiled code shows that the first sign of blocked loads
is near these reads:

```cpp
Gather(xformedPos, index, numLanes);
		
vFxPt4 xFormedFxPtPos[3];
for(int i = 0; i < 3; i++)
{
    xFormedFxPtPos[i].X = ftoi_round(xformedPos[i].X);
    xFormedFxPtPos[i].Y = ftoi_round(xformedPos[i].Y);
    xFormedFxPtPos[i].Z = ftoi_round(xformedPos[i].Z);
    xFormedFxPtPos[i].W = ftoi_round(xformedPos[i].W);
}
```

and looking at the code for <code>Gather</code> shows us exactly what's going on:

```cpp
void TransformedMeshSSE::Gather(vFloat4 pOut[3], UINT triId, UINT numLanes)
{
    for(UINT l = 0; l < numLanes; l++)
    {
        for(UINT i = 0; i < 3; i++)
        {
            UINT index = mpIndices[(triId * 3) + (l * 3) + i];
            pOut[i].X.lane[l] = mpXformedPos[index].m128_f32[0];
            pOut[i].Y.lane[l] = mpXformedPos[index].m128_f32[1];
            pOut[i].Z.lane[l] = mpXformedPos[index].m128_f32[2];
            pOut[i].W.lane[l] = mpXformedPos[index].m128_f32[3];
        }
    }
}
```

Aha! This is the code that transforms our vertices from the AoS (array of
structures) form that's used in memory into the SoA (structure of arrays) form
we use during binning (and also the two rasterizers). Note that the output
vectors are written element by element; then, as soon as we try to read the
whole vector into a register, we hit a forwarding stall, because the core can't
forward the results from the 4 different stores per vector to a single load. It
turns out that the other two instances of forwarding stalls run into this
problem for the same reason --- during the gather of bounding box vertices and
triangle vertices in the rasterizer, respectively.

So how do we fix it? Well, we'd really like those vectors to be written using
full-width SIMD stores instead. Luckily, that's not too hard: converting data
from AoS to SoA is essentially a matrix transpose, and our typical use case
happens to be 4 separate 4-vectors, i.e. a 4x4 matrix; luckily, a 4x4 matrix
transpose is fairly easy to do in SSE, and Intel's intrinsics header file even
comes with a macro that implements it. So here's the updated
<code>Gather</code> that uses a SSE transpose:

```cpp
void TransformedMeshSSE::Gather(vFloat4 pOut[3], UINT triId, UINT numLanes)
{
    const UINT *pInd0 = &mpIndices[triId * 3];
    const UINT *pInd1 = pInd0 + (numLanes > 1 ? 3 : 0);
    const UINT *pInd2 = pInd0 + (numLanes > 2 ? 6 : 0);
    const UINT *pInd3 = pInd0 + (numLanes > 3 ? 9 : 0);

    for(UINT i = 0; i < 3; i++)
    {
        __m128 v0 = mpXformedPos[pInd0[i]]; // x0 y0 z0 w0
        __m128 v1 = mpXformedPos[pInd1[i]]; // x1 y1 z1 w1
        __m128 v2 = mpXformedPos[pInd2[i]]; // x2 y2 z2 w2
        __m128 v3 = mpXformedPos[pInd3[i]]; // x3 y3 z3 w3
        _MM_TRANSPOSE4_PS(v0, v1, v2, v3);
        // After transpose:
        pOut[i].X = VecF32(v0); // v0 = x0 x1 x2 x3
        pOut[i].Y = VecF32(v1); // v1 = y0 y1 y2 y3
        pOut[i].Z = VecF32(v2); // v2 = z0 z1 z2 z3
        pOut[i].W = VecF32(v3); // v3 = w0 w1 w2 w3
    }
}
```

Not much to talk about here. The other two instances of this get modified in
the exact same way. So how much does it help?

<b>Change:</b> Gather using SSE instructions and transpose
<table>
  <tr>
    <th>Total cull time</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Initial</td>
    <td>3.148</td><td>3.208</td><td>3.243</td><td>3.305</td><td>4.321</td><td>3.271</td><td>0.100</td>
  </tr>
  <tr>
    <td>SSE Gather</td>
    <td>2.934</td><td>3.078</td><td>3.110</td><td>3.156</td><td>3.992</td><td>3.133</td><td>0.103</td>
  </tr>
</table>

<table>
  <tr>
    <th>Render depth</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Initial</td>
    <td>2.206</td><td>2.220</td><td>2.228</td><td>2.242</td><td>2.364</td><td>2.234</td><td>0.022</td>
  </tr>
  <tr>
    <td>SSE Gather</td>
    <td>2.099</td><td>2.119</td><td>2.137</td><td>2.156</td><td>2.242</td><td>2.141</td><td>0.028</td>
  </tr>
</table>

<table>
  <tr>
    <th>Depth test</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Initial</td>
    <td>0.813</td><td>0.830</td><td>0.839</td><td>0.847</td><td>0.886</td><td>0.839</td><td>0.013</td>
  </tr>
  <tr>
    <td>SSE Gather</td>
    <td>0.773</td><td>0.793</td><td>0.802</td><td>0.809</td><td>0.843</td><td>0.801</td><td>0.012</td>
  </tr>
</table>

So we're another 0.13ms down, about 0.04ms of which we gain in the depth
testing pass and the remaining 0.09ms in the rendering pass. And a re-run with
VTune confirms that the blocked loads are indeed gone:

![Store forwarding fixed](hotspots_stlf_fixed.png)

### Vertex transformation

[Last time](*reshaping_dataflows), we modified the vertex transform code in the
depth test rasterizer to get rid of the z-clamping and simplify the clipping
logic. We also changed the logic to make better use of the regular structure of
our input vertices. We don't have any special structure we can use to make
vertex transforms on regular meshes faster, but we definitely can (and should)
improve the projection and near-clip logic, turning this:

```cpp
mpXformedPos[i] = TransformCoords(&mpVertices[i].position, cumulativeMatrix);
float oneOverW = 1.0f/max(mpXformedPos[i].m128_f32[3], 0.0000001f);
mpXformedPos[i] = _mm_mul_ps(mpXformedPos[i], _mm_set1_ps(oneOverW));
mpXformedPos[i].m128_f32[3] = oneOverW;
```

into this:

```cpp
__m128 xform = TransformCoords(&mpVertices[i].position, cumulativeMatrix);
__m128 vertZ = _mm_shuffle_ps(xform, xform, 0xaa);
__m128 vertW = _mm_shuffle_ps(xform, xform, 0xff);
__m128 projected = _mm_div_ps(xform, vertW);

// set to all-0 if near-clipped
__m128 mNoNearClip = _mm_cmple_ps(vertZ, vertW);
mpXformedPos[i] = _mm_and_ps(projected, mNoNearClip);
```

Here, near-clipped vertices are set to the (invalid) x=y=z=w=0, and the binner
code can just check for <code>w==0</code> to test whether a vertex is
near-clipped instead of having to use the original w tests (which again had a
hardcoded near plane value).

This change doesn't have any significant impact on the running time, but it
does get rid of the hardcoded near plane location for good, so I thought it was
worth mentioning.

### Again with the memory ordering

And if we profile again, we notice there's at least one more surprise waiting
for us in the binning code:

![Binning Machine Clears](hotspots_binning_mc.png)

Machine clears? We've seen them before, way back in "[%](*cores_dont_share)".
And yes, they're again for memory ordering reasons.  What did we do wrong this
time? It turns out that the problematic code has been in there since the
beginning, and ran just fine for quite a while, but ever since the scheduling
optimizations we did in "[%](*care_and_feeding_worker_threads_1)", we now have
binning jobs running tightly packed enough to run into memory ordering issues.
So what's the problem? Here's the code:

```cpp
// Add triangle to the tiles or bins that the bounding box covers
int row, col;
for(row = startY; row <= endY; row++)
{
    int offset1 = YOFFSET1_MT * row;
    int offset2 = YOFFSET2_MT * row;
    for(col = startX; col <= endX; col++)
    {
        int idx1 = offset1 + (XOFFSET1_MT * col) + taskId;
        int idx2 = offset2 + (XOFFSET2_MT * col) +
            (taskId * MAX_TRIS_IN_BIN_MT) + pNumTrisInBin[idx1];
        pBin[idx2] = index + i;
        pBinModel[idx2] = modelId;
        pBinMesh[idx2] = meshId;
        pNumTrisInBin[idx1] += 1;
    }
}
```

The problem turns out to be the array <code>pNumTrisInBin</code>. Even though
it's accessed as 1D, it is effectively a 3D array like this:

<code>uint16 pNumTrisInBin[TILE_ROWS][TILE_COLS][BINNER_TASKS]</code>

The <code>TILE_ROWS</code> and <code>TILE_COLS</code> parts should be obvious.
The <code>BINNER_TASKS</code> needs some explanation though: as you hopefully
remember, we try to divide the work between binning tasks so that each of them
gets roughly the same amount of triangles. Now, before we start binning
triangles, we don't know which tiles they will go into --- after all, that's what
the binner is there to find out.

We could have just one output buffer (bin) per tile; but then, whenever two
binner tasks simultaneously end up trying to add a triangle to the same tile,
they will end up getting serialized because they try to increment the same
counter. And even worse, it would mean that the actual order of triangles in
the bins would be different between every run, depending on when exactly each
thread was running; while not fatal for depth buffers (we just end up storing
the max of all triangles rendered to a pixel anyway, which is
ordering-invariant) it's still a complete pain to debug.

Hence there is one bin per tile per binning worker. We already know that the
binning workers get assigned the triangles in the order they occur in the
models --- with the 32 binning workers we use, the first binning task gets the
first 1/32 of the triangles, and second binning task gets the second 1/32, and
so forth. And each binner processes triangles in order. This means that the
rasterizer tasks can still process triangles in the original order they occur
in the mesh --- first process all triangles inserted by binner 0, then all
triangles inserted by binner 1, and so forth. Since they're in distinct memory
ranges, that's easily done. And each bin has a separate triangle counter, so
they don't interfere, right? Nothing to see here, move along.

Well, except for the bit where coherency is managed on a cache line
granularity. Now, as you can see from the above declaration, the triangle
counts for all the binner tasks are stored in adjacent 16-bit words; 32 of
them, to be precise, one per binner task. So what was the size of a cache line
again? 64 bytes, you say?

Oops.

Yep, even though it's 32 separate counters, for the purposes of the memory
subsystem it's just the same as if it was all a single counter per tile (well,
it might be slightly better than that if the initial pointer isn't 64-byte
aligned, but you get the idea).

Luckily for us, the fix is dead easy: all we have to do is shuffle the order of
the array indices around.

<code>uint16 pNumTrisInBin[BINNER_TASKS][TILE_ROWS][TILE_COLS]</code>

We also happen to have 32 tiles total --- which means that now, each binner task
gets its own cache line by itself (again, provided we align things correctly).
So again, it's a really easy fix. The question being --- how much does it help?

<b>Change:</b> Change pNumTrisInBin array indexing
<table>
  <tr>
    <th>Total cull time</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Initial</td>
    <td>3.148</td><td>3.208</td><td>3.243</td><td>3.305</td><td>4.321</td><td>3.271</td><td>0.100</td>
  </tr>
  <tr>
    <td>SSE Gather</td>
    <td>2.934</td><td>3.078</td><td>3.110</td><td>3.156</td><td>3.992</td><td>3.133</td><td>0.103</td>
  </tr>
  <tr>
    <td>Change bin inds</td>
    <td>2.842</td><td>2.933</td><td>2.980</td><td>3.042</td><td>3.914</td><td>3.007</td><td>0.125</td>
  </tr>
</table>

<table>
  <tr>
    <th>Render depth</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Initial</td>
    <td>2.206</td><td>2.220</td><td>2.228</td><td>2.242</td><td>2.364</td><td>2.234</td><td>0.022</td>
  </tr>
  <tr>
    <td>SSE Gather</td>
    <td>2.099</td><td>2.119</td><td>2.137</td><td>2.156</td><td>2.242</td><td>2.141</td><td>0.028</td>
  </tr>
  <tr>
    <td>Change bin inds</td>
    <td>1.980</td><td>2.008</td><td>2.026</td><td>2.046</td><td>2.172</td><td>2.032</td><td>0.035</td>
  </tr>
</table>

That's right, a 0.1ms difference from <em>changing the memory layout of a
1024-entry, 2048-byte array</em>. You really need to be extremely careful with
the layout of shared data when dealing with multiple cores at the same time.

### Once more, with branching

At this point, the binner is starting to look fairly good, but there's one more
thing that springs to eye:

![Binning branch mispredicts](hotspots_binning_mispred.png)

Branch mispredictions. Now, the two rasterizers have legitimate reason to be
mispredicting branches some of the time --- they're processing triangles with
fairly unpredictable sizes, and the depth test rasterizer also has an early-out
that's hard to predict. But the binner has less of an excuse --- sure, the
triangles have very different dimensions measured <em>in 2x2 pixel blocks</em>,
but the vast majority of our triangles fits inside one of our (generously
sized!) 320x90 pixel tiles. So where are all these branches?

```cpp
for(int i = 0; i < numLanes; i++)
{
    // Skip triangle if area is zero 
    if(triArea.lane[i] <= 0) continue;
    if(vEndX.lane[i] < vStartX.lane[i] || vEndY.lane[i] < vStartY.lane[i])
        continue;
			
    float oneOverW[3];
    for(int j = 0; j < 3; j++)
        oneOverW[j] = xformedPos[j].W.lane[i];
			
    // Reject the triangle if any of its verts are outside the near clip plane
    if(oneOverW[0] == 0.0f || oneOverW[1] == 0.0f || oneOverW[2] == 0.0f)
        continue;

    // ...
}
```

Oh yeah, that. In particular, the first test (which checks for degenerate and
back-facing triangles) will reject roughly half of all triangles and can be
fairly random (as far as the CPU is concerned). Now, [last time we had an issue
with branch mispredicts](*depth_buffers_done_quick_1), we simply removed the
offending early-out. That's a really bad idea in this case --- any triangles we
don't reject here, we're gonna waste even more work on later. No, these tests
really should all be done here.

However, there's no need for them to be done like this; right now, we have a
whole slew of branches that are all over the map. Can't we consolidate the
branches somehow?

Of course we can. The basic idea is to do all the tests on 4 triangles at a
time, while we're still in SIMD form:

```cpp
// Figure out which lanes are active
VecS32 mFront = cmpgt(triArea, VecS32::zero());
VecS32 mNonemptyX = cmpgt(vEndX, vStartX);
VecS32 mNonemptyY = cmpgt(vEndY, vStartY);
VecF32 mAccept1 = bits2float(mFront & mNonemptyX & mNonemptyY);

// All verts must be inside the near clip volume
VecF32 mW0 = cmpgt(xformedPos[0].W, VecF32::zero());
VecF32 mW1 = cmpgt(xformedPos[1].W, VecF32::zero());
VecF32 mW2 = cmpgt(xformedPos[2].W, VecF32::zero());

VecF32 mAccept = and(and(mAccept1, mW0), and(mW1, mW2));
// laneMask == (1 << numLanes) - 1; - initialized earlier
unsigned int triMask = _mm_movemask_ps(mAccept.simd) & laneMask;
```

Note I change the "is not near-clipped test" from <code>!(w == 0.0f)</code> to
<code>w &gt; 0.0f</code>, on account of me knowing that all legal w's happen to
not just be non-zero, they're positive (okay, what really happened is that I
forgot to add a "cmpne" when I wrote <code>VecF32</code> and didn't feel like
adding it here). Other than that, it's fairly straightforward. We build a mask
in vector registers, then turn it into an integer mask of active lanes using
<code>MOVMSKPS</code>.

With this, we could turn all the original branches into a single test in the
<code>i</code> loop:

```cpp
if((triMask & (1 << i)) == 0)
    continue;
```

However, we can do slightly better than that: it turns out we can iterate
pretty much directly over the set bits in <code>triMask</code>, which means
we're now down to one single branch in the outer loop --- the loop counter
itself. The modified loop looks like this:

```cpp
while(triMask)
{
    int i = FindClearLSB(&triMask);
    // ...
}
```

So what does the magic <code>FindClearLSB</code> function do? It better not
contain any branches! But lucky for us, it's quite straightforward:

```cpp
// Find index of least-significant set bit in mask
// and clear it (mask must be nonzero)
static int FindClearLSB(unsigned int *mask)
{
    unsigned long idx;
    _BitScanForward(&idx, *mask);
    *mask &= *mask - 1;
    return idx;
}
```

all it takes is <code>_BitScanForward</code> (the VC++ intrinsic for the x86
<code>BSF</code> instruction) and a really old trick for clearing the
least-significant set bit in a value. In other words, this compiles into about
3 integer instructions and is completely branch-free. Good enough. So does it
help?

<b>Change:</b> Less branches in binner
<table>
  <tr>
    <th>Total cull time</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Initial</td>
    <td>3.148</td><td>3.208</td><td>3.243</td><td>3.305</td><td>4.321</td><td>3.271</td><td>0.100</td>
  </tr>
  <tr>
    <td>SSE Gather</td>
    <td>2.934</td><td>3.078</td><td>3.110</td><td>3.156</td><td>3.992</td><td>3.133</td><td>0.103</td>
  </tr>
  <tr>
    <td>Change bin inds</td>
    <td>2.842</td><td>2.933</td><td>2.980</td><td>3.042</td><td>3.914</td><td>3.007</td><td>0.125</td>
  </tr>
  <tr>
    <td>Less branches</td>
    <td>2.786</td><td>2.879</td><td>2.915</td><td>2.969</td><td>3.706</td><td>2.936</td><td>0.092</td>
  </tr>
</table>

<table>
  <tr>
    <th>Render depth</th>
    <th>min</th><th>25th</th><th>med</th><th>75th</th><th>max</th><th>mean</th><th>sdev</th>
  </tr>
  <tr>
    <td>Initial</td>
    <td>2.206</td><td>2.220</td><td>2.228</td><td>2.242</td><td>2.364</td><td>2.234</td><td>0.022</td>
  </tr>
  <tr>
    <td>SSE Gather</td>
    <td>2.099</td><td>2.119</td><td>2.137</td><td>2.156</td><td>2.242</td><td>2.141</td><td>0.028</td>
  </tr>
  <tr>
    <td>Change bin inds</td>
    <td>1.980</td><td>2.008</td><td>2.026</td><td>2.046</td><td>2.172</td><td>2.032</td><td>0.035</td>
  </tr>
  <tr>
    <td>Less branches</td>
    <td>1.905</td><td>1.934</td><td>1.946</td><td>1.959</td><td>2.012</td><td>1.947</td><td>0.019</td>
  </tr>
</table>

That's another 0.07ms off the total, for about a 10% reduction in median total
cull time for this post, and a 12.7% reduction in median rasterizer time. And
for our customary victory lap, here's the VTune results after this change:

![Binning with branching improved](hotspots_binning_done.png)

The branch mispredictions aren't gone, but we did make a notable dent. It's
more obvious if you compare the number of clock cyles with the previous image.

And with that, I'll conclude this journey into both the triangle binner and the
dark side of speculative execution. We're also getting close to the end of this
series --- the next post will look again at the loading and rendering code we've
been intentionally ignoring for most of this series :), and after that I'll
finish with a summary and wrap-up --- including a list of things I didn't cover,
and why not.

