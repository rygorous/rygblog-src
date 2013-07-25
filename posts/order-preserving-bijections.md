-title=Order-preserving bijections
-time=2013-01-22 04:56:13
Sometimes it's useful to convert numbers to a different representation in a way that's order\-preserving. This is useful because some applications have a clear preference for one type of number over another \- for example, [Radix sort](http://en.wikipedia.org/wiki/Radix_sort) and the closely related [Radix trees](http://en.wikipedia.org/wiki/Radix_tree) are most naturally expressed in terms of unsigned integers, and it's generally easier to transform the keys so they sort correctly as unsigned ints than it is to adapt the algorithm to deal with signed numbers \(or floats\).

Another case of interest is SIMD instructions on x86. For example, there's signed integer greater\-than comparison instructions `PCMPGTB`, `PCMPGTW` and `PCMPGTD` starting with the Pentium MMX \(or SSE2 for 128\-bit variants\), but no unsigned equivalents. There's also signed word integer min/max `PMINSW` and `PMAXSW` starting from SSE \(SSE2 for 128\-bit\), but for some reason the corresponding unsigned equivalents `PMINUW` and `PMAXUW` weren't added until SSE4.1.

So, without further ado, here's my transforms of choice \(assuming two's complement arithmetic\):

### Signed int32 \<\-\> unsigned int32

* `x ^= 0x80000000;`
* or: `x += 0x80000000;`
* or: `x -= 0x80000000;`

All three do the same thing and are involutions \(i.e. they are their own inverse\).

Mnemonic: To convert signed integers to unsigned integers, add 0x80000000 so the smallest signed integer \(\-0x80000000\) turns into the smallest unsigned integer \(0\). The same works in reverse of course. 

The MSB doesn't carry into anything, so addition and exclusive or do the same thing. Note that 0x80000000 isn't a representable integer in 32\-bit two's complement arithmetic, but \-0x80000000 is, so technically the correct expressions are `x -= -0x80000000` instead of `x += 0x80000000` \(and similar for subtraction\), but you get the idea. This generalizes to integers with other sizes in the obvious way.

### IEEE float \<\-\> signed int32

Float to int32:

```
int32 temp   = float2bits(f32_val);
int32 i32val = temp ^ ((temp >> 31) & 0x7fffffff);
```

int32 to float:

```
int32 temp   = i32val ^ ((i32val >> 31) & 0x7fffffff);
float f32val = bits2float(temp);
```

Aside from the "bit casting" \(turn an IEEE754 float number into its integer bits and back\) this transform is an involution too. It uses bit shifts on signed two's complement numbers which is technically undefined in C, but in practice all compilers I've ever used just turn it into the arithmetic right shifts you'd expect.

Positive floats have the MSB \(integer sign bit\) clear and larger floating\-point values have larger integer representations. This includes the IEEE infinity value, which is larger than all finite floats. Negative floats have the MSB \(integer sign bit\) set, but they are represented as sign \+ magnitude, so 0x800000 actually represents the *largest* "negative" float \(actually, it's \-0\), whereas smaller \(more negative\) floats have larger representations when compared as integers. This expression leaves positive floats alone but flips all but the sign bit for negative floats, so they order correctly.

**Caveat 1**: Under this transform, \-0 \< 0, whereas "true" IEEE comparisons treat them as the same.
<br>**Caveat 2**: There's NaNs \(not a number\) both with and without the sign bit set. Under this transform, the "smallest" and "largest" values can both represent NaN bit patterns, and NaNs are ordered relative to each other. This is well\-defined and reasonable, but doesn't match the behavior or regular floating\-point compares.

### IEEE float \<\-\> unsigned int32

Float to uint32:

```
uint32 temp   = float2bits(f32_val);
uint32 i32val = temp ^ (((int32)temp >> 31) | 0x80000000);
```

uint32 to float:

```
int32  temp1  = u32val ^ 0x80000000;
int32  temp2  = temp1 ^ (temp1 >> 31);
float  f32val = bits2float(temp2);
```

This is really just a combination of the previous two: instead of making sure we don't change the sign bit, we make sure to always flip it in the forward transform. Because we flip the sign, the reverse transform needs to flip it back before it does the arithmetic shift, so this is *not* an involution unlike the other two. The same caveats apply as for the int32 version.