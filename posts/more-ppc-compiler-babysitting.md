-title=More PPC compiler babysitting
-time=2010-11-07 01:18:12
Another recent discovery from looking at generated code. On inorder PPC processors, you can't move data directly between the integer and floating point units \- it has to go through memory first. This usually involves storing some value to memory and reading it immediately afterwards, a guaranteed LHS \(Load\-Hit\-Store\) stall. A full integer to floating point conversion on PPC involves multiple steps:

1. Sign\-extend the integer to 64 bits \(`extsw`\)
2. Store 64\-bit value into memory \(`std`\)
3. Load 64\-bit into into floating\-point register \(`lfd`\)
4. Convert to double \(`fcfid`\)
5. Round to single precision \(`frsp`\)

The sign\-extend and round to single steps may be omitted depending on context, but the rest is pretty much fixed, and the dreaded LHS is triggered by step 3. There's ways to work around this problem \- if you have a small set of integers, it can make sense to use a small table for int\-\>float conversion. You can also use SIMD instructions to do the conversion, provided you do the rest of your computation in SIMD registers too \(again, no direct movement between the integer, vector and floating point units, you have to go through memory\).

That's not what this post is about, though. Let's just accept that LHS as a fact of life for now. Does that mean we have to eat it on every int to float \(or float to int\) conversion? Not really. Have a look at this code:

```
void some_function(float a, float b, float c, float d);

void problem(int a, int b, int c, int d, float scale)
{
  some_function(a*scale, b*scale, c*scale, d*scale);
}
```

We need to perform four int\-to\-float conversion for this function call. They're completely independent, so the compiler could just do steps 1 and 2 for all four values, then steps 3\-5. Unless we're unlucky, we expect all four temporaries to be in the same cache line on the stack, so we expect to get only one LHS stall on the first load. So much for the theory, anyway \- I recently noticed that one of the PPC compilers didn't do this, so I whipped up the small example above and checked the other compilers we use, and it turns out that all three of them happily produced code with 4 LHS stalls.

When the swelling from the subsequent Mother Of All Facepalms\(tm\) abated, I went on to check if there was some way to coax the compilers into generating better code. And yes, on all 3 compilers there's a way to get the desired behavior, though the details differ a bit:

```
 // Names changed to protect the guilty
#ifndef COMPILER_C
typedef volatile S64 S32itof;
#else 
typedef S64 S32itof;
#endif

static inline F32 fast_itof(S32itof x)
{
#ifdef COMPILER_A
  return x;
#else
  return (F32) __fcfid(x);
#endif
}

void better(int a, int b, int c, int d, float scale)
{
  S32itof fa = a, fb = b, fc = c, fd = d;
  some_function(fast_itof(fa)*scale, fast_itof(fb)*scale,
    fast_itof(fc)*scale, fast_itof(d)*scale);
}
```

My original implementation uses a macro for `fast_itof` since it needs to work in plain C89 code, and the temporary values of type `S32itof` aren't optional in that case. With the inline function, you might be able to get rid of them, but I haven't checked this.