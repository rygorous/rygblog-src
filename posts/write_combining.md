-time=2013-01-29
-parent=occlusion_culling
# Write combining is not your friend

Most memory you deal with on a daily basis is cached; on CPUs, it's usually
write-back cached. While dealing with processor caches can be
counter-intuitive, caching works well most of the time, and it's mostly
transparent to the programmer (and certainly the user). However, if we are to
use the cache to service memory reads, we need to make sure to invalidate our
cache entries if someone else writes to the corresponding memory locations.
This is implemented using one of several mechanisms referred to as <a
href="http://en.wikipedia.org/wiki/Cache_coherence#Coherency_protocol">"coherency
protocols"</a>, which CPU cores use to synchronize their caches with each
other.

That is not the subject of this post, though. Because while such mechanisms are
in place for CPUs talking to each other, there is nothing equivalent for the
CPU talking to other non-CPU devices, such as GPUs, storage or network devices.
Generally, communication with such devices still happens via system memory (or
by memory-mapping registers or device memory so they *appear* to be
system memory, which doesn't make much difference from the CPU core's point of
view), but the CPU is not going to be notified of changes in a timely fashion,
so normal caching is out.

Originally, device memory used to be accessed completely without caching.
That's safe (or at least as safe as it's going to get) but also slow, because
each memory access gets turned into an individual bus transaction, which has
considerable overhead. Now anything related to graphics tends to move *a
lot* of data around. Before widespread hardware acceleration, it was mostly
the CPU writing pixels to the frame buffer, but now there's other
graphics-related writes too. So finally we get <a
href="http://en.wikipedia.org/wiki/Write-combining">write combining</a>, where
the CPU treats reads as uncached but will buffer writes for a while in the hope
of being able to combine multiple adjacent writes into a larger bus
transaction. This is much faster. Common implementations have much weaker
memory ordering guarantees than most memory accesses, but that's fine too; this
kind of thing tends to be used mainly for bulk transfers, where you really
don't care in which order the bytes trickle into memory. All you really want is
some mechanism to make sure that all the writes are done before you pull the
trigger and launch a command buffer, display a frame, trigger a texture upload,
whatever.

All this is fairly straightforward and reasonable. However, the devil's in the
details, and in practice write combining is finicky. It's really easy to make a
small mistake that results in a big performance penalty. I've seen this twice
in the last two days, on two different projects, so I've decided to write up
some guidelines.

### Where is write combining used?

I'm only going to talk about graphics here. For all I know, write-combining
might be used for lots of other things, but I would assume that even if that is
true, graphics is the only mainstream application where WC memory is exposed to
user-mode applications.

So the main way to get a pointer to write-combining memory is by asking a 3D or
GPGPU API to map a buffer or texture into memory: that is, using GL
`glMapBuffer`, D3D9 `Lock`, CL `clEnqueueMap*` or D3D1x `Map`. Not all such
buffers are write-combined, but those used for rapid uploads usually are -
doubly so if you're requesting a "write-only" mapping, which all mentioned APIs
support.

### What happens if you read from write-combined memory?

Sadly, the answer is not "reading from write-combined memory isn't allowed".
This would be much simpler and less error-prone, but at least on x86, the
processor doesn't even have the notion of memory that can be written but not
read.

Instead, what actually happens is that the read is treated as uncached. This
means all pending write-combining buffers get flushed, and then the read is
performed without any cache. Flushing write-combining buffers costs time and
results in stores of partial cache lines, which is also inefficient. And of
course uncached reads are really slow too.

*Don't read from write-combining memory*, unless you have a *very*
good reason to (you probably don't). In particular, *never read values back
from constant buffers, vertex buffers or index buffers you're currently writing
to*. Ever.

How bad can it possibly be? Let me show you an example. Here's an excerpt of a
VTune profile for an application I recently looked at:

![Reading from write-combined memory](wc_slow.png)

As you can see, a lot of time is being spent in
`CPUTModelDX11::SetRenderStates`. Worse, as VTune helpfully
highlights for us, this function runs at an absolutely appalling 9.721 clock
cycles per instruction (CPI Rate)! Now it turns out that a large fraction is
due to these innocent-looking lines that write to a constant buffer:

```cpp
    pCb = (CPUTModelConstantBuffer*)mapInfo.pData;
    pCb->World               = world;
    pCb->ViewProjection      = view * projection;
    pCb->WorldViewProjection = world * pCb->ViewProjection;
```

Note how `pCb->ViewProjection` is used as an argument for a matrix multiply in the last line. Now, here's the simple fix:

```cpp
    XMMATRIX viewProj = view * projection;
    pCb = (CPUTModelConstantBuffer*)mapInfo.pData;
    pCb->World               = world;
    pCb->ViewProjection      = viewProj;
    pCb->WorldViewProjection = world * viewProj;
```

And here's the corresponding VTune profile:

![Without the read](wc_faster.png)

Now, this profile was somewhat longer so the actual cycle counts are different,
but the point stands: This simple change made the function drop from the #5 to
the #12 spot, and based on the CPI rate, it now runs more than twice as fast
per invocation - mind you, 4.4 cycles/instruction is still pretty bad, but it's
certainly an improvement over the 9.7 we saw earlier.

### Other things to be careful about

Okay, so not reading is an important point. What else? Well, it depends on the
processor. Early x86s had fairly restrictive rules about write combining:
writes had to be of certain sizes, they needed to be properly aligned, and
accesses needed to be purely sequential. The first two can be dealt with, but
the latter is tricky when dealing with C/C++ compilers that try to move
schedule writes for optimum efficiency. For several years, it used to be that
you basically had to mark all pointers to vertex buffers etc. as
`volatile` to make sure the compiler didn't try to reorder writes
and inadvertently break write-combining in the process. While not as bad as
reads, this still results in a very noticeable drop in performance.

Luckily, x86 processors from about 2002 on are far more tolerant about writes
arriving out of order and will generally be able to combine writes even if
they're not perfectly sequential. However, other processors (such as those
found in some game consoles) aren't as tolerant; better safe than sorry. And
even if you don't strictly need to enforce sequential accesses, it's still a
good idea to write the code that way, because of the next rule:

*Avoid holes*. If you're writing to a memory range, write the whole range.
If you're writing a dynamic vertex buffer, write every field, *even if your
shader ignores some of them*. If you map a buffer, write the whole thing -
even if you (think you) know some of the contents don't need to change. Any
hole will break the sequence and turn what would otherwise be one large write
into at least two smaller ones. On some processors, it has other adverse
effects too. That's why you want to write struct fields sequentially, at least
in your source code - that way, it's easier to check against the struct
definition to make sure you left nothing out.

### Conclusion

Write combining is a powerful technique to accelerate writes to graphics
memory, but it's very easy to misuse in a way that causes severe performance
degradation. Worse, because things only get slow but don't crash, such problems
can creep in and not be noticed for a long time. Short of profiling your code
periodically, there's little you can do to find them. Here's the summary:

* If it's a dynamic constant buffer, dynamic vertex buffer or dynamic texture
  and mapped "write-only", it's probably write-combined.
* *Never* read from write-combined memory.
* *Try to keep writes sequential*. This is good style even when it's not
  strictly necessary. On processors with picky write-combining logic, you might
  also need to use `volatile` or some other way to cause the compiler
  not to reorder instructions.
* *Don't leave holes*. Always write large, contiguous ranges.
* *Check the rules for your target architecture*. There might be additional alignment and access width limitations.

If you live by these rules, write-combining can be a powerful ally in writing
high-performance graphics code. But never a friend - it *will* stab you
in the back on the first opportunity. So be careful.

