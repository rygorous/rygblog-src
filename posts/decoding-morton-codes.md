-title=Decoding Morton Codes
-time=2009-12-13 16:33:19
There's lots of material on the web about computing Morton codes \(also called Morton keys or Morton numbers\) efficiently \- bitwise interleaving of two or more numbers. This may sound esoteric, but it's surprisingly useful in some applications. If you haven't heard of Morton codes yet, step by [Wikipedia](http://en.wikipedia.org/wiki/Z-order_%28curve%29) or look into a book like [Real-Time Collision Detection](http://realtimecollisiondetection.net/books/rtcd/) to learn more about them. Anyway, the subject of this post is not to introduce you to Morton codes, but rather to fill a rather curious gap: As I discovered a few months ago, there's lots of material on the web and in books about how to generate morton codes from 2 or 3 numbers, but I didn't find a single site explaining how to de\-interleave the bits again to get the original numbers back from a morton code! I figured it's time to change that.
<br>

The "classic" algorithms to generate Morton codes look like this:

```
uint32 EncodeMorton2(uint32 x, uint32 y)
{
  return (Part1By1(y) << 1) + Part1By1(x);
}

uint32 EncodeMorton3(uint32 x, uint32 y, uint32 z)
{
  return (Part1By2(z) << 2) + (Part1By2(y) << 1) + Part1By2(x);
}

// "Insert" a 0 bit after each of the 16 low bits of x
uint32 Part1By1(uint32 x)
{
  x &= 0x0000ffff;                  // x = ---- ---- ---- ---- fedc ba98 7654 3210
  x = (x ^ (x <<  8)) & 0x00ff00ff; // x = ---- ---- fedc ba98 ---- ---- 7654 3210
  x = (x ^ (x <<  4)) & 0x0f0f0f0f; // x = ---- fedc ---- ba98 ---- 7654 ---- 3210
  x = (x ^ (x <<  2)) & 0x33333333; // x = --fe --dc --ba --98 --76 --54 --32 --10
  x = (x ^ (x <<  1)) & 0x55555555; // x = -f-e -d-c -b-a -9-8 -7-6 -5-4 -3-2 -1-0
  return x;
}

// "Insert" two 0 bits after each of the 10 low bits of x
uint32 Part1By2(uint32 x)
{
  x &= 0x000003ff;                  // x = ---- ---- ---- ---- ---- --98 7654 3210
  x = (x ^ (x << 16)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
  x = (x ^ (x <<  8)) & 0x0300f00f; // x = ---- --98 ---- ---- 7654 ---- ---- 3210
  x = (x ^ (x <<  4)) & 0x030c30c3; // x = ---- --98 ---- 76-- --54 ---- 32-- --10
  x = (x ^ (x <<  2)) & 0x09249249; // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
  return x;
}
```

The meat is in the Part1By1 and Part1By2 functions, which separate the bits from each other. Reversing this function is actually very easy \- it mainly boils down to executing the function in reverse, turning left shifts into right shifts and moving the masks aroundd a bit. All of this is pretty easy to work out by taking one single step and figuring out how to reverse it. So, without further ado, here's the inverses of Part1By1 and Part1By2:

```
// Inverse of Part1By1 - "delete" all odd-indexed bits
uint32 Compact1By1(uint32 x)
{
  x &= 0x55555555;                  // x = -f-e -d-c -b-a -9-8 -7-6 -5-4 -3-2 -1-0
  x = (x ^ (x >>  1)) & 0x33333333; // x = --fe --dc --ba --98 --76 --54 --32 --10
  x = (x ^ (x >>  2)) & 0x0f0f0f0f; // x = ---- fedc ---- ba98 ---- 7654 ---- 3210
  x = (x ^ (x >>  4)) & 0x00ff00ff; // x = ---- ---- fedc ba98 ---- ---- 7654 3210
  x = (x ^ (x >>  8)) & 0x0000ffff; // x = ---- ---- ---- ---- fedc ba98 7654 3210
  return x;
}

// Inverse of Part1By2 - "delete" all bits not at positions divisible by 3
uint32 Compact1By2(uint32 x)
{
  x &= 0x09249249;                  // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
  x = (x ^ (x >>  2)) & 0x030c30c3; // x = ---- --98 ---- 76-- --54 ---- 32-- --10
  x = (x ^ (x >>  4)) & 0x0300f00f; // x = ---- --98 ---- ---- 7654 ---- ---- 3210
  x = (x ^ (x >>  8)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
  x = (x ^ (x >> 16)) & 0x000003ff; // x = ---- ---- ---- ---- ---- --98 7654 3210
  return x;
}
```

Using these, getting the original x, y and z coordinates from Morton codes is then trivial:

```
uint32 DecodeMorton2X(uint32 code)
{
  return Compact1By1(code >> 0);
}

uint32 DecodeMorton2Y(uint32 code)
{
  return Compact1By1(code >> 1);
}

uint32 DecodeMorton3X(uint32 code)
{
  return Compact1By2(code >> 0);
}

uint32 DecodeMorton3Y(uint32 code)
{
  return Compact1By2(code >> 1);
}

uint32 DecodeMorton3Z(uint32 code)
{
  return Compact1By2(code >> 2);
}
```

There you go, hope it comes in handy.