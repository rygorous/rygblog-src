-title=Linear Algebra Toolbox 2
-time=2012-06-16 06:37:04
In the [previous part](*linear-algebra-toolbox-1) I covered a bunch of basics. Now let's continue with stuff that's a bit more fun. Small disclaimer: In this series, I'll be mostly talking about finite\-dimensional, real vector spaces, and even more specifically $$\mathbb{R}^n$$ for some n. So assume that's the setting unless explicitly stated otherwise; I don't want to bog the text down with too many technicalities.

### \(Almost\) every product can be written as a matrix product

In general, most of the functions we call "products" share some common properties: they're examples of "bilinear maps", that is vector\-valued functions of two vector\-valued arguments which are linear in both of them. The latter means that if you hold either of the two arguments constant, the function behaves like a linear function of the other argument. Now we know that any linear function $$f$$ can be written as a matrix product $$f(x)=Mx$$ for some matrix M, provided we're willing to choose a basis.

Okay, now take one such product\-like operation between vector spaces, let's call it $$*$$. What the above sentence means is that for any $$a$$, there is a corresponding matrix $$M_a$$ such that $$a*b = M_a b$$ \(and also a $$M'_b$$ such that $$a*b = M'_b a$$, but let's ignore that for a minute\). Furthermore, since a product is linear in *both* arguments, $$M_a$$ itself \(respectively $$M'_b$$\) is a linear function of a \(respectively b\) too.

This is all fairly abstract. Let's give an example: the standard dot product. The dot product of two vectors a and b is the number $$a \cdot b = \sum_{i=1}^n a_i b_i$$. This should be well known. Now let's say we want to find the matrix $$M_a$$ for some a. First, we have to figure out the correct dimensions. For fixed a, $$a \cdot b$$ is a scalar\-valued function of two vectors; so the matrix that represents "a\-dot" maps a 3\-vector to a scalar \(1\-vector\); in other words, it's a 1x3 matrix. In fact, as you can verify easily, the matrix representing "a\-dot" is just "a" written as a row vector \- or written as a matrix expression, $$M_a = a^T$$. For the full dot product expression, we thus get $$a \cdot b = a^T b$$ = $$b^T a = b \cdot a$$ \(because the dot product is symmetric, we can swap the positions of the two arguments\). This works for any dimension of the vectors involved, provided they match of course. More importantly, it works the other way round too \- a 1\-row matrix represents a scalar\-valued linear function \(more concisely called a "linear functional"\), and in case of the finite\-dimensional spaces we're dealing with, all such functions can be written as a dot product with a fixed vector.

The same technique works for any given bilinear map. Especially if you already know a form that works on coordinate vectors, in which case you can instantly write down the matrix \(same as in part 1, just check what happens to your basis vectors\). To give a second example, take the cross product $$a \times b$$ in three dimensions. The corresponding matrix looks like this:

$$a \times b = [a]_\times b = \begin{pmatrix} 0 & -a_3 & a_2 \\ a_3 & 0 & -a_1 \\ -a_2 & a_1 & 0 \end{pmatrix} b$$.

The $$ [a]_\times b$$ is standard notation for this construction. Note that in this case, because the cross product is vector\-valued, we have a full 3x3 matrix \- and not just any matrix: it's a skew\-symmetric matrix, i.e. $$ [a]_\times = -[a]_\times^T$$. I might come back to those later.

So what we have now is a systematic way to write any "product\-like" function of a and b as a matrix product \(with a matrix depending on one of the two arguments\). This might seem like a needless complication, but there's a purpose to it: being able to write everything in a common notation \(namely, as a matrix expression\) has two advantages: first, it allows us to manipulate fairly complex expressions using uniform rules \(namely, the rules for matrix multiplication\), and second, it allows us to go the other way \- take a complicated\-looked matrix expression and break it down into components that have obvious geometric meaning. And that turns out to be a fairly powerful tool.

### Projections and reflections

Let's take a simple example: assume you have a unit vector $$v$$, and a second, arbitrary vector $$x$$. Then, as you hopefully know, the dot product $$v \cdot x = v^T x$$ is a scalar representing the length of the projection of x onto v. Take that scalar and multiply it by v again, and you get a vector that represents the component of x that is parallel to v:

$$x_\parallel = v(v \cdot x) = v (v^T x) = (v v^T)\, x =: P_v\, x$$.

See what happened there? Since it's all just matrix multiplication, which is associative \(we can place parentheses however we want\), we can instantly get the matrix $$P_v$$ that represents parallel projection onto v. Similarly, we can get the matrix for the corresponding orthogonal component:

$$x_\perp = x - x_\parallel = x - (v v^T) x = Ix - (v v^T) x = (I - v v^T) x =: O_v\, x$$.

All it takes is the standard algebra trick of multiplying by 1 \(or in this case, an identity matrix\); after that, we just use linearity of matrix multiplication. You're probably more used to exploiting it when working with vectors \(stuff like $$Ax + Ay = A (x+y)$$\), but it works in both directions and with arbitrary matrices: $$AB + AC = A (B+C)$$ and $$AB + CB = (A + C)B$$ \- matrix multiplication is another bilinear map.

Anyway, with the two examples above, we get a third one for free: We've just separated $$x$$ into two components, $$x = x_\perp + x_\parallel$$. If we keep the orthogonal part but flip the parallel component, we get a reflection about the plane through the origin with normal $$v$$. This is just $$x_\perp - x_\parallel$$, which is again linear in x, and we can get the matrix $$R_v$$ for the whole by subtracting the two other matrices:

$$x_\perp - x_\parallel = O_v\, x - P_v\, x = (O_v - P_v)\, x = (I - 2 v v^T) \, x =: R_v \, x$$.

None of this is particularly fancy \(and most of it you should know already\), so why am I going through this? Two reasons. First off, it's worth knowing, since all three special types of matrices tend to show up in a lot of different places. And second, they give good examples for transforms that are constructed by adding something to \(or subtracting from\) the identity map; these tend to show up in all kinds of places. In the general case, it's hard to mentally visualize what the sum \(or difference\) of two transforms does, but orthogonal complements and reflections come with a nice geometric interpretation.

I'll end this part here. See you next time!