-title=SIMD transposes 2
-time=2013-08-19 19:00:00
I originally intended to write something different for part 2 of this series, but since I've started rewriting that article no less than 3 times at this point, I'm just gonna switch the order of topics around a bit.

### Transpose from even/odd interleaves

I already showed one instance of this last time ("variant 2") for the 4&times;4 case, but let's go at it a bit more systematically. Since we've already beaten this size to back, let's spice things up a bit and do 8&times;8 this time:

```
a0 a1 a2 a3 a4 a5 a6 a7
b0 b1 b2 b3 b4 b5 b6 b7
c0 c1 c2 c3 c4 c5 c6 c7
d0 d1 d2 d3 d4 d5 d6 d7
e0 e1 e2 e3 e4 e5 e6 e7
f0 f1 f2 f3 f4 f5 f6 f7
g0 g1 g2 g3 g4 g5 g6 g7
h0 h1 h2 h3 h4 h5 h6 h7
```

"Variant 2" from last time was the version where we started by interleaving rows not with their immediate neighbors, but with the rows that were two steps away. The key here is that we have to do multiple interleave steps to complete the transpose, and with every even-odd interleave, we space the original elements of a vector further apart. So if we interleaved rows A and B in the first step, we would have `a0 b0` after the first step, but `a0 xx b0 xx` as soon as we interleaved that with something else. That's not what we want. So instead, we start by interleaving rows A and E - after a total of 3 passes, that should put `e0` where it's supposed to go, 4 elements from `a0`.

The same argument goes for the other rows, too---so let's just do an even-odd interleave between the entire first half and the last half of our rows:

```
a0 e0 a1 e1 a2 e2 a3 e3
a4 e4 a5 e5 a6 e6 a7 e7
b0 f0 b1 f1 b2 f2 b3 f3
b4 f4 b5 f5 b6 f6 b7 f7
c0 g0 c1 g1 c2 g2 c3 g3
c4 g4 c5 g5 c6 g6 c7 g7
d0 h0 d1 h1 d2 h2 d3 h3
d4 h4 d5 h5 d6 h6 d7 h7
```

For the next step, we want to interleave the row containing `a0` with the row containing the elements that needs to end up 2 places away from `a0` in the final result - namely, `c0`, and similar for the other two rows. Which again boils down to doing an even-odd interleave between the entire first and second halves:

```
a0 c0 e0 g0 a1 c1 e1 g1
a2 c2 e2 g2 a3 c3 e3 g3
a4 c4 e4 g4 a5 c5 e5 g5
a6 c6 e6 g6 a7 c7 e7 g7
b0 d0 f0 h0 b1 d1 f1 h1
b2 d2 f2 h2 b3 d3 f3 h3
b4 d4 f4 h4 b5 d5 f5 h5
b6 d6 f6 h6 b7 d7 f7 h7
```

At this point we're just one turn of the crank away from the result we want, so let's go for it and do one more round of interleaves...

```
a0 b0 c0 d0 e0 f0 g0 h0
a1 b1 c1 d1 e1 f1 g1 h1
a2 b2 c2 d2 e2 f2 g2 h2
a3 b3 c3 d3 e3 f3 g3 h3
a4 b4 c4 d4 e4 f4 g4 h4
a5 b5 c5 d5 e5 f5 g5 h5
a6 b6 c6 d6 e6 f6 g6 h6
a7 b7 c7 d7 e7 f7 g7 h7
```

and that's it, 8&times;8 matrix successfully transposed.

This is nothing I haven't shown you already, although in a different order than before. This form here makes the underlying algorithm much clearer, and also generalizes in the obvious way to larger sizes, should you ever need them. But that's not the reason I'm talking about this. Time to get to the fun part!

### Rotations

Let's look a bit closer at how the elements move during every pass. For this purpose, let's just treat all of the elements as a 64-element array. The first row contains the first 8 elements, the second row contains the second 8 elements, and so forth. `a0` starts out in row zero and column zero, the first element of the array, and stays there for the entire time (boring!). `b3` starts out in row 1, column 3 - that's element number 11 (1&times;8 + 3). Now, the algorithm above simply applies the same permutation to the overall array 3 times. Let's look at how the array elements move in one step---for reasons that will become clear in a second, I'll give the array indices in binary:

From   |        |To
------:|:------:|:------
000 000|&rarr;  |000 000
000 001|&rarr;  |000 010
000 010|&rarr;  |000 100
000 011|&rarr;  |000 110
       |&vellip;|
001 000|&rarr;  |010 000
001 001|&rarr;  |010 010
001 010|&rarr;  |010 100
       |&vellip;|
100 000|&rarr;  |000 001
100 001|&rarr;  |000 011
100 010|&rarr;  |000 101
100 011|&rarr;  |000 111
       |&vellip;|
101 010|&rarr;  |010 101
       |&vellip;|

Since we have 8 rows and 8 columns, the first 3 and last 3 bits in each index correspond to the row and column indices, respectively. Anyway, can you see the pattern? Even-odd interleaving the first half of the array with the second half in effect performs a bitwise rotate left on the element indices!

Among other things, this instantly explains why it takes exactly three passes to transpose a 8&times;8 matrix with this approach: the row and column indices take 3 bits each. So after 3 rotate-lefts, we've swapped the rows and columns---which is exactly what a matrix transpose does. Another salient point is that repeating even-odd interleaves like this will return us to our starting arrangement after 6 passes. This is easy to see once we know that such a step effectively rotates the bits of the element index; it's not at all obvious when looking at the permutation by itself.

But it goes further than that. For one thing, the even/odd interleave construction really works for any even number of elements; it certainly works for all powers of two. So we're not strictly limited to square matrices here. Say we have a 4&times;8 matrix (4 rows, 8 columns). That's 32 elements total, or a 5-bit element index, laid out in binary like `r1r0c2c1c0`, where `r` are row index bits and `c` are column index bits. After two interleave passes, we're at `c2c1c0r1r0`, corresponding to the transposed layout---a 8&times;4 matrix. To go from there to the original layout, we would have to run three more passes, rotating everything by another 3 bits, back to where we started.

Which illustrates another interesting point: for non-square matrices, going in one direction using this method can be much cheaper than going in the other direction. That's because the even/odd interleave step only gives us a "rotate left" operation, and sometimes the shorter path would be to "rotate right" instead. On some architectures the corresponding deinterleave operation is available as well (e.g. ARM NEON), but often it's not, at least not directly.

### Groups

Let's step back for a moment, though. We have an operation: even/odd interleave between the first and second halves of sequences with 2<sup>k</sup> elements, which is really just a particular permutation. And now we know that we can get the inverse operation via repeated interleaving. Which means that our even-odd interleave generates a [group](http://en.wikipedia.org/wiki/Group_\(mathematics\)). Now, as long as we really only do even-odd interleaves on the complete sequence, this group is a [cyclic group](http://en.wikipedia.org/wiki/Cyclic_group) of order k---it has to be: it's a finite group generated by a single element, ergo a cyclic group, and we already know how long the cycle is, based on the "rotate left" property.

So to make matters a bit more interesting, let's get back to the original topic of this article! Namely, the *SIMD* bit. While it's convenient to build a complete matrix transpose out of a single operation on all elements simultaneously, namely a very wide even/odd interleave, that's not how the actual code looks. We have fixed-width registers, and to synthesize anything wider than that, we have to break the data down into smaller chunks and process them individually anyway. However, we do need to have full even/odd interleaves to get a permutation group structure, so we can't allow using single "low" or "high" interleave instructions without their opposite half.

What kind of model do we end up with? Let's list the ingredients. We have:

* A set of n SIMD registers, each k "elements" wide. We'll assume that k is a power of two. What an "element" is depends on context; a 128-bit SIMD registers might be viewed as consisting of 16 byte-sized elements, or 8 16-bit elements, or 4 32-bit elements... you get the idea.
* An even-odd interleave (perfect shuffle) operation between a pair of SIMD registers. For convenience, we'll assume that the results are returned in the same 2 registers. Implementing this might require another temporary register depending on the architecture, but let's ignore that for the purposes of this article; we only care about the state of the registers before and after interleaves, not during them.
* Finally, we assume that registers are completely interchangeable, and that we can "rename" them at will; that is, we'll consider all permutations that can be performed by just renumbering the registers to be equivalent.

To explain the latter, we would consider an arrangement like this:

```
r0 = a0 b0 c0 d0
r1 = a1 b1 c1 d1
```

(where `r0` and `r1` correspond to SIMD registers) to be equivalent to:

```
r0 = a1 b1 c1 d1
r1 = a0 b0 c0 d0
```

or even

```
r3 = a0 b0 c0 d0
r5 = a1 b1 c1 d1
```

To rephrase it, we don't care about differences in "register allocation": as long as we get all the individual rows we need, any order will do.

### What permutations can be generated using interleaves?

This is a question I've been wondering about ever since I first saw the original MMX instructions, but I didn't really spend much time thinking about it until fairly recently, when I got curious. So I don't have a full answer, but I do have some interesting partial results.

Let's get the trivial case out of the way first: if k=1 (that is, each register contains exactly one element), then clearly we can reach any permutation we want, and without doing any work to boot---every register contains one value, and as explained above, our model treats register-level permutations as free. However, as soon as we have multiple elements inside a single register, things start to get interesting.

### Permutations generated for n=2, k=2

We're only permuting n&times;k = 4 elements here, so the groups in question are all small enough to enumerate their elements on a piece of paper, which makes this a good place to start. Also, with n=2, the "register permutation" side of things is really simple (we either swap the two registers or we don't). For the even-odd interleave, we would normally have to specify which two registers to interleave---but since we only have two, we can just agree that we always want to interleave register 0 with register 1. Should we want the opposite order (interleave register 1 with register 0), we can simply swap the two registers beforehand. So our available operations boil down to just two permutations on 4 elements:

* Swap registers 0 and 1---this swaps the first two and the last two elements, so it corresponds to the permutation $$0123 \mapsto 2301$$ or (02)(13) in cycle notation. This is an involution: applying it twice swaps the elements back.
* Even/odd interleave between registers 0 and 1. This boils down to the permutation $$0123 \mapsto 0213$$ or (12) which swaps the two middle elements and is also an involution.

These are the only operations we permit, so we have a finite group that is generated by involutions: it must be a [dihedral group](http://en.wikipedia.org/wiki/Dihedral_group). In fact, it turns out to be [Dih<sub>4</sub>](http://en.wikipedia.org/wiki/Dihedral_group_of_order_8#dihedral_group_of_order_8), the symmetry group of a square, which is of order 8. So using 2 registers, we can reach only 8 of the $$4! = 24$$ permutations of 4 elements. So what happens when we have more registers at our disposal?

### Permutations generated for n>2, k=2

The next smallest case is n=3, k=2, which gives us permutations of 6 elements. $$6! = 720$$, so this is still small enough to simply run a search, and that's what I did. Or, to be more precise, I wrote a [program](https://gist.github.com/rygorous/6378437) that did the searching for me. It turns out that the even-odd interleave of the first two registers combined with arbitrary permutations on the registers (of which there are $$3! = 6$$) is enough to reach all 720 permutations in S<sub>6</sub>, the symmetric group on 6 elements. Beyond this, I can't say much about how this representation of the group works out; it would be nice if there was an easy way to find shortest paths between permutations for example (which would have uses for code generation), but if there is, I don't know how. That said, my understanding of group theory is fairly basic; I'd really appreciate input from someone with more experience dealing with finite groups here.

I can tell you what happens for n>3, though: we already know we can produce *all* permutations using only 3 registers. And using the exact same steps, we can reach any permutation of the first 3 registers for n>3, leaving the other registers untouched. But that's in fact enough to generate an *arbitrary* permutation of n elements, as follows: Say we have n=4, and we start with

```
r0 = e0 e1
r1 = e2 e3
r2 = e4 e5
r3 = e6 e7
```

and we want to end up with the (arbitrarily chosen) permutation

```
r0 = e3 e7
r1 = e0 e5
r2 = e1 e4
r3 = e6 e2
```

To begin, we try to generate the value we want to end up in `r3` (namely, `e6 e2`). First, we swap rows around so that we have the source values we need in rows 0 and 1 (that is, registers `r0` and `r1`). In our example, that just requires swapping `r0` with `r3`:

```
r0 = e6 e7
r1 = e2 e3
r2 = e4 e5
r3 = e0 e1
```

Next, we know that we can reach arbitrary permutations of the first three rows (registers). In particular, we can shuffle things around so that `r0` contains the value we'd like to be in `r3`:

```
r0 = e6 e2
r1 = e7 e3
r2 = e4 e5
r3 = e0 e1
```

This is one way of doing it, but really any permutation that has `e6 e2` in the first row would work. Anyway, now that we have produced the value we wanted, we can swap it back into `r3`:

```
r0 = e0 e1
r1 = e7 e3
r2 = e4 e5
r3 = e6 e2
```

We now have the value we want in `r3`, and all the remaining unused source elements remain in rows 0--2. And again, since we know we can achieve arbitrary permutations of 6 elements using 3 registers using the n=3 case, we're done! For n>4, the proof works in the same way: we first generate rows 3, 4, ..., n-1 one by one; once a row is done, we never touch it again (it can't contain any source elements we need for the remaining rows, since we only allow permutations). In the end we will always arrive at a configuration that has all the remaining "unfinished" elements in rows 0--2, which is a configuration we can solve.

I don't mean to suggest that this is an *efficient* way to solve this problem; quite the opposite, in fact. But it's an easy way to prove that once we have n=3 solved, higher n's don't add any substantial difficulty.

### Summary

This covers the easiest cases, k=1 and k=2, and answers the question I originally wondered about in the positive: using only interleaves, you can produce arbitrary permutations of the input elements in registers, as long as you only have k=2 elements per register (for example, 32-bit values inside the 64-bit MMX registers) and at least 3 SIMD registers worth of storage. Without any nice bounds on the number of operations required or an algorithmic way to compute an optimal interleave/rename sequence, I'm the first one to admit that this has little practical relevance, but it's cool stuff nonetheless! Coming up, I'll talk a bit about the (more interesting) k=4 case, but I think this is enough material for a single blog post. Until next time!
