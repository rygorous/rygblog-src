-parent=debris-opening-the-box
-title=Fast blurs 1
-time=2012-07-30 07:44:08

A bit of context first. As I explained [before](*genthree-overview), the texture generators in RG2 / GenThree / Werkkzeug3 / Werkkzeug4 all use 16 bits of storage per color channel, with the actual values using only 15 bits \(to work around some issues with the original MMX instruction set\). Generated textures tend to go through lots of intermediate stages, and experience with some older texture generation experiments taught me that rounding down to 8 bits after every step comes at a noticeable cost in both quality and user convenience.

All those texture generators are written to use the CPU. For Werkkzeug4, this is simple because it's using a very slightly modified version of the Werkkzeug3 texture generator; the others were written in the early 2000s, when Pixel Shaders were either not present or very limited, GPU arithmetic wasn't standardized, video memory management and graphics drivers were crappy, there was no support for render target formats with more than 8 bits per pixel, and cards were on AGP instead of PCI Express so read\-backs were seriously slow.

Because we were targeting CPU, we used algorithms that were appropriate for CPU execution, and one of the more CPU\-centric ones was the blur we used \- an improved version of "Blur v2" in RG2, which I wrote around 2001\-2002 \(not sure when exactly\). This algorithm really doesn't map well to the regular graphics pipeline, and for a long time I thought it was going to join the ranks of now\-obsolete software rendering tricks. However, we now have Compute Shaders, and guess what \- they're actually a good fit for this algorithm! Which just goes to show that it's worthwhile to know these tricks even when they're not immediately useful right now.

Anyway, enough introduction. Time to talk blurs.

### 2D convolution

As usual, I'll just describe the basics very briefly \(there's plenty of places on the web where you can get more details if you're confused\) so I can get to the interesting bits. Blurs are, in essence, 2D convolution filters, so each pixel of the output image is a linear combination \(weighted sum\) of the corresponding pixel in the input image and some of its neighbors. The set of weights \(corresponding to the adjacent pixels\) is called the "convolution kernel" or "filter kernel". A typical example kernel would be 

$$\frac{1}{16} \begin{bmatrix} 1 & 2 & 1 \\ 2 & 4 & 2 \\ 1 & 2 & 1 \end{bmatrix}$$

which happens to correspond to a simple blur filter \(throughout this post, I'll use filters with odd dimensions, with the center of the kernel aligned with the output pixel\). Different types of blur correspond to different kernels. There's also non\-linear filters that can't be described this way, but I'll ignore those here. To apply such a filter, you simple sum the contributions of all adjacent input pixels, weighted by the corresponding value in the filter kernel, for each output pixel. This is nice, simple, and the amount of work per pixel directly depends on the size of the filter kernel: a 3x3 filter needs to sum 9 samples, a 5x5 filter 25 samples, and so forth. So the amount of work is roughly proportional to the blur radius \(which determines the filter kernel size\), squared.

For 3x3 pixels this is not a big deal. For 5x5 pixels it's already borderline, and it's very rare to see larger kernels implemented as direct 2D convolution filters.

### Separable filters

Luckily, the filters we actually care about for blurs are *separable*: the 2D filter can be written as the sequential application of two 1D filters, one in the horizontal direction and one in the vertical direction. So instead of convolving the whole image with a 2D kernel, we effectively do two passes: first we blur all individual rows horizontally, then we blur all individual columns vertically. The kernel given above is separable, and can be factored into the product of two 1D kernels:

$$\frac{1}{16} \begin{bmatrix} 1 & 2 & 1 \\ 2 & 4 & 2 \\ 1 & 2 & 1 \end{bmatrix} = \left(\frac{1}{4} \begin{bmatrix} 1 \\ 2 \\ 1 \end{bmatrix}\right) \otimes \left(\frac{1}{4} \begin{bmatrix} 1 & 2 & 1 \end{bmatrix}\right)$$.

To apply this kernel, we first filter all pixels in the horizontal direction, then filter the result in the vertical direction. Both these passes sum 3 samples per pixel, so to apply our 3x3 kernel we need 6 samples total \(in two passes\) \- a 33% reduction in number of samples taken, and so potentially up to 33% faster \(with some major caveats; I'll pass on this for a minute, but we'll get there eventually\). A 5x5 kernel takes 10 samples instead of 25 \(60% reduction\), a 7x7 kernel 14 instead of 49 \(71% reduction\), you get the idea.

Also, nobody forces us to use the same kernel in both directions. We can have different kernels of different sizes if we want to; for example, we might want to have a stronger blur in the horizontal direction than in the vertical, or even use different filter types. If the width of the horizontal kernel is p, and the height of the vertical kernel is q, the two\-pass approach takes p\+q samples per pixel, vs. p×q for a full 2D convolution. A linear amount of work per pixel is quite a drastic improvement from the quadratic amount we had before, and while large\-radius blurs may still not be fast, at least they'll complete within a reasonable amount of time.

So far, this is all bog\-standard. The interesting question is, can we do less than a linear amount of work per pixel and still get the right results? And if so, how much less? Logarithmic time? Maybe even constant time? Surprisingly, we can actually get down to \(almost\) constant time if we restrict our selection of filters, but let's look at a more general approach first.

### Logarithmic time per pixel: convolution and the discrete\-time Fourier transform

But even for general kernels \(separable or not\), it turns out we can do better than linear time per pixel, if we're willing to do a bit more setup work. The key here is the [convolution theorem](http://en.wikipedia.org/wiki/Convolution_theorem): convolution is equivalent to pointwise multiplication in the frequency domain. In 1D, we can compute convolutions by transforming the row/column in question to the frequency domain using the Fast Fourier Transform \(in the general case, we need to add padding around the image to get the boundary conditions right\), multiplying point\-wise with the FFT of the filter kernel, and then doing an inverse FFT. The forward/inverse FFTs have a cost of $$O(n \log n)$$ \(where n is either the width or height of the image\), and the pointwise multiplication is linear, so our total cost for transforming a full row/column with a separable filter is also $$O(n \log n)$$, a logarithmic amount of work per pixel. And of course, we only compute the FFT of the filter kernel once. Note that the size of our FFT depends on both the size of the image and the size of the convolution kernel, so we didn't lose the dependency on filter kernel size completely, even though it may seem that way.

The same approach also works for non\-separable filters, using a 2D FFT. The FFT as a linear transform *is* separable, so computing the FFT of a 2D image with N×N pixels is still a logarithmic amount of work per pixel. This time, we need the 2D FFT of the filter kernel to multiply with, but the actual convolution in frequency space is again just pointwise multiplication.

While all of this is nice, general and very elegant, it all gets a bit awkward once you try to implement it; the FFT has higher dynamic range than its inputs \(so if you compute the FFT of an 8\-bit/channel image, 8 bits per pixel aren't going to be enough\), and the FFT of real signals is complex\-valued \(albeit with some symmetry properties\). The padding also means that you end up enlarging the image considerably before you do the actual convolution, and combined with the higher dynamic range it means we need a lot of temporary space. So yes, you can implement filters this way, and for large radii it will win over the direct separable implementation, but at the same time it tends to be significantly slower \(and certainly more cumbersome\) for smaller kernels \(which are important in practice\), so it's not an easy choice to make.

### Thinking inside the box

Instead, let's try something different. Instead of starting with a general filter kernel and trying to figure out how to apply it efficiently, let's look for filters that are cheap to apply even without doing any FFTs. A very simple blur filter is the box filter: just take N sequential samples and average them together with equal weights. It's called a box filter because that's what a plot of the impulse response looks like. So for example a 5\-tap 1D box filter would compute

$$y(n) = (x(n-2) + x(n-1) + x(n) + x(n+1) + x(n+2)) / 5$$.

Now, because all samples are weighted equally, it's very easy to compute the value at location n\+1 from the value at location n \- the filter just computes a [moving average](http://en.wikipedia.org/wiki/Moving_average):

$$y(n+1) = (x(n-1) + x(n) + x(n+1) + x(n+2) + x(n+3)) / 5$$
<br>$$y(n+1) - y(n) = (x(n+3) - x(n-2)) / 5$$

The middle part of the sum stays the same, it's just one sample coming in at one end and another dropping off at the opposite end. So once we have the value at one location, we can sweep through pixels sequentially and update the sum with two samples per pixel, *independent of how wide the filter is*. We compute the full box filter once for the first pixel, then just keep updating it. Here's some pseudo\-code:

```
  // Compute box-filtered version of x with a (2*r+1)-tap filter,
  // ignoring boundary conditions.
  float scale = 1.0f / (2*r + 1); // or use fixed point

  // Compute sum at first pixel. Remember this is an odd-sized
  // box filter kernel.
  int sum = x[0];
  for (int i=0; i < r; i++)
    sum += x[-i] + x[i];

  // Generate output pixel, then update running sum for next pixel.
  for (int i=0; i < n; i++) {
    y[i] = sum * scale;
    sum += x[i+r+1] - x[i-r];
  }
```

In practice, you need to be careful near the borders of the image and define proper boundary conditions. The natural options are pretty much the boundary rules supported by texture samplers: define a border color for pixels outside the image region, clamp to the edge, wrap around \(periodic extension\), mirror \(symmetric extension\) and so forth. Some people also just decrease the size of the blur near the edge, but that is trickier to implement and tends to produce strange\-looking results; I'd advise against it. Also, in practice you'll support multiple color channels, but the whole thing is linear and we treat all color channels equally, so this doesn't add any complications.

This is all very nice and simple. It's also fast \- if we have a n\-pixel image and a m\-tap box filter, using this trick drops us from n×m samples down to m \+ 2n samples for a full column or now, and hence down from m samples per pixel to \(m/n \+ 2\) samples per pixel. Now the m/n term is generally less than 1, because it makes little sense to blur an image with a kernel wider than the image itself is, so this is for all practical purposes bounded by a constant amount of samples per pixel \(less than 3\).

There's two problems, though: First, while box filters are cheap to compute, they make for fairly crappy blur filters. We'd really like to use better kernels, preferably Gaussian kernels \(or something very similar\). Second, the implementation as given only supports odd\-sized blur kernels, so we can only increase the filter size in increments of 2 pixels at a time. That's extremely coarse. We could try to support even\-sized kernels too \(it works exactly the same way\), but even\-sized kernels shift phase by half a pixel, and pixel granularity is still very coarse; what we really want is sub\-pixel resolution, and this turns out to be reasonably easy to do.

That said, this post is already fairly long and I'm not even halfway through the material I want to cover, so I guess this is going to be another multi\-parter. So we'll pick up right here in part two.

### Bonus: Summed area tables

I got one more though: [summed area tables](http://en.wikipedia.org/wiki/Summed_area_table), also known as "integral images" in the Computer Vision community. Wikipedia describes the 2D version, but I'll give you the 1D variant for comparison with the moving average approach. What you do is simply calculate the cumulative sums of all pixels in a row \(column\):

$$S(n) := \sum_{k=0}^{n} x(k)$$
<br>so
<br>$$S(0) = x(0)$$,
<br>$$S(1) = x(0) + x(1)$$,
<br>...
<br>$$S(n-1) = x(0) + x(1) + x(2) + \cdots + x(n-1)$$.

Now, the fundamental operation in box filtering was simply computing the sum across a continuous span of pixels, let's write this as
<br>$$X(i:j) := \sum_{k=i}^{j} x(k)$$
<br>which given S reduces to
<br>$$X(i:j) = S(j) - S(i-1)$$

In other words, once we know the cumulative sums for a given row \(which take n operations to compute\), we can again compute arbitrary\-width box filters using two samples per pixel. However, the cumulative sums usually perform more setup work per row/column than the moving average approach described above, and boundary conditions other than a constant color border are trickier to implement. They do have one big advantage though: once you have the cumulative sums, it's really easy to use a different blur radius per pixel. Neither moving averages nor the FFT approach can do this, and it's a pretty neat feature.

I've described the 1D version; the Wikipedia link describes actual summed area tables which are the 2D version, and the same approach also generalizes to higher dimensions. They all allow applying a N\-dimensional box filter using a constant number of samples, and they all take linear time \(in the number of elements in the dataset\) to set up. As said, I won't be using them here, but they're definitely worth knowing about.
