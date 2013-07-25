-title=A small note on the Elias gamma code
-time=2011-01-19 09:36:41
This is a small one, for all compression geeks out there.

The [Elias gamma code](http://en.wikipedia.org/wiki/Elias_gamma_coding) \(closely related to Exponential\-Golomb codes, or Exp\-Golomb codes for short\) is very useful for practical compression applications; it certainly crops up in a lot of modern video coding standards, for example. The mapping goes like this:

```
  1 -> 1
  2 -> 010
  3 -> 011
  4 -> 00100
  5 -> 00101
  6 -> 00110
  7 -> 00111
  8 -> 0001000
```

and so on \(Exp\-Golomb with k=0 is the same, except the first index encoded is 0 not 1, i.e. there's an implicit added 1 during encoding and a subtracted 1 during decoding\).

Anyway, if you want to decode this quickly, and if your bit buffer reads bits from the MSB downwards, shifting after every read so the first unconsumed bit is indeed the MSB \(there's very good reasons for doing it this way; I might blog about this at some point\), then there's a *very* nifty way to decode this quickly:

```
  // at least one of the top 12 bits set?
  // (this means less than 12 heading zeros)
  if (bitbuffer & (~0u << (32 - 12))) {
    // this is the FAST path    
    U32 num_zeros = CountLeadingZeros(bitbuffer);
    return GetBits(num_zeros * 2 + 1);
  } else {
    // coded value is longer than 25 bits, need to
    // use slow path (read however you would read
    // gamma codes regularly)
  }
```

Note that this is one CountLeadingZeros and *one* GetBits operation. The GetBits reads both the zeros and the actual value in one go; it just so happens that the binary value of that is exactly the value we need to decode. Not earth\-shaking, but nice to know. In practice, it means you can read such codes very quickly indeed \(it's just a handful of opcodes on both x86 with `bsr` and PowerPC with `cntlzw` or `cntlzd` if you're using a 64\-bit buffer\).

This is assuming a 32\-bit shift register that contains your unread bits, refilled by reading another byte whenever there's 24 or less unconsumed bits available \(a fairly typical choice\). If you have 64\-bit registers, it's usually better to keep a 64\-bit buffer and refill whenever the available number of bits is 32 or less. In that case you can read gamma codes of up to 33 bits length \(i.e. 16 heading 0 bits\) directly.