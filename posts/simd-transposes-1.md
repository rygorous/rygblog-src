-title=SIMD transposes 1
-time=2013-07-09 08:25:58
This one tends to show up fairly frequently in SIMD code: Matrix transposes of one sort or another. The canonical application is transforming data from AoS \(array of structures\) to the more SIMD\-friendly SoA \(structure of arrays\) format: For concreteness, say we have 4 float vertex positions in 4\-wide SIMD registers

```
  p0 = { x0, y0, z0, w0 }
  p1 = { x1, y1, z1, w1 }
  p2 = { x2, y2, z2, w2 }
  p3 = { x3, y3, z3, w3 }
```

and would really like them in transposed order instead:

```
  X = { x0, x1, x2, x3 }
  Y = { y0, y1, y2, y3 }
  Z = { z0, z1, z2, z3 }
  W = { w0, w1, w2, w3 }
```

Note that here and in the following, I'm writing SIMD 4\-vectors as arrays of 4 elements here \- none of this nonsense that some authors tend to do where they write vectors as "w, z, y, x" on Little Endian platforms. Endianness is a concept that makes sense for numbers and no sense at all for arrays, which SIMD vectors are, but that's a rant for another day, so just be advised that I'm always writing things in the order that they're stored in memory.

Anyway, transposing vectors like this is one application, and the one I'm gonna stick with for the moment because it "only" requires 4x4 values, which are the smallest "interesting" size in a certain sense. Keep in mind there are other applications though. For example, when implementing 2D separable filters, the "vertical" direction \(filtering between rows\) is usually easy, whereas "horizontal" \(filtering between columns within the same register\) is trickier \- to the point that it's often faster to transpose, perform a vertical filter, and then transpose back. Anyway, let's not worry about applications right now, just trust me that it tends to come up more frequently than you might expect. So how do we do this?

### One way to do it

The method I see most often is to try and group increasingly larger parts of the result together. For example, we'd like to get "x0" and "x1" adjacent to each other, and the same with "x2" and "x3", "y0" and "y1" and so forth. The canonical way to do this is using the "unpack" \(x86\), "merge" \(PowerPC\) or "unzip" \(ARM NEON\) intrinsics. So to bring "x0" and "x1" together in the right order, we would do:

```
  a0 = interleave32_lft(p0, p1) = { x0, x1, y0, y1 }
```

where `interleave32_lft` \("interleave 32\-bit words, left half"\) corresponds to `UNPCKLPS` \(x86, floats\), `PUNPCKLDQ` \(x86, ints\), or `vmrghw` \(PowerPC\). And to be symmetric, we do the same thing with the other half, giving us:

```
  a0 = interleave32_lft(p0, p1) = { x0, x1, y0, y1 }
  a1 = interleave32_rgt(p0, p1) = { z0, z1, w0, w1 }
```

where `interleave32_rgt` corresponds to `UNPCKHPS` \(x86, floats\), `PUNPCKHDQ` \(x86, ints\), or `vmrglw` \(PowerPC\). The reason I haven't mentioned the individual opcodes for NEON is that their "unzips" always work on pairs of registers and handle both the "left" and "right" halves at once, forming a combined

```
  (a0, a1) = interleave32(p0, p1)
```

operation \(`VUZP.32`\) that also happens to be a good way to thing about the whole operation on other architectures \- even though it is not the ideal way to perform transposes on NEON, but I'm getting ahead of myself here. Anyway, again by symmetry we then do the same process with the other two rows, yielding:

```
  // (a0, a1) = interleave32(p0, p1)
  // (a2, a3) = interleave32(p2, p3)
  a0 = interleave32_lft(p0, p1) = { x0, x1, y0, y1 }
  a1 = interleave32_rgt(p0, p1) = { z0, z1, w0, w1 }
  a2 = interleave32_lft(p2, p3) = { x2, x3, y2, y3 }
  a3 = interleave32_rgt(p2, p3) = { z2, z3, w2, w3 }
```

And presto, we now have all even\-odd pairs nicely lined up. Now we can build `X` by combining the left halves from `a0` and `a2`. Their respective right halves also combine into `Y`. So we do a similar process like before, only this time we're working on groups that are pairs of 32\-bit values \- in other words, we're really dealing with 64\-bit groups:

```
  // (X, Y) = interleave64(a0, a2)
  // (Z, W) = interleave64(a1, a3)
  X = interleave64_lft(a0, a2) = { x0, x1, x2, x3 }
  Y = interleave64_rgt(a0, a2) = { y0, y1, y2, y3 }
  Z = interleave64_lft(a1, a3) = { z0, z1, z2, z3 }
  W = interleave64_rgt(a1, a3) = { w0, w1, w2, w3 }
```

This time, `interleave64_lft` \(`interleave64_rgt`\) correspond to `MOVLHPS` \(`MOVHLPS`\) for floats on x86, `PUNPCKLQDQ` \(`PUNPCKHQDQ`\) for ints on x86, or `VSWP` of `d` registers on ARM NEON. PowerPCs have no dedicated instruction for this but can synthesize it using `vperm`. The variety here is why I use my own naming scheme in this article, by the way.

Anyway, that's one way to do it with interleaves. There's more than one, however!

### Interleaves, variant 2

What if, instead of interleaving `p0` with `p1`, we pair it with `p2` instead? By process of elimination, that means we have to pair `p1` with `p3`. Where does that lead us? Let's find out!

```
  // (b0, b2) = interleave32(p0, p2)
  // (b1, b3) = interleave32(p1, p3)
  b0 = interleave32_lft(p0, p2) = { x0, x2, y0, y2 }
  b1 = interleave32_lft(p1, p3) = { x1, x3, y1, y3 }
  b2 = interleave32_rgt(p0, p2) = { z0, z2, w0, w2 }
  b3 = interleave32_rgt(p1, p3) = { z1, z3, w1, w3 }
```

Can you see it? We have four nice little squares in each of the quadrants now, and are in fact just one more set of interleaves away from our desired result:

```
  // (X, Y) = interleave32(b0, b1)
  // (Z, W) = interleave32(b2, b3)
  X = interleave32_lft(b0, b1) = { x0, x1, x2, x3 }
  Y = interleave32_rgt(b0, b1) = { y0, y1, y2, y3 }
  Z = interleave32_lft(b2, b3) = { z0, z1, z2, z3 }
  W = interleave32_rgt(b2, b3) = { w0, w1, w2, w3 }
```

This one uses just one type of interleave instruction, which is preferable if you the 64\-bit interleaves don't exist on your target platform \(PowerPC\) or would require loading a different permutation vector \(SPUs, which have to do the whole thing using `shufb`\).

Okay, both of these methods start with a 32\-bit interleave. What if we were to start with a 64\-bit interleave instead?

### It gets a bit weird

Well, let's just plunge ahead and start by 64\-bit interleaving `p0` and `p1`, then see whether it leads anywhere.

```
  // (c0, c1) = interleave64(p0, p1)
  // (c2, c3) = interleave64(p2, p3)
  c0 = interleave64_lft(p0, p1) = { x0, y0, x1, y1 }
  c1 = interleave64_rgt(p0, p1) = { z0, w0, z1, w1 }
  c2 = interleave64_lft(p2, p3) = { x2, y2, x3, y3 }
  c3 = interleave64_rgt(p2, p3) = { z2, w2, z3, w3 }
```

Okay. For this one, we can't continue with our regular interleaves, but we still have the property that each of our target vectors \(X, Y, Z, and W\) can be built using elements from only two of the c's. In fact, the low half of each target vector comes from one c and the high half from another, which means that on x86, we can combine the two using `SHUFPS`. On PPC, there's always `vperm`, SPUs have `shufb`, and NEON has `VTBL`, all of which are much more general, so again, it can be done there as well:

```
  // 4 SHUFPS on x86
  X = { c0[0], c0[2], c2[0], c2[2] } = { x0, x1, x2, x3 }
  Y = { c0[1], co[3], c2[1], c2[3] } = { y0, y1, y2, y3 }
  Z = { c1[0], z1[2], c3[0], c3[2] } = { z0, z1, z2, z3 }
  W = { c1[1], c1[3], c3[1], c3[3] } = { w0, w1, w3, w3 }
```

As said, this one is a bit weird, but it's the method used for `_MM_TRANSPOSE4_PS` in Microsoft's version of Intel's `emmintrin.h` \(SSE intrinsics header\) to this day, and used to be the standard implementation in GCC's version as well until [it got replaced](http://gcc.gnu.org/ml/gcc-patches/2005-10/msg00324.html) with the first method I discussed.

Anyway, that was starting by 64\-bit interleaving `p0` and `p1`. Can we get it if we interleave with `p2` too?

### The plot thickens

Again, let's just try it!

```
  // (c0, c2) = interleave64(p0, p2)
  // (c1, c3) = interleave64(p1, p3)
  c0 = interleave64_lft(p0, p2) = { x0, y0, x2, y2 }
  c1 = interleave64_lft(p1, p3) = { x1, y1, x3, y3 }
  c2 = interleave64_rgt(p0, p2) = { z0, w0, z2, w2 }
  c3 = interleave64_rgt(p1, p3) = { z1, w1, z3, w3 }
```

Huh. This one leaves the top left and bottom right 2x2 blocks alone and swaps the other two. But we still got closer to our goal \- if we swap the top right and bottom left element in each of the four 2x2 blocks, we have a full transpose as well. And NEON happens to have an instruction for that \(`VTRN.32`\). As usual, the other platforms can try to emulate this using more general shuffles:

```
  // 2 VTRN.32 on NEON:
  // (X, Y) = vtrn.32(c0, c1)
  // (Z, W) = vtrn.32(c2, c3)
  X = { c0[0], c1[0], c0[2], c1[2] } = { x0, x1, x2, x3 }
  Y = { c0[1], c1[1], c0[3], c1[3] } = { y0, y1, y2, y3 }
  Z = { c2[0], c3[0], c2[2], c3[2] } = { z0, z1, z2, z3 }
  W = { c2[1], c3[1], c2[3], c3[3] } = { w0, w1, w2, w3 }
```

Just like NEON's "unzip" instructions, `VTRN` both reads and writes two registers, so it is in essence doing the work of two instructions on the other architectures. Which means that we now have 4 different methods to do the same thing that are essentially the same cost in terms of computational complexity. Sure, some methods end up faster than others on different architectures due to various implementation choices, but really, in essence none of these are fundamentally more difficult \(or easier\) than the others.

Nor are these the only ones \- for the last variant, we started by swapping the 2x2 blocks within the 4x4 matrix and then transposing the individual 2x2 blocks, but doing it the other way round works just as well \(and is again the same cost\). In fact, this generalizes to arbitrary power\-of\-two sized square matrices \- you can just partition it into differently sized block transposes which can run in any order. This even works with rectangular matrices, with some restrictions. \(A standard way to perform "[chunky to planar](http://www.lysator.liu.se/~mikaelk/doc/c2ptut/)" conversion for old bit plane\-based graphics architectures uses this general approach to good effect\).

### And now?

Okay, so far, we have a menagerie of different matrix transpose techniques, all of which essentially have the same complexity. If you're interested in SIMD coding, I suppose you can just use this as a reference. However, that's not the actual reason I'm writing this; the real reason is that the whole "why are these things all essentially the same complexity" thing intrigued me, so a while back I looked into this and found out a whole bunch of cool properties that are probably not useful for coding at all, but which I nevertheless found interesting. In other words, I'll write a few more posts on this topic, which I will spend gleefully nerding out with no particular goal whatsoever. If you don't care, just stop reading now. You're welcome!