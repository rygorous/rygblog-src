-title=How to generate cellular textures 2
-time=2010-03-29 18:42:58
After writing the previous article, I experimented with the problem a bit more and found out two things. First, there's a bug in the distance lower bound computation I used for the "tiles" variant that caused it to perform significantly worse than it should. I actually copied it over from the Werkkzeug3 implementation, which has the same bug \- shouldn't have assumed it's correct just because it's worked for a couple of years. \(The bug causes the lower bound to be much larger than necessary in some cases; i.e. it never causes any visual changes, it just makes the algorithm run slower\). The fixed version of distanceBound is a lot simpler than the original implementation. The second thing I found out is that there's another big speedup to be had without using point location structures, higher\-order Voronoi diagrams or an "all nearest neighbor" algorithm. All it takes is a bit of thinking about the problem.



The "tiled" algorithm is already quite good at reducing the number of iterations in the inner loop; for example, when rendering a 1024x1024 image with 256 randomly placed cells in 32x32 pixel tiles, around 3.5 distance calculations are performed per pixel on average. Considering that *any* algorithm that solves the problem needs to calculate at least 2 distances per pixel \(to the nearest and second\-nearest cell center for coloring\), and that reducing the number of distance computations from 256/pixel to 3.5/pixel "only" gave us a speedup factor of about 28, there's not that much to be gained from reducing the distance computations further. We're gonna hit diminishing returns there.

However, we did achieve our speedup by shifting a lot of work to the outer loop, which now has quite a lot to do \- traverse all tiles in the image, compute a distance lower bound to each cell center per\-tile, then sort the list of cell centers by distance. Considering that most cell centers only "contribute" to a small number of tiles, this seems wasteful. Wouldn't it be great if we could avoid dealing with distant cell centers altogether?

And that's exactly the main idea for this improvement: get rid of unnecessary points early. But how do we determine which points to reject? Assume you're rendering some subrectangle R of the current image, and that R contains at least one cell center C. Either this cell center is already the closest to every pixel P inside R, or there is some pixel P for which another cell center D outside of R is closer to P. In short, $$dist(P,D) \le dist(P,C) \le diam(R)$$ because both P and C are in R. This means that all points that *might* be the nearest point to some pixel in R must be within a distance of $$diam(R)$$ from R. The same argument works for the closest 2 points if at least 2 points are contained in R, and it can also be done in 1D for the x and y axis separately. The net result is that if R contains at least 2 points, all points that are candidates for "closest or second\-closest to some pixel in R" must be contained in a rectangle R' that is centered on R and has three times the diameter in both dimensions. That's the trick.

Now all we need to do is make use of this. What I did was to subdivide the output image is subdivided recursively in a quadtree\-like fashion. To render the pixels inside the subrectangle R, subdivide R into four rectangles, which are processed sequentially \(note this is completely implicit; no tree is actually built and no data structures are queried\). Say the current such rectangle is S. We then compute S' and divide points into two categories: within S' and outside S'. If there's some points inside S' and at least two of these points inside S \(without the apostrophe!\), the process is repeated starting with the smaller rectangle S. If we can't subdivide any further or if the subrectangles get too small, actually render the current rectangle, using any of the methods described in the previous article on the reduced point set.

So, how much does it help? Time for some hard data. Same setup as before, my notebook \(2.2GHz Core2Duo\), 1024x1024 pixel, randomly placed points with minimum distance enforced. I've also changed the measuring code to retry everything 3 times and take the fastest run; it didn't much matter with the huge differences between algorithms last time, but this time I wanted to do it a bit more properly. \(I still always use the same point distribution, though\)

```
64 points.
         brute force:    710142 microseconds
                tree:   1745306 microseconds
           sort by y:    149844 microseconds
      sort by y, SSE:     54521 microseconds
               tiles:     99334 microseconds
          tiles, SSE:     22741 microseconds
        spatial subd:     21571 microseconds

128 points.
         brute force:   1534623 microseconds
                tree:   2191476 microseconds
           sort by y:    195516 microseconds
      sort by y, SSE:     74734 microseconds
               tiles:    109785 microseconds
          tiles, SSE:     29030 microseconds
        spatial subd:     23927 microseconds

256 points.
         brute force:   3206320 microseconds
                tree:   2777783 microseconds
           sort by y:    250306 microseconds
      sort by y, SSE:    104342 microseconds
               tiles:    123634 microseconds
          tiles, SSE:     39941 microseconds
        spatial subd:     28874 microseconds

512 points.
         brute force:   7312217 microseconds
                tree:   4044699 microseconds
           sort by y:    357257 microseconds
      sort by y, SSE:    144823 microseconds
               tiles:    160355 microseconds
          tiles, SSE:     66846 microseconds
        spatial subd:     34001 microseconds

1024 points.
         brute force:  15794828 microseconds
                tree:   5683397 microseconds
           sort by y:    490350 microseconds
      sort by y, SSE:    215715 microseconds
               tiles:    254225 microseconds
          tiles, SSE:    151504 microseconds
        spatial subd:     40939 microseconds
```

Results are overall similar to last time for the first few methods. The tile\-based algorithm has improved dramatically thanks to the distanceBound\-bugfix. The other thing is that the new spatial subdivision algorithm really kills everything else across the whole range. This didn't surprise me much with large numbers of points \(after all, this is where rejecting points outright really helps\), but I didn't expect the algorithm to deal gracefully with a small number of points, due to the increased overhead. Turns out that's not a problem \- the new algorithm still is reliably a win for as little as 16 points, and only minimally smaller \(less than 1%\) for less than that.

So, what about implementation complexity? Here's the number of lines of code \(including blank lines and comments\) for the different algorithms. "sort Y", "tiles" and "spatial subd" use the KeyedPoint functions \(24 lines\), and "spatial subd" also uses most of the tile\-based rendering code \(61 lines\). The result is:

```
brute force:               31 lines
sort y:            42+24 = 66 lines
tiles:             70+24 = 94 lines
tree:                     185 lines
spatial subd:  53+61+24 = 138 lines
```

You can download the new code [here](http://www.farbrausch.de/~fg/code/cellular_new.cpp). And my original point still stands: keep it simple, stupid! Look at the problem you're trying to solve. And don't just use trees for everything :\)

**UPDATE:** This one had a bug as well. Stupid error in the "spatial subd" variant, introduced while cleaning up the code. Found and fixed :\)