-title=DXT5 alpha block index determination
-time=2009-12-15 00:53:48
And another quick coding post; this one came up in an email conversation with [Charles Bloom](http://www.cbloom.com). The question was how to optimally select per\-pixel color indices for DXT5 alpha blocks. DXT5 stores two 8\-bit reference values per block. Depending on whether the first one is larger than the second or not, one out of two possible "color maps" is selected: There's either the two extremal points and 6 interpolated colors between them \(spaced uniformly\), or 0, 255, the two extremal points, and 4 interpolated colors. The problem is how to assign the 3\-bit color map indices for each of the 16 pixels in a DXT block in a way that minimizes error.



Let's start with the first encoding: This seems like a trivial uniform quantization problem, but there's some subtletly with the rounding involved. The solution is not quite what you'd expect. What I ended up with was \(assuming the two endpoint values are "min" and "max", min \< max, and val is the current alpha value to be encoded with min \<= val \<= max\)

```
  int range = max - min;
  int bias = (range < 8) ? (range-1) : (range/2 + 2);
  int index = ((val - min) * 7 + bias) / range;
```

This is *exact* \- it picks the optimal solution for all valid combinations of min, max, and val. This is a "monotonicized" index, by the way, increasing from 0 for min to 7 for max; actual DXT encoding assigns the color map slots differently, so you need to remap the index values before actually generating the bits for the coded DXT5 block. But the simple increasing sequence is way more convenient to work with here.

For the most part this is what one would expect, but the expression to compute the correct rounding bias is somewhat puzzling. I first tried to come up with this algebraically and didn't really get anywhere. So I decided to experiment a bit. The first observation was that the linear interpolation in DXT is symmetric with regards to the two endpoints, so you can assume min\<=max without loss of generality \(actually min \< max, since min=max picks the other encoding with just 4 interpolated values\). Another property is that the index determination has a "translational symmetry" \- if you add \(or subtract\) the same value from min, max and val, the solution doesn't change. This means that the optimum bias can only depend on the difference between max and min. And given our restrictions \(min\<=max, 8 bit values\), we know 0 \<= max\-min \<= 255. Writing a program to determine the optimal biases for all of these is pretty straightforward from there; I then found the bias expression in the source fragment above by just eyeballing the results. Retroactively, it isn't hard to justify \- for range \>= 8, you're "compressing" a larger set of values into a smaller one, while range\<8 has more color map entries than distinct values.

For the second type of blocks \(only 4 interpolated colors, 6 including the endpoints\), the formula for the "interpolated" part is similar, and can be obtained the same way:

```
  int range = max - min;
  int bias = (range < 6) ? (range-1) : (range/2 + 2);
  int index = ((val - min) * 5 + bias) / range;
```

After determining the best "interpolated" index this way, you need to compute the error manually and check whether you can improve it using the special\-case 0 or 255 codes. While somewhat annoying, this is easy. You also need to handle the case where min=max, but this is trivial. Your choices are either 0, 255, or min \- just try them all.

Now if only the DXT color blocks were that easy to pick optimally...