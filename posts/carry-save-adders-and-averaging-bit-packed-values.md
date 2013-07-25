-title=Carry-save adders and averaging bit-packed values
-time=2010-08-23 10:10:08
Long time no update. Got a few things to write about, but I thought I'd start with a quick post on a simple trick that I've never seen documented in full: An interesting identity for addition of integer values is that `a + b = (a^b) + ((a&b)<<1) = (a^b) + 2*(a&b)`. You can find this on a lot of pages that collect bit\-twiddling tricks. This is basically the reduction formula for a 2\-input Carry\-Save Adder \(Google it if you don't know what that is\). The more interesting 3\-input carry save adder has the reduction formula

```
a + b + c = S + (C << 1) where
S = a ^ b ^ c
C = (a & b) | (a & c) | (b & c)
```

In Hardware, they are very useful as building blocks for integer multipliers: note that there's no \+ in the computation of S and C, and that the three input numbers are "compressed" into two outputs. This makes them very useful to compute all the intermediate sums in a binary multiplier without heaving to deal with carries \- using CSAs, you can reduce any multiple\-term addition into a lot of very simple constant\-delay logic elements with only one fast adder \(the "completion adder"\) placed at the very end. In Software, there is nothing to be gained by this \- basically all current architectures have all basic integer ALU operations running at the same \(fast\) speed. But the reduction formula is still interesting, for another reason: Say you want to compute \(a\+b\)/2 without overflow. Then you can apply the above identity to get `(a+b)/2 = (a^b)/2 + (a&b)` which is guaranteed to be overflow\-free. This trick is also well\-known; it does tend to come in handy every once in a while for SIMD code, since a lot of SIMD instruction sets have a limited set of operand sizes and no output carry bit functionality. Unpacking a 4x32 bit SIMD register to 2 2x64 bit regs just to do a sum is a pain and a big waste of time.

But often you want not \(a\+b\)/2, but \(a\+b\+1\)/2, i.e. with a rounding bias added into the mix. This is one of the reasons for this blog\-post, since I haven't run across a description of this yet. You can use the three\-input CSA reduction for this case. It simplifies down to: `(a+b+1)/2 = (a^b)/2 + ((a&b) | ((a|b)&1))` Not as neat as the variant without rounding bias, but still better than temporary widening if you don't have a SIMD add\-with\-carry instruction.

I've got one more: Let's go back to the first variant again. A nice property of this is that it works well with bit\-packed values, like A8R8G8B8 pixels in a 32\-bit word. All we need to do is to make sure that our division \(shift\) doesn't erroneously spill into adjacent channels. But that's easily remedied with another bit masking operation: 

```
avg_pixel_a8r8g8b8(a,b) = (((a^b) >> 1) & 0x7f7f7f7f) + (a&b)
```

In fact, why limit ourselves to 32\-bit values? It works just as well for two 32\-bit pixels inside a 64\-bit register, just use 0x7f7f7f7f7f7f7f7f as mask. Nor does it say anywhere that the fields all have to have to same size. The trick works just as well for uneven partitions like the 11:11:10 bit format often used to store vertex normals or other unit vectors, or R5G6B5 pixels. All that changes is the bit mask.

Finally, the bitpacked stuff and the rounding bias fix are orthogonal \- you can do both at the same time.

Sure, this isn't *terribly* useful in practice, but it's come in handy for me a couple times over the past few years, and I think it's just fundamentally too *cool* not to have it properly documented.

**UPDATE**: As Charles pointed out in the comments, a better way to compute \(a\+b\+1\)/2 is to use `(a | b) - ((a ^ b) >> 1)` \- just as cheap as the version without rounding bias, and you can do the same masking trick to get rid of carries where you don't want them.