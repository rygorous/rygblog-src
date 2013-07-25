-parent=debris-opening-the-box
-title=How to generate cellular textures
-time=2010-03-28 01:19:58
Cellular textures are a really useful primitive to have in a texture generator. Jim Scott alias blackpawn wrote a great introduction to the subject several years ago \- [it's available here](http://blackpawn.com/texts/cellular/default.html). If you don't know what cellular textures are, start there; I'm gonna get right into the juicy bits. Jims article does a great job of putting you onto the right track, but I have two complaints about it. The first one is minor: there's another method to combine the two distances that's quite useful to have, namely \(dist2 \- dist1\) / \(dist2 \+ dist1\) or equivalently 1 \- \(2 dist1\) / \(dist1 \+ dist2\), where dist1 and dist2 are the distances to the closest and second\-closest points, respectively. This is like "dist2 \- dist1", but the distances are "normalized", i.e. there are no huge brightness variations between the cells. Very handy \(the result is shown below\). The second complaint is more serious: I strongly disagree with his recommendation of using trees to accelerate the distance calculations, because there's a much simpler method that improves performance far more. But let's start at the beginning.

![Cellular texture generated with the (dist2 - dist1) / (dist2 + dist1) formula](http://www.farbrausch.de/~fg/blog/cellular.png)



The first thing to take care of is to clearly define our problem. In this case, we'd like to determine, for each pixel in the image, the distance to the closest two points in a given set. \(Even though several of the shading formulas work with just the distance to the closest point, we'd really like to have both if possible\). To solve this problem, we need to determine which points are the two closest neighbors to any given pixel; we can easily calculate the distances from there. The geometric structure that answers this problem is the so\-called *2nd\-order Voronoi diagram*, which is closely related to the "normal" \(1st\-order\) Voronoi diagram you might already know. The 2nd\-order Voronoi diagram solves our problem neatly: it gives us a polygonal description of each cell, all we have to do is fill the polygons and calculate the distances. It's also, however, rather complicated to compute, with lots of fairly tricky code.

Blackpawns solution is to use a point location structure. He gives one flavor of tree as an example, but as he mentions, you could use others as well. His description only deals with finding the closest point, but it's fairly straightforward to determine the closest two points \- you just need to keep track of two distances, always using the larger distance during rejection testing. This works, but it's still quite a lot more code than the brute force variant of just testing against every point, and it doesn't make *any* use of the rather special nature of our problem: we're querying all points on a regular grid. There's obviously a huge amount of redundant \(or at least very similar\) work done every pixel. Pre\-seeding the search distance as Blackpawn mentions doesn't solve this \- we still need to walk down the tree from the root to the nearest point every single time, even when we've "guessed" the closest point correctly. Can't we do any better than this?

Of course we can, but let's start with some code fragments for the brute force implementation:

```
static inline float wrapDist(float a, float b)
{
  float d = fabs(b - a);
  return min(d, 1.0f-d);
}

static inline float wrapDistSq(const Point &a, const Point &b)
{
  return square(wrapDist(a.x, b.x)) + square(wrapDist(a.y, b.y));
}

static void cellularTexBruteForce(Image &out, const Point pts[], int count)
{
  for(int y=0; y<out.SizeY; y++)
  {
    Intens *dest = out.Row(y);
    Point cur(0.0f, float(y) / out.SizeY);

    for(int x=0; x<out.SizeX; x++)
    {
      cur.x = float(x) / out.SizeX;

      // determine distance to closest 2 points via brute force
      float best = 1.0f, best2 = 1.0f;
      for(int i=0; i<count; i++)
      {
        float d = wrapDistSq(cur, pts[i]);
        if(d < best2)
        {
          if(d < best)
            best2 = best, best = d;
          else
            best2 = d;
        }
      }

      // color the pixel accordingly
      dest[x] = cellIntensity(sqrtf(best), sqrtf(best2));
    }
  }
}
```

The first approach I came up with when optimizing the Werkkzeug3 texture generator \(several years ago\) works by combining a straightforward low\-level optimization with a simple rejection test. First, the straightforward low\-level optimization: if you look at the distance computation, you'll notice that the y part of the distance \(based on point\[i\].y \- y\) is computed for every destination pixel and each of the cell centers, even though it's always the same for each cell center over the course of a scanline! Instead, we can compute this just once per cell center, for every scanline. But then, we can just sort the points by this precomputed distance: if they're sorted and the current second\-best distance is lower than the y\-distance for the current point, we can stop looking at other points, since none of them can "beat" the existing points anymore. A simple insertion sort is sufficient to keep the point list sorted, since it will be very nearly sorted from the previous scanline. This yields a very simple algorithm that performs *dramatically* better than the brute\-force variant, while adding only about 20 lines of code \(compare this to a tree implementation!\). Another nice aspect about this solution is that it's trivial to parallelize \- you can easily test 4 \(or more\) pixels at once, only stopping when you're certain you've found the nearest neighbors for all of them. Doing the same for a tree\-based implementation is more involved, since the traversal paths can diverge; handling this correctly adds a bunch of management overhead.

This works fine, and served the Werkkzeug3 well for 2 years or so, until I noticed that we had a lot of fairly large textures with a fairly small number of cells. This, together with a dataset where the cellular texture generation was one of the main performance hotspots, led to me look at the code again. The algorithm described above is fundamentally asymmetric \- the y\-axis can be used for rejection testing, but the x\-axis can't. The asymmetry isn't much of a problem as long as you're dealing with square images and plain Euclidean distance, but Werkkzeug3 also allows the x and y distances to be weighted differently, and the previous algorithm becomes equivalent to the brute\-force solution as you assign larger weight to x distances \- not good. So I wondered whether it wouldn't be possible to make better use of the 2D structure of the problem.

What I came up with was processing the image by dealing with small, square tiles. Per tile, all cell centers are considered, and a lower bound of the distance to this cell from any point inside the tile is computed. This distance is used as a sorting key; rejection testing proceeds as before. This introduces some per\-tile setup work and means we have to calculate the y\-distances per pixel again \(tiles aren't wide enough to make precalculating them advantageous\), but it's perfectly symmetrical in x and y, can also reject pixels based on large x\-distance, and is just as easy to parallelize as the previous algorithm. It does add code, though \- roughly another 20 extra lines.

So, how do the algorithms compare to each other? When calculating a 1024x1024 image with randomly placed points \(with minimum distance constraint\) on the Core2Duo 2.2GHz notebook I'm writing this on, I get the following run times \(single threaded\):

```
64 points.
         brute force:    710881 microseconds
                tree:   1707396 microseconds
           sort by y:    148130 microseconds
      sort by y, SSE:     55308 microseconds
               tiles:    123540 microseconds
          tiles, SSE:     32005 microseconds

128 points.
         brute force:   1528133 microseconds
                tree:   2182593 microseconds
           sort by y:    189426 microseconds
      sort by y, SSE:     76763 microseconds
               tiles:    150655 microseconds
          tiles, SSE:     42470 microseconds

256 points.
         brute force:   3344158 microseconds
                tree:   2919555 microseconds
           sort by y:    258804 microseconds
      sort by y, SSE:    107899 microseconds
               tiles:    226136 microseconds
          tiles, SSE:     68839 microseconds

512 points.
         brute force:   7170120 microseconds
                tree:   3690930 microseconds
           sort by y:    330661 microseconds
      sort by y, SSE:    146126 microseconds
               tiles:    401721 microseconds
          tiles, SSE:    136655 microseconds
```

The tree\-less variants are not only *much* less code \(the tree\-based variant is close to 200 lines of code, and I've taken care not to do anything stupid in there, and spent some time debugging it; "sort by y" is around 60 lines of fairly straightforward code that worked fine on the first attempt\), they also run circles around the supposedly more "clever" tree code, beating it by *an order of magnitude* in nearly all cases! [The code is available here](http://www.farbrausch.de/~fg/code/cellular.cpp); I've compiled it with VC2005 using /fp:fast and /arch:SSE. 

So, yeah. Have fun with cellular textures, but just stay clear of the trees. It's easier, smaller, *and* faster \- at least within the usual operating conditions encountered in texture generation.

**UPDATE:** There's one thing I forgot to mention, namely that using a point location structure has a fundamental asymmetry in the resulting algorithm, just like the sort\-by\-y approach has: we effectively want to compute the 2 nearest neighbors among the set of cell centers \(let's call it C\) for a set of points on a regular grid of pixels \(let's call the grid G\). The point location approach tries to use the structure of C, but completely ignores the structure of G, just starting from the beginning for each point \- when put that way, it should be obvious why this is wasteful: it's far more sensible to try to classify whole groups \(subrectangles\) of G, only subdiving them when necessary. This problem is called "all nearest neighbors", and is far closer to what we need. I haven't yet implemented any solution based on all nearest neighbors, but I'm fairly certain that it would be more code than the tree\-based approach and usually faster than all of the algorithms presented here. Maybe later...

**UPDATE 2:** Another [article](*how-to-generate-cellular-textures-2) on the topic. I've found a bug in the "tiles" code, so don't use the code described here! The new version is much faster.
