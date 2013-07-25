-title=Min, Max under negation and an AABB trick
-time=2013-01-15 03:21:17
The two obvious identities:

`min(a,b) = -max(-a, -b)`
<br>`max(a,b) = -min(-a, -b)`

can be used to rewrite algorithms using mixed min/max expressions in terms of just min \(or just max\). This can sometimes be useful when working with data that is intended to be processed with SIMD instructions, because it can be used to make the dataflow more regular. Let me give you a simple example to show what I mean: computing the axis\-aligned bounding box \(or AABB for short\) of the union of several 2D AABBs.

### AABB of the union of N 2D AABBs

A common representation for a 2D AABB just stores the extrema in both X and Y:

```
union AlignedBox2 {
  struct {
    float min_x, min_y;
    float max_x, max_y;
  };
  Vec4 simd;
};
```

The AABB for the union of N such AABBs can then be computed by computing the min/max over all bounds in the array, as follows:

```
AlignedBox2 union_bounds(const AlignedBox2 *boxes, int N) // N >= 1
{
  AlignedBox2 r = boxes[0];
  for (int i=1; i < N; i++) {
    r.min_x = min(r.min_x, boxes[i].min_x);
    r.min_y = min(r.min_y, boxes[i].min_y);
    r.max_x = max(r.max_x, boxes[i].max_x);
    r.max_y = max(r.max_y, boxes[i].max_y);
  }
  return r;
}
```

A typical 4\-wide SIMD implementation can apply the operations to multiple fields at the same time, but ends up wasting half the SIMD lanes on fields it doesn't care about, and does some extra work at the end to merge the results back together:

```
AlignedBox2 union_bounds_simd(const AlignedBox2 *boxes, int N)
{
  Vec4 mins = boxes[0].simd;
  Vec4 maxs = boxes[0].simd;
  for (int i=1; i < N; i++) {
    mins = min(mins, boxes[i].simd);
    maxs = max(maxs, boxes[i].simd);
  }

  AlignedBox2 r;
  r.minx = mins[0]; // or equivalent shuffle...
  r.miny = mins[1];
  r.maxx = maxs[2];
  r.maxy = maxs[3];
  return r;
}
```

But the identities above suggest that it might help to use a different \(and admittedly somewhat weird\) representation for 2D boxes instead, where we store the *negative* of max\_x and max\_y:

```
union AlignedBox2b {
  struct {
    float min_x, min_y;
    float neg_max_x, neg_max_y;
  };
  Vec4 simd;
};
```

If we write the computation of the union bounding box of two AABBs A and B in this form, we get \(the interesting part only\):

```
  r.min_x = min(a.min_x, b.min_x);
  r.min_y = min(a.min_y, b.min_y);
  r.neg_max_x = min(a.neg_max_x, b.neg_max_x);
  r.neg_max_y = min(a.neg_max_y, b.neg_max_y);
```

where the last two lines are just the result of applying the identity above to the original computation of `max_x` / `max_y` \(with all the sign flips thrown in\). Which means the SIMD version in turn becomes much easier \(and doesn't waste any work anymore\):

```
AlignedBox2b union_bounds_simd(const AlignedBox2b *boxes, int N)
{
  AlignedBox2b r = boxes[0];
  for (int i=1; i < N; i++)
    r.simd = min(r.simd, boxes[i]);

  return r;
}
```

And the same approach works for intersection too \- in fact, all you need to do to get a box intersection function is to turn the `min` into a `max`.

Now, this is just a toy example, but it shows the point nicely \- sometimes a little sign flip can go a long way. In particular, this trick can come in handy when dealing with 3D AABBs and the like, because groups of 3 don't fit nicely in typical SIMD vector sizes, and you don't always have another float\-sized value to sandwich in between; even if you don't store the negative of the max, it's usually much easier to sign\-flip individual lanes than it is to rearrange them.