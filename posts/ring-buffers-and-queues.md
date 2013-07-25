-title=Ring buffers and queues
-time=2010-12-15 07:57:11
The data structure is extremely simple: a bounded FIFO. One step up from plain arrays, but still, it's very basic stuff. And if you're doing system programming, particularly anything involving IO or directly talking to hardware \(boils down to the same thing really\), it's absolutely everywhere. It's also very useful to communicate between different threads. I have some notes on the topic than aren't immediately obvious, so it's time to write them up. I'm only going to talk about the single producer, single consumer \(SPSC\) case since that's what you usually have when you're dealing with hardware.

The producer produces commands/objects/whatever in some way and appends them to the queue. The consumer pops an item from the start and does its work. If the queue is full, the producer has to wait; if it's empty, the consumer has to wait. As programmer feeding hardware \(or being fed from hardware\), you're generally trying to reach a steady state that does neither. The actual data structure always looks something like this:

```
struct FIFO {
  ElemType Elem[SIZE];
  uint ReadPos;
  uint WritePos;
};
```

In hardware, the elements are stored in some block of memory somewhere, and `ReadPos`/`WritePos` usually come in the form of memory\-mapped registers. In software, you normally use a slightly different layout \(put one pointer before the array and the other after it and make sure it's all in different cache lines to avoid false sharing\). You can find details on this elsewhere; I'm gonna be focusing on a different, more conceptual issue.

What `Elem` means is not really up to interpretation; it's an array, just a block of memory where you drop your data/commands/whatever at the right position. `ReadPos`/`WritePos` have a bit more room for interpretation; there are two common models with slightly different tradeoffs.

### Model 1: Just array indices \(or pointers\)

This is what you normally have when talking to hardware. In this model, the two positions are just array indices. When adding an element, you first write the new element to memory via `Elem[WritePos] = x;` and then compute the next write position as `WritePos = (WritePos + 1) % SIZE;`; reading is analogous. If `ReadPos == WritePos`, the queue is empty. Otherwise, the queue currently has `WritePos - ReadPos` elements in it if `WritePos > ReadPos`, and `WritePos + SIZE - ReadPos` elements if `WritePos < ReadPos`.

There's an ambiguous case though: if we fill up the queue completely, we end up with `ReadPos == WritePos`, which is then interpreted as an empty queue. \(Storing `WritePos - 1` doesn't solve this; now the "queue empty" case becomes tricky\). There's a simple solution though: *Don't do that*. Seriously. When adding elements to the queue, block when it contains `SIZE - 1` elements. What you definitely shouldn't do is get fancy and use special encodings for an empty \(or full\) queue and riddle the code with ifs. I've seen this a couple times, and it's *bad*. It makes "lock\-free" implementations hard, and when dealing with hardware, *you usually have no locks*. If you use this method, just live with the very slight memory waste.

### Model 2: Virtual stream

The intuition here is that you're not giving the actual position in the ring buffer, but the "distance travelled" from the start. So if you've wrapped around the ring buffer twice, your current `WritePos` would be `2*SIZE`, not `0`.

This is just a slight change, but with important consequences: writing elements is `Elem[WritePos % SIZE] = x;` and updating the index is `WritePos++;` \(and analogous for `ReadPos`\). In other words, you delay the reduction modulo `SIZE`. For this to be efficient, you normally want to pick a power of 2 for `SIZE`; this makes the wrapping computation cheap and will automatically do the right thing if one of the positions ever overflows. This leads to very straightforward, efficient code. The number of items in the queue is `WritePos - ReadPos`; no case distinction, unsigned arithmetic does the right thing. No trouble with the last element either \(if the queue is full, then WritePos == ReadPos \+ SIZE \- no problem!\).

With non\-pow2 SIZE, you still need to do some amount of modulo reduction on increment \- always modulo `N*SIZE`, where `N` is some constant \>1 \(if you use 1, you end up with Method 1\). This is more work than for method 1, so it seems like a waste. But it's not quite that simple.

### Virtual streams are a useful model!

One advantage of virtual streams is it's usually easier to state \(and check\) invariants using this model; for example, if you're streaming data from a file \(and I mean streaming in the original sense of the word, i.e. reading some amount of data sequentially and piece by piece without skipping around\), it's very convenient to use file offsets for the two pointers. This leads to very readable, straightforward logic: the two invariants for your streaming buffer are `WritePos >= ReadPos` and `WritePos - ReadPos <= SIZE`, and one of them \(`WritePos` \- you'd pick a different name in this case\) is just the current file pointer which you need to dispatch the next async read. No redundant variables, no risk of them getting out of sync. As a bonus, if you align your destination buffer address to whatever alignment requirement async reads have, it also means you can DMA data directly from the drive to your streaming buffer without any copying \(the lowest bits of the file pointer and the target address need to match for this to work, and you get that almost for free out of this scheme\).

This scheme is particularly useful for sound playback, where the "consumer" \(the audio HW\) keeps reading data whether you're ready or not. Of course you try to produce data fast enough, but sometimes you may be too late and the audio HW forges ahead. In that case, you want to know *how far* ahead it got \(at least if you're trying to keep audio and video in sync\). With a "virtual stream" type API, you have a counter for the total number of samples \(or blocks, or whatever\) played and can immediately answer this question. Annoyingly, almost all sound APIs only give you the current read position mod the ring buffer size, so you don't have this information. This usually leads to a little song and dance routine in low\-level sound code where you query a timer every time you ask for the current read position. Next time, you look at the time difference; if it's longer than the total length of the ring buffer in ms minus some fudge factor, you use the secondary timer to estimate how many ms you skipped, otherwise you can use the read pointer to determine how big the skip was.

It's not a big deal, but it *is* annoying, especially since it's purely an API issue \- the sound driver actually knows how many samples were played, even though the HW usually uses method 1, since the driver gets an interrupt whenever the audio HW is done playing a block. This is enough to disambiguate the ring buffer position. But for some reason most audio APIs don't give you this information, so you have to guess \- argh!

This is a general pattern: If you have some type of separate feedback channel, the regular ring buffer semantics are fine. But when the FIFO is really the only means of communication, the virtual stream model is more expressive and hence preferable. Particularly with pow2 sizes, where everything just works out automagically without any extra work. Finally, a nice bonus on PowerPC\-based platforms is that address generation for the array access can be done with a single `rlwinm` instruction if `SIZE` and `sizeof(ElemType)` are both powers of 2. This is even less work than the regular mod\-after\-increment variant!