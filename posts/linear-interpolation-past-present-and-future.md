-title=Linear interpolation past, present and future
-time=2012-08-15 17:04:27
Linear interpolation. Lerp. The bread and butter of graphics programming. Well, turns out I have three tricks about lerps to share. One of them is really well known, the other two less so. So let's get cracking!

Standard linear interpolation is just `lerp(t, a, b) = (1-t)*a + t*b`. You should already know this. At t=0 we get a, at t=1 we get b, and for inbetween values of t we interpolate linearly between the two. And of course we can also linearly extrapolate by using a t outside \[0,1\].

### Past

The expression shown above has two multiplies. Now, it used to be the case that multiplies were really slow \(and by the way they really aren't anymore, so please stop doubling the number of adds in an expression to get rid of a multiply, no matter what your CS prof tells you\). If multiplies are expensive, there's a better \(equivalent\) expression you can get with some algebra: `lerp(t, a, b) = a + t*(b-a)`. This is the first of the three tricks, and it's really well known.

But in this setting \(int multiplies are slow\) you're also really unlikely to have floating\-point hardware, or to be working on floating\-point numbers. Especially if we're talking about pixel processing in computer graphics, it used to be all\-integer for a *really* long time. It's more likely to be all fixed\-point, and in the fixed\-point setting you typically have something like `fixedpt_lerp(t, a, b) = a + ((t * (b-a)) >> 8)`. And more importantly, your a's and b's are also fixed\-point \(integer\) numbers, typically with a very low range.

So here comes the second trick: for some applications \(e.g. cross fades\), you're doing a lot of lerps with the same t \(at least one per pixel\). Now note that if t is fixed, the `(t * (b - a)) >> 8` part really only depends on b\-a, and that's a small set of possible values: If a and b are byte values in \[0,255\], then d=b\-a is in \[\-255,255\]. So we really only ever need to do 511 multiplies based on t, to build a table indexed by d. Except that's not true either, because we compute first t\*0 then t\*1 then t\*2 and so forth, so we're really just adding t every time, and we can build the whole table without any multiplies at all. So here we get trick two, for doing lots of lerps with constant t on integer values:

```
U8 lerp_tab[255*2+1]; // U8 is sufficient here

// build the lerp table
for (int i=0, sum = 0; i < 256; i++, sum += t) {
  lerp_tab[255-i] = (U8) (-sum >> 8); // negative half of table
  lerp_tab[255+i] = (U8) ( sum >> 8); // positive half
}

// cross-fade (grayscale image here for simplicity)
for (int i=0; i < npixels; i++) {
  int a = src1[i];
  int b = src2[i];
  out[i] = a + lerp_tab[255 + b-a];
}
```

Look ma, no multiplies!

### Present

But back to the present. Floating\-point hardware is readily available on most platforms and purely counting arithmetic ops is a poor estimator for performance on modern architectures. Practically speaking, for almost all code, you're never going to notice any appreciable difference in speed between the two versions

```
  lerp_1(t, a, b) = (1 - t)*a + t*b
  lerp_2(t, a, b) = a + t*(b-a)
```

but you might notice something else: unlike the real numbers \(which our mathematical definition of lerp is based on\) and the integers \(which our fixed\-point lerps worked on\), floating\-point numbers don't obey the arithmetic identities we've been using to derive this. In particular, for two floating point numbers we generally have `a + (b-a) != b`, so the second lerp expression is generally not correct at t=1! In contrast, with IEEE floating point, the first expression is guaranteed to return the exact value of a \(b\) at t=0 \(t=1\). So there's actually some reason to prefer the first expression in that case, and using the second one tends to produce visible artifacts for some applications \(you can also hardcode your lerp to return b exactly at t=1, but that's just ugly and paying a data\-dependent branch to get rid of one FLOP is a bad idea\). While for pixel values you're unlikely to care, it generally pays to be careful for mesh processing and the like; using the wrong expression can produce cracks in your mesh.

So what to do? Use the first form, which has one more arithmetic operation and does two multiplies, or the second form, which has one less operation but unfavorable rounding properties? Luckily, this dilemma is going away.

### Future

Okay, "future" is stretching a bit here, because for some platforms this "future" started in 1990, but I digress. Anyway, in the future we'd like to have a magic lerp instruction in our processors that solves this problem for us \(and is also fast\). Unfortunately, that seems very unlikely: Even GPUs don't have one, and [Michael Abrash](http://software.intel.com/file/15542) never could get Intel to give him one either. However, he did get fused multiply\-adds, and that's one thing all GPUs have too, and it's either already on the processor you're using or soon coming to it. So if fused multiply\-adds can help, then maybe we're good. And it turns out they can.

A fused multiply\-add is just an operation `fma(a, b, c) = a*b + c` that computes the inner expression using only one exact rounding step. And FMA\-based architectures tend to compute regular adds and multiplies using the same circuitry, so all three operations cost roughly the same \(in terms of latency anyway, not necessarily in terms of power\). And while I say "fma" these chips usually support different versions with sign flips in different places too \(implementing this in the HW is almost free\); the second most important one is "fused negative multiply\-subtract", which does `fnms(a, b, c) = -(a*b - c) = c - a*b`. Let's rewrite our lerp expressions using FMA:

```
  lerp_1(t, a, b) = fma(t, b, (1 - t)*a)
  lerp_2(t, a, b) = fma(t, b-a, a)
```

Both of these still have arithmetic operations left that aren't in FMA form; lerp\_1 has two leftover ops and lerp\_2 has one. And so far both of them aren't significantly better than their original counterparts. However, lerp\_1 has exactly one multiply and one subtract left; they're just subtract\-multiply \(which we don't have HW for\), rather than multiply\-subtract. However, that one is easily remedied with some algebra: `(1 - t)*a = 1*a - t*a = a - t*a`, and that last expression *is* in fma \(more accurately, fnms\) form. So we get a third variant, and our third trick:

```
  lerp_3(t, a, b) = fma(t, b, fnms(t, a, a))
```

Two operations, both FMA\-class ops, and this is based on lerp\_1 so it's actually exact at the end points. Two dependent ops \- as long as we don't actually get a hardware lerp instruction, that's the best we can hope for. So this version is both fast *and* accurate, and as you migrate to platforms with guaranteed FMA support, you should consider rewriting your lerps that way \- it's the lerp of the future!