-title=The Magic Ring Buffer
-time=2012-07-22 06:43:18
This is a cute little trick that would be way more useful if there was proper OS support for it. It's useful in a fairly small number of cases, but it's nice enough to be worth writing up.

### Ring buffers

I'm assuming you know what a ring buffer is, and how it's typically implemented. I've [written about it before](*ring-buffers-and-queues), focusing on different ways to keep count of the fill state \(and what that means for the invariants\). Ring buffers are a really nice data structure \- the only problem is that everything that directly interfaces with ring buffers needs to be aware of the fact, to handle wrap\-around correctly. With careful interface design, this can be done fairly transparently: if you use the technique I described in ["Buffer-centric IO"](*buffer-centric-io), the producer has enough control over the consumer's view on the data to make the wrap\-around fully transparent. However, while this is a nice way of avoiding copies in the innards of an IO system, it's too unwieldy to pass down to client code. A lot of code is written assuming data that is completely linear in memory, and using such code with ring buffers requires copying the data out to a linear block in memory first.

Unless you're using what I'm calling a "magic ring buffer", that is.

### The idea

The underlying concept is quite simple: "unwrap" the ring by placing multiple identical copies of it right next to each other in memory. In theory you can have an arbitrary number of copies, but in practice two is sufficient in basically all practical use cases, so that's what I'll be using here.

Of course, keeping the multiple copies in sync is both annoying and tricky to get right, and essentially doing every memory access twice is a bad idea. Luckily, we don't actually need to keep two physical copies of the data around. Really the only thing we need is to have the same physical data in two separate \(logical, or virtual\) memory locations \- and virtual memory \(paging\) hardware is, at this point, ubiquitous. Using paging means we get some external constraints: buffers have to have sizes that are \(at least\) a multiple of the processor's page size \(potentially larger, if virtual memory is managed at a coarser granularity\) and meet some alignment constraints. If those restrictions are acceptable, then really all we need is some way to get the OS to map the same physical memory multiple times into our address space, using calls available from user space.

The right facility turns out to be memory mapped files: modern OSes generally provide support for anonymous mmaps, which are "memory mapped files" that aren't actually backed by any file at all \(except maybe the swap file\). And using the right incantations, these OSes can indeed be made to map the same region of physical memory multiple times into a contiguous virtual address range \- exactly what we need!

### The code

I've written a basic implementation of this idea in C\+\+ for Windows. The code is available [here](https://gist.github.com/3158316). The implementation is a bit dodgy \(see comments\) since Windows won't let me reserve a memory region for memory\-mapping \(as far as I can tell, this can only be done for allocations\), so there's a bit of a song and dance routine involved in trying to get an address we can map to \- other threads might be end up allocating the memory range we just found between us freeing it and completing our own mapping, so we might have to retry several times.

On the various Unix flavors, you can try the same basic principle, though you might actually need to create a backing file in some cases \(I don't see a way to do it without when relying purely on POSIX functionality\). For Linux you should be able to do it using an anonymous shared mmap followed by remap\_file\_pages. No matter which Unix flavor you're on, you can do it without a race condition, so that part is much nicer. \(Though it's really better without a backing file, or at most a backing file on a RAM disk, since you certainly don't want to cause disk IO with this\).

The code also has a small example to show it in action.

**UPDATE**: In the comments there is now also a link to two articles describing how to implement the same idea \(and it turns out using pretty much the same trick\) on MacOS X, and it turns out that [Wikipedia](http://en.wikipedia.org/wiki/Circular_buffer#Optimized_POSIX_Implementation) has working code for a \(race\-condition free\) POSIX variant as described earlier.

### Coda: Why I originally wanted this

There's a few cases where this kind of thing is useful \(several of them IO\-related, as mentioned in the introduction\), but the case where I originally really wanted this was for inter\-thread communication. The setting had one thread producing variable\-sized commands and one thread consuming them, with a SPSC queue inbetween them. Without a magic ring buffer, doing this was a major hassle: wraparound could theoretically happen anywhere in the middle of a command \(well, at any word boundary anyway\), so this case was detected and there was a special command to skip ahead in the ring buffer that was inserted whenever the "real" command would've wrapped around. With a magic ring buffer, all the logic and special cases just disappear, and so does some amount of wasted memory. It's not huge, but it sure is nice.