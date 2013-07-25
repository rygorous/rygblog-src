-title=Small note on Quaternion distance metrics
-time=2013-01-07 17:26:11
There's multiple ways to measure distances between unit quaternions \(a popular rotation representation in 3D\). What's interesting is that the popular choices are essentially all equivalent.

### Polar form

A standard way to build quaternions is using the polar \(axis\-angle\) form
<br>$$q = \exp(\frac{1}{2} \theta \mathbf{n}) = \cos(\theta/2) + \sin(\theta/2) (i n_x + j n_y + k n_z)$$, where n is the \(unit length\) axis of rotation, θ is the angle, and i, j and k are the imaginary basis vectors.

For a rotation in this form, we know how "far" it goes: it's just the angle θ. Since the real component of q is just cos\(θ/2\), we can read off the angle as
<br>$$\theta(q) = \theta(q, 1) := 2 \arccos(\textrm{real}(q)) = 2 \arccos(q \cdot 1)$$
<br>where the dot denotes the quaternion dot product.

This measures, in a sense, how far away the quaternion is from the identity element 1. To get a distance between two unit quaternions q and r, we rotate both of them such that one of them becomes the identity element. To do this for our pair q, r, we simply multiply both by r's inverse from the left, and since r is a unit quaternion its inverse and conjugate are the same:
<br>$$\theta(q,r) := \theta(r^*q, r^*r) = \theta(r^*q, 1) = 2 \arccos((r^*q) \cdot 1)$$

Note that cosine is a monotonic function over the interval we care about, so in any numerical work, there's basically never the need to actually calculate that arc cosine: instead of checking, say, whether the angle is less than some maximum error threshold T, we can simple check that the dot product is larger than cos\(T/2\). If you're actually taking the arc cosine for anything other than display purposes, you're likely doing something wrong.

### Dot product

Another way is to use the dot product directly as a distance measure between two quaternions. How does this relate to the angle from the polar form? It's the same, as we quickly find out when we use the fact that the dot product is invariant under rotations:

$$(q \cdot r) = (r^*q \cdot r^*r) = (r^*q \cdot 1)$$

and hence also

$$\theta(q,r) = 2 \arccos(q \cdot r)$$

So again, whether we minimize the angle between q and r \(as measured in the polar form\) or maximize the dot product between q and r boils down to the same thing. But there's one final choice left.

### L<sub>2</sub> distance

The third convenient metric is just using the norm of the difference between the two quaternions: $$||q-r||$$. The question is, can we relate this somehow to the other two? We can, and as is often the case, it's easier to work with the square of the norm:

$$||q-r||^2 = ||q||^2 - 2 (q \cdot r) + ||r||^2 = 1 - 2 (q \cdot r) + 1 = 2 (1 - q \cdot r)$$.

In other words, the distance between two unit quaternions again just boils down to the dot product between them \- albeit with a scale and bias this time.

### Conclusion

The popular choices of distance metrics between quaternions all boil down to the same thing. The relationships between them are simple enough that it's easy to convert, say, an exact error bound on the norm between two quaternions into an exact error bound on the angle of the corresponding rotation. Each of these three representations is the most convenient to use in some context; feel free to convert back and forth between them for different solvers; they're all compatible in the sense that their minima will always agree.

**UPDATE:** As Sam points out in the comments, you need to be careful about the distinction between quaternions and rotations here \(I cleared up the language in the article slightly\). Each rotation in 3\-dimensional real Euclidean space has two representations as a quaternion: the quaternion group double\-covers the rotation group. If you want to measure the distances between rotations not quaternions, you need to use slightly modified metrics \(see his comment for details\).