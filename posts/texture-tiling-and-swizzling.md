-title=Texture tiling and swizzling
-time=2011-01-17 09:57:01
If you're working with images in your program, you're most likely using a regular 2D array layout to store image data. Which is to say, it's basically a 1D array of `width * height` pixels, and the index of every pixel in the array is normally computed as `y * width + x` \(or, more generally, `y * stride + x` when you don't require the lines to be densely packed\). Simple and easy, but it has a problem: if you have a cache, this is very efficient when processing pixels in one direction \(left to right\) and very inefficient if you move at a 90 degree angle to that direction \(top to bottom\): the first pixel of every row is in a different cache line \(unless your image is tiny\), so you get tons of cache misses.

That's one of the reasons why GPUs tend to prefer *tiled* or *swizzled* texture formats, which depart from the purely linear memory layout to something a tad more involved. The specifics heavily depend on the internals of the memory subsystem, but while the respective magic values may be different between different pieces of hardware, the general principles are always the same.

### Tiling

This one's fairly simple. You chop the image up into smaller subrects of M x N pixels. For hardware usage, M and N are always powers of 2. For example, with 64\-byte cache lines, you might decide to chop up 32bpp textures into tiles of 4x4 pixels, so each cache line contains one tile. That way, any traversal that doesn't skip around wildly through the image is likely to get roughly the same cache hit rates. It also means that all images must be padded to have widths and heights that are multiples of 4. Overall, addressing looks like this:

```cpp
  // per-texture constants
  uint tileW = 4;
  uint tileH = 4;
  uint widthInTiles = (width + tileW-1) / tileW;

  // actual addressing
  uint tileX = x / tileW;
  uint tileY = y / tileH;
  uint inTileX = x % tileW;
  uint inTileY = y % tileH;

  pixel = image[(tileY * widthInTiles + tileX) * (tileW * tileH)
                + inTileY * tileW
                + inTileX];
```

This looks like a bunch of work, but it's very simple to do in hardware \(details in a minute\), and software implementations can be optimized nicely as well \(under the right conditions\).

### Swizzling

"Tiling" is a fairly well\-defined technique; people referring to it generally mean the same thing \(the technique I just described\). "Swizzling" is somewhat more complicated; there's several other popular uses of the word, e.g. "pointer swizzling" or the vector swizzles \(like "v.xywz"\) used in various shading languages\) that have nothing at all to do with image / texture storage. And even confined to the realm of graphics hardware, there's several techniques in use. What they all have in common is that they effectively form the linear address then swap some of the memory address bits around. Time for some ASCII\-art. Again, let's assume a 32bpp RGBA texture, say 256x256 pixels. Then the pixel address \(in bytes\) when using regular linear addressing looks like this on the bit level:

```
MSB ...                bits                     ... LSB
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|y7|y6|y5|y4|y3|y2|y1|y0|x7|x6|x5|x4|x3|x2|x1|x0|c1|c0|
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

where x0..7 are the bits corresponding to the x coordinates, y0..7 are the bits corresponding to the y coordinate, and c0..1 correspond to the color channel index---whether your image uses ARGB, BGRA or RGBA byte order is a holy war I won't concern myself with today :\). A popular swizzle pattern is Morton order \(also often called "Z\-order" because the order that pixels are stored in follows a distinct recursive Z\-shaped pattern\) which interleaves the x and y bits:

```
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|y7|x7|y6|x6|y5|x5|y4|x4|y3|x3|y2|x2|y1|x1|y0|x0|c1|c0|
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

While somewhat awkward in software, this kind of bit\-interleaving is relatively easy and cheap to do in hardware since no logic is required \(it does affect routing complexity, though\). Or you could do this:

```
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|y7|y6|y5|y4|y3|y2|x7|x6|x5|x4|x3|x2|y1|y0|x1|x0|c1|c0|
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

Note that this is just the 4x4 pixel tiles I described earlier: the hardware implementation is very simple indeed. Or maybe you want to go completely wild:

```
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|y7|y6|y5|y4|y3|x7|x6|x3|x4|x5|c1|c0|y2|x2|y1|x1|y0|x0|
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

This forms tiles of 8x8 pixels with morton\-code addresses inside tiles. Each tile just contains one color channel, with the 4 tiles for the 4 color channels following each other, and the rest is stored in mostly row\-major order but with bits x3 and x5 swapped. You can get even fancier and maybe XOR some bits together, but I think you get the idea.

### Nested tiling

The last few examples already touch on another idea: One way to construct swizzle patterns is by nesting different tile sizes. You could put 8x8 tiles into 32x32 tiles, for example. In fact, the morton code/z\-order swizzling takes that idea to its logical extreme: it's effectively 2x2 tiles inside 4x4 tiles inside 8x8 tiles and so on. You can even view it as 2x2 tiles inside 4x2 tiles inside 4x4 tiles inside 8x4 tiles inside 8x8 tiles and so on \(accounting for each individual bit as it gets added\). This viewpoint suggests a natural way to handle non\-square textures with power\-of\-2 dimensions when using morton\-order swizzling \(the straight variant only works well with square dimensions\): Say you have a WxH pixels texture where W and H are both powers of 2 and W \> H \(the other case is symmetrical\). Then you use tiles of HxH pixels with morton\-order swizzling inside them. This gives you all the advantages of morton order, but doesn't force you to pad the texture up to square size in memory \(which would be a significant waste\).

All schemes that can be expressed as nested tiling have a nice property: they consume bits from the x and y coordinates in order. They might interleave them in arbitrary groups, but they'll never swap the relative order of bits inside a coordinate. This turns out to be very convenient for software implementations, and I'll limit myself to texture swizzle patterns that can be expressed as some form of nested tiling in the rest of this post.

The "nested tiling" approach also generalizes to non\-power\-of\-2 texture sizes. In general, you have some "top\-level tile size" \(the largest of your nested tile sizes\)---say 32x32 pixels. Above that, you use the regular 2D \(row\-major\) array order. You need to pad textures to be multiples of 32 pixels in width and height, but they don't need to have power\-of\-2 dimensions. Of course that means you can't easily represent anything above the 32x32 pixel level with a nice per\-bit diagram anymore. More about this later.

### Swizzling textures in software

Okay, so this is the real reason for me to write this post. Over the past few months I've written fast texture swizzling functions for various platforms. Normally this is either something you deal with at asset build time \(you just store them in your platform\-preferred format on disk\) or something the driver handles for you \(if you're working on PC or Mac\), but in this particular case we needed to deal with compressed images \(think JPEG or PNG\) that had to be converted to the platform\-specific swizzled format at runtime. This conversion step needed to be fast, and it needed to support updating arbitrary subrects of an image---that last requirement being there because a\) some textures are updated dynamically from an in\-memory copy \(with dirty rectangles available\), and b\) decompression and swizzling are interleaved to prevent data falling out of the cache.

Luckily, two of the platforms use texture swizzling methods that fit within the "nested tiling" schemes described above, and the third didn't quite fit into the mold but had its quirks only within the lower few bits, which essentially boils down to unrolling the lower\-level loops a bit more and modifying some of the unrolled copies to do something slightly different. But I'm getting ahead of myself.

### Bulk processing

There's two basic ways to structure the actual swizzling: either you go through the \(linear\) source image in linear order, writing in \(somewhat\) random order, or you iterate over the output data, picking the right source pixel for each target location. The former is more natural, especially when updating subrects of the destination texture \(the source pixels still consist of one linear sequence of bytes per line; the pattern of destination addresses written is considerably more complicated\), but the latter is usually much faster, especially if the source image data is in cached memory while the output data resides in non\-cached write\-combined memory where non\-sequential writes are expensive.

Luckily, we don't need to write the data in a completely sequential fashion: write combining works at the level of cache lines. As long as we make sure to always write full aligned cache\-lines worth of data, we can skip around merrily without incurring any performance penalties. You can still process data mostly in source order \(more convenient with partial updates\), only having to write data in "destination order" in the innermost loop. You size that innermost loop to generate exactly one cache line worth of data. Assuming a Morton order swizzle pattern and 32bpp textures, that size would be 4x4 pixels with 64\-byte cache lines, 8x4 pixels with 128\-byte cache lines, and so on.

So you read an aligned 4x4 \(or 8x4, or whatever\) tile of pixels from the source, permute the pixel order a bit \(with a fixed permutation\), and store it as one cache line. That's a fairly simple exercise in either integer or SIMD code and I'm not gonna bore you with it. This leaves us with a couple of problems however:

* What order do we process the small tiles in? Source order is preferable, but is that efficient?
* How do we update the source/destination pointers for the next tile? When using SIMD, we usually have some slots to spare for integer instructions in the inner loop, but e.g. a complete bit\-interleave for Morton encoding still takes up more than a dozen instructions \(and a number of registers to hold integer constants\).
* This gives us a nice way to handle aligned 4x4 \(8x4\) blocks, but what do we do with the rest of the update region?

Fortunately, there's a neat solution to all those problems.

### Power\-of\-2 textures

For a while, let's assume that our texture has power\-of\-2 dimensions, though not necessarily square. Let's say we have this swizzle pattern:

```
       +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
offs = |y7|y6|y5|x7|x6|x5|y4|y3|x4|x3|y2|y1|y0|x2|x1|x0|c1|c0|
       +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

which is a 8x8\-inside\-32x32 tile pattern with no channel reordering. Ideally, we'd like to step through our texture in source order. That means our loop structure looks something like this:

```cpp
  for (y=y0; y < y1; y++) {
    U32 *src = (U32 *) (src + y * src_pitch);
    for (x=x0; x < x1; x++) {
      U32 pixel = src[x0];
      // compute dest_offs somehow!
      dest[dest_offs] = pixel;
    }
  }
```

First step: divide and conquer. We know that all the "y" bits will be the same for the whole line, so it makes sense to split the destination offset into an "x" and "y" component. Also, the channels aren't reordered and we always copy 32 bits at a time, so we can ignore the "c" bits completely. We end up with:

```
       +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
offs = |y7|y6|y5| 0| 0| 0|y4|y3| 0| 0|y2|y1|y0| 0| 0| 0| 0| 0|
       +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
       +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
     + | 0| 0| 0|x7|x6|x5| 0| 0|x4|x3| 0| 0| 0|x2|x1|x0| 0| 0|
       +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

I use "\+" and not "\|" for two reasons: First, a lot of processors have addressing modes using the sum of two registers, but none that I know have addressing modes that bitwise\-or two registers together. Second, the actual addressing computation is something like `dest + (offs_y | offs_x)`, and if we express it as a sum, we can compute it as `(dest + offs_y) + offs_x` instead; the first term is constant per line, so it only needs to be computed once. The updated loop structure looks like this:

```cpp
  U32 offs_x0 = swizzle_x(x0); // offset in *bytes*
  U32 offs_y  = swizzle_y(y0); // dto

  for (y=y0; y < y1; y++) {
    U32 *src = (U32 *) (src + y * src_pitch + x0*4);
    U8 *dest_line = dest + offs_y;
    U32 offs_x = offs_x0;

    for (x=x0; x < x1; x++) {
      U32 pixel = *src++;
      *((U32 *) (dest_line + offs_x)) = pixel;
      // compute offs_x for next pixel
    }

    // compute offs_y for next line
  }
```

The only remaining bit to fill in is how to update offs\_x and offs\_y. If we look at the bits for `offs_x` and `offs_y` again, it's clear what we'd like to do: increment the "x" bits, and have the carries silently pass over the "holes" between them. But wait, that's easy: All we need to do is make sure to have 1\-bits in our addend in these places. That way, if the x\-increment carries *into* the hole, the carry will ripple all through it and into the next x\-bit \(which is exactly what we want\). So to increment `offs_x`, we add:

```
          +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
offs_x' = | 0| 0| 0|x7|x6|x5| 0| 0|x4|x3| 0| 0| 0|x2|x1|x0| 0| 0|
          +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
          +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        + | 0| 0| 0| 0| 0| 0| 1| 1| 0| 0| 1| 1| 1| 0| 0| 1| 0| 0|
          +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

That is, we take all the "holes" left to the first x\-bit \(x0\), set them to 1, also set the location of bit x0 to 1, and add that to `offs_x`. The result will likely have some of the "hole" bits set, which we don't want, so we have to follow this with a bitwise AND to clear them again. We could implement this right now \(cost: one add and a bitwise and, that's very reasonable\), but it pays to think some more about the magic constants we need. And\-mask first: That's easy. We just need something that's 1 wherever "x"\-bits are. Let's call that `x_mask`. The second is the value to add. Start with `~x_mask`---this has 1\-bits in all the holes. It also has 1\-bits after the last x\-bit \(no problem, we clear those bits every iteration anyway\) and before the first "x"\-bit. We can use that last fact to avoid having to determine the position of "x0" so we can put a strategical 1 there: Just add a 1 at the very first bit and let it ripple through to the position of x0! \(That's the same trick as using the 1\-bits to skip over holes\). Putting it all together, we get:

```cpp
  // update offs_x:
  offs_x = (offs_x + (~x_mask + 1)) & x_mask;
```

which can be further simplified \(if you know your two's complement identities\) into:

```cpp
  offs_x = (offs_x - x_mask) & x_mask;
```

In short, we don't even need two registers to hold the two constants---if we use this formulation, the constant argument to the sub and the and\-mask are the same! And `x_mask` \(and `y_mask`\) are in fact the only details about the swizzle pattern that ever enter into the whole swizzling loop. You can use the same loop for different patterns---all you need are the right masks. This is great if the exact swizzle pattern depends on the data, like the "nonsquare\-Morton" scheme described above. The complete inner loop above can be compiled into four PowerPC instructions per pixel \(plus loop control\): `lwzu, subf, stwx, and`. Details are left as an exercise to the reader :\)

This directly leads to a nice function to swizzle handle the non\-aligned parts of the image subrect. And you can use the same approach to update destination pointers between 4x4 \(8x4\) tiles in the "big loop"; you just modify `x_mask` and `y_mask` by clearing the lowest few x/y bits.

### Non\-power\-of\-2 textures

The idea here is, again, simple: The texture is padded to top\-level tile boundaries \(whatever that tile size is\), so the bottom bits follow the swizzle pattern as usual. The remaining bits encode the tile index in usual row\-major fashion: `tileY * tilesPerRow + tileX`. Because the innermost loop may \(and often will\) cross top\-level tile boundaries, we will need to increase `tileX` whenever we wrap around into the next tile. The easiest way to get that to happen is to count all of the "top" bits \(that contain the tile index\) as part of the x coordinate, and set up `x_mask` accordingly. That way, whenever we wrap into the next tile in the same row, the tile index will be incremented, which is exactly what we want! The inner loop stays unchanged, perfect.

But what do we do in the y loop? Every few rows, we'll "carry" into the next row of tiles and need to adjust the tile index accordingly, by adding `tilesPerRow` to the tile index. `tilesPerRow` is not a power of 2, so we can't neatly express that using the carry trick, and besides we already decided to include those bits in the `x_mask`; the `y_mask` can't overlap with the `x_mask` or our whole add\-instead\-of\-or trick collapses.

Luckily, this is very easy to fix: the `y_mask` is already set up to include all of the "swizzled" y bits, but not the tile index. So whenever we wrap around into the next tile row, the incremented `offs_y` will be zero. All we need to do is to add `tilesPerRow` \(shifted by the appropriate number of bits so we actually hit the tile index\) to our destination address whenever that happens. Since we already decided that `offs_x` really contains x\-plus\-tile\-index, it's fairly natural to add this offset to `offs_x0` \(the initial x offset we use at the start of every line\).

The final code looks like this:

```cpp
  U32 offs_x0 = swizzle_x(x0); // offset in *bytes*
  U32 offs_y  = swizzle_y(y0); // dto
  U32 x_mask  = swizzle_x(~0u);
  U32 y_mask  = swizzle_y(~0u);
  U32 incr_y  = swizzle_x(padded_width);

  // step offs_x0 to the right row of tiles
  offs_x0 += incr_y * (y0 / tile_height);

  for (y=y0; y < y1; y++) {
    U32 *src = (U32 *) (src + y * src_pitch + x0*4);
    U8 *dest_line = dest + offs_y;
    U32 offs_x = offs_x0;

    for (x=x0; x < x1; x++) {
      U32 pixel = *src++;
      *((U32 *) (dest_line + offs_x)) = pixel;
      offs_x = (offs_x - x_mask) & x_mask;
    }

    offs_y = (offs_y - y_mask) & y_mask;
    if (!offs_y) offs_x0 += incr_y; // wrap into next tile row
  }
```

Note that I use `swizzle_x` \(which swizzles x\-coordinates\) and `swizzle_y` to also compute what `x_mask` and `y_mask` are, by swizzling ~0 \(i.e. all 1 bits, otherwise known as \-1\). If you want this to work correctly, both functions need to follow the rules outlined in the text above---i.e. `swizzle_x` handles both swizzled x\-part and tile index, while `swizzle_y` ignores the tile index \(that's why there's some adjustment after the initialization to point offs\_x0 to the right row of tiles\).

### Conclusion and generalizations

This code is fully generic and can handle *any* swizzling pattern that can be expressed as some form of nested tiling, with regular row\-major array indexing at the tile level. You need to provide the correct swizzle functions, but they're only used once at the beginning, so their speed is not that important. And of course, it's still at least 4 operations per pixel---you really want to combine this with an optimized loop that writes whole destination cache lines as a time, as outlined earlier. The loop incrementing works exactly the same. But if you're processing e.g. 8x4 tiles, you want to increment the x\-coordinate by 8 and the y coordinate by 4 in every iteration. As long as you're increment in power\-of\-2 sized steps, you can use the exact same code. The only modification is that you now initialize `x_mask` as `swizzle_x(~0u << 3) == swizzle_x((U32) -8)`. `y_mask` works analogously. And finally, of course you can also step in now\-power\-of\-2 increments, but in that case you need to perform the increment using something like `offs_x = (offs_x - swizzle_x(-5)) & swizzle_x(-1);` \(hoisting constants of course\). In other words, you need to spend an extra register and get a tiny bit more setup work.

Finally, the same approach can be extended to volume textures. You end up with 3 components for the offset \(`offs_x`, `offs_y` and `offs_z`\) with their respective bit masks, but the underlying ideas are exactly the same.

### Credit where credit is due

I've described this for textures, but in fact the whole idea of addressing 2D data with tiled/swizzled indices is applicable to all 2D data that is traversed in both row and column direction. For example, fast linear algebra packages \(BLAS etc.\) tend to process matrices as blocks \(in tiles, effectively\) to increase cache coherence, and some use tiled storage formats or Morton order. A lot of sources describe Morton order; general "bit\-interleave patterns" \(as captured by the "nested tiles"\) notion aren't as common. The paper ["Morton-order Matrices Deserve Compilers' Support"](http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.72.7223) by Wise and Frens makes the case for supporting Z\-order array addressing in compilers and describes, among other things, a special case of the "subtract\-and" scheme limited to Morton order. It doesn't mention the "truncated" Morton order way to store rectangular matrices, instead pushing to always treat large matrices as square, but returning unused pages to the OS. This seems highly dubious to me from an address space fragmentation perspective; "truncated" Morton order is just as expensive/cheap as the regular kind \(in terms of iteration overhead, anyway\) and only requires padding dimensions up to the next power of 2. While this is still a hefty cost, it has an upper bound on "badness" \(it never wastes more than 3/4 of the address space it allocates\).

The technique of splitting bit fields inside an integer register and using banks of 1s to make the carries pass through is definitely not new; it's part of computer graphics lore and I've seen it in, among other things, several texture mapping inner loops, but it's somewhat underdocumented, which is one of the reasons I wrote this post. While I'm certain I'm not the first to discover that the "subtract\-and" method works when iterating over codes using arbitrary bit\-skip patterns, not just Morton codes, I've never seen it documented anywhere. The same goes for the non\-power\-of\-2 handling.
