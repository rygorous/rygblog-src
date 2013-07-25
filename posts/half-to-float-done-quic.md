-title=Half to float done quick
-time=2012-03-29 03:51:20
It all started a few days ago with [this tweet](https://twitter.com/#!/castano/status/182252019418021888) by Ignacio Castaño \- complaining about the speed of the standard library `half_to_float` in [ISPC](http://ispc.github.com/). Tom then [replied](https://twitter.com/#!/tom_forsyth/status/182315716077301762) that this was hard to do well in code without dedicated HW support \- then immediately followed it up with [an idea](https://twitter.com/#!/tom_forsyth/status/182316268681043968) of how you might do it. I love this kind of puzzle \(and obviously follow both Ignacio and Tom\), so I jumped in and offered to write some code. Tom's initial approach was a dead end, but it turned out that it was in fact possible to do a pretty decent job using standard SSE2 instructions \(available anywhere from Pentium 4 onwards\) with no dedicated hardware support at all; that said, dedicated HW support will exist in Intel processors starting from "Ivy Bridge", due later this year. My solutions involve some fun but not immediately obvious bit\-twiddling on floats, so I figured I should take the time to write it up. If you're impatient and just want the code, [knock yourself out](https://gist.github.com/2144712). Actually you might want to open that up anyway; I'll copy over key passages but not all the details. The code was written for x86 machines using Little Endian, but it doesn't use any particularly esoteric features, so it should be easily adapted for BE architectures or different vector instruction sets.

### What's in a float?

If you don't know or care how floating\-point numbers are represented, this is *not* a useful article for you to read, because from here on out it will deal almost exclusively with various storage format details. If you don't know how floats work but would like to learn, a good place to start is Bruce Dawson's [article on the subject](http://altdevblogaday.com/2012/01/05/tricks-with-the-floating-point-format/). If you do know how floats work in principle but don't remember the storage details of IEEE formats, make a quick stop at Wikipedia and read up on the layout of [single-precision](http://en.wikipedia.org/wiki/Single-precision) and [half-precision](http://en.wikipedia.org/wiki/Half-precision_floating-point_format) floats. Still here? Okay, great, let's get started then!

### Half to float basics

Converting between the different float formats correctly is mostly about making sure you catch all the important cases and map them properly. So let's make a list of all the different classes a floating point number can fall into:

* **Normalized numbers** \- the ones where the exponent bits are neither all\-0 nor all\-1. This is the majority of all floats. Single\-precision floats have both a larger exponent range and more mantissa bits than half\-precision floats, so converting normalized halfs is easy: just add a bunch of 0 bits at the end of the mantissa \(a plain left shift on the integer representation\) and adjust the exponent accordingly.
* **Zero** \(exponent and mantissa both 0\) should map to zero \- easy.
* **Denormalized numbers** \(exponent zero, mantissa nonzero\). Values that are denormals in half\-precision map to regular normalized numbers in single precision, so they need to be renormalized during conversion.
* **Infinities** \(exponent all\-ones, mantissa zero\) map to infinities.
* Finally, **NaNs** \(exponent all\-ones, mantissa nonzero\) should map to NaNs. There's often an extra distinction between different types of NaNs, like quiet vs. signaling NaNs. It's nice to preserve these semantics when possible, but in principle anything that maps NaNs to NaNs is acceptable.

Finally there's also the matter of the sign bit. There's two slightly weird cases here \(signed zero and signed NaNs\), but actually as far as conversions go you'll never go wrong if you just preserve the sign bit on conversion, so that's what we'll do. If you just work through these cases one by one, you get something like `half_to_float_full` in the code:

```
static FP32 half_to_float_full(FP16 h)
{
    FP32 o = { 0 };

    // From ISPC ref code
    if (h.Exponent == 0 && h.Mantissa == 0) // (Signed) zero
        o.Sign = h.Sign;
    else
    {
        if (h.Exponent == 0) // Denormal (converts to normalized)
        {
            // Adjust mantissa so it's normalized (and keep
            // track of exponent adjustment)
            int e = -1;
            uint m = h.Mantissa;
            do
            {
                e++;
                m <<= 1;
            } while ((m & 0x400) == 0);

            o.Mantissa = (m & 0x3ff) << 13;
            o.Exponent = 127 - 15 - e;
            o.Sign = h.Sign;
        }
        else if (h.Exponent == 0x1f) // Inf/NaN
        {
            // NOTE: Both can be handled with same code path
            // since we just pass through mantissa bits.
            o.Mantissa = h.Mantissa << 13;
            o.Exponent = 255;
            o.Sign = h.Sign;
        }
        else // Normalized number
        {
            o.Mantissa = h.Mantissa << 13;
            o.Exponent = 127 - 15 + h.Exponent; 
            o.Sign = h.Sign;
        }
    }

    return o;
}
```

Note how this code handles NaNs and infinities with the same code path; despite having a different *interpretation*, the actual work that needs to happen in both cases is exactly the same.

### Dealing with denormals

Clearly, the ugliest part of the whole thing is the handling of denormals. Can't we do any better than that? Turns out we can. After all, the whole point of denormals is that they are *not normalized*; in other words, they're just a scaled integer \(fixed\-point\) representation of a fairly small number. For half\-precision floats, they represent `Mantissa * 2^(-14)`. If you're on one of the architectures with a "convert integer to float" instruction that can scale by an arbitrary power of 2 along the way, you can handle this case with a single instruction. Otherwise, you can either use regular integer→float conversion followed by a multiply to scale the value properly or use a "magic number" based conversion \(if you don't know what that is, check out [Chris Hecker's old GDMag article](http://chrishecker.com/images/f/fb/Gdmfp.pdf) on the subject\). Either way, 0 happens to have all\-0 mantissa bits; in short, same as with NaNs and infinities, we can actually funnel zero and denormals through the same code path. This leaves just three cases to take care of: normal, denormal, or NaN/infinity. `half_to_float_fast2` is an implementation of this approach:

```
static FP32 half_to_float_fast2(FP16 h)
{
    static const FP32 magic = { 126 << 23 };
    FP32 o;

    if (h.Exponent == 0) // Zero / Denormal
    {
        o.u = magic.u + h.Mantissa;
        o.f -= magic.f;
    }
    else
    {
        o.Mantissa = h.Mantissa << 13;
        if (h.Exponent == 0x1f) // Inf/NaN
            o.Exponent = 255;
        else
            o.Exponent = 127 - 15 + h.Exponent;
    }

    o.Sign = h.Sign;
    return o;
}
```

Variants 3, 4 and 4b all use this same underlying idea; they're slightly different implementations, but nothing major \(and the SSE2 versions are fairly straight translations of the corresponding scalar variants\). Variant 5, however, uses a very different approach that reduces the number of distinct cases to handle from three down to two.

### A different method with other applications

Both single\- and half\-precision floats have denormals at the bottom of the exponent range. Other than the exact location of that "bottom", they work exactly the same way. The idea, then, is to translate denormal halfs into denormal floats, and let the floating\-point hardware deal with the rest \(provided it supports denormals efficiently, that is\). Essentially, all we need to do is to shift the input half by the difference in the amount of mantissa bits \(13, as already seen above\). This will map half\-denormals to float\-denormals and normalized halfs to normalized floats. The only problem is that all numbers converted this way will end up too small by a fixed factor that depends on the difference between the exponent biases \(in this case, they need to be scaled up by $$2^{127-15}$$\). That's easily fixed with a single multiply. This reduces the number of fundamentally different cases from three to two: we still need to dedicate some work to handling infinities and NaNs, but that's it. The code looks like this:

```
static FP32 half_to_float_fast5(FP16 h)
{
    static const FP32 magic = { (127 + (127 - 15)) << 23 };
    static const FP32 was_infnan = { (127 + 16) << 23 };
    FP32 o;

    o.u = (h.u & 0x7fff) << 13;     // exponent/mantissa bits
    o.f *= magic.f;                 // exponent adjust
    if (o.f >= was_infnan.f)        // make sure Inf/NaN survive
        o.u |= 255 << 23;
    o.u |= (h.u & 0x8000) << 16;    // sign bit
    return o;
}
```

This is not the fastest way to do the conversion, because it leans on HW to deal with denormals should they arise \(something that floating\-point HW tends to be quite slow at\), but it's definitely the slickest out of this bunch.

More importantly, unlike the other variants mentioned, this basic approach also works in the opposite direction \(converting from floats to halfs\), which in turn inspired [this code](https://gist.github.com/2156668). There's a bit of extra work to ensure there's no unintended double rounding and to handle NaNs and overflows correctly, but it's still the same idea. Which goes to show \- sometimes making things as simple as possible really does have rewards beyond the pure intellectual satisfaction. :\)

And that's it. I admit that play\-by\-play narration of source code isn't particularly exciting, but in this case I thought the code itself was interesting and short enough to give it a shot. And now back to our regularly scheduled posts :\)