-title=Trig identities from complex exponentials
-time=2013-05-13 07:30:39
There's tons of useful trig identities. You could spend the time to learn them by heart, or just look them up on Wikipedia when necessary. But I've always had problems remembering where the signs and such go when trying to memorize this directly. At least for me, what worked way better is this: spend a few hours familiarizing yourself with complex numbers if you haven't done so already; after that, most identities that you need in practice are easy to derive from Euler's formula:

$$e^{ix} = \exp(ix) = \cos(x) + i \sin(x)$$

Let's do the basic addition formulas first. Euler's formula gives:

$$\cos(x+y) + i \sin(x+y) = \exp(i(x+y)) = \exp(ix) \exp(iy)$$

and once we apply the identity again we get:

$$(\cos(x) + i \sin(x)) (\cos(y) + i \sin(y))$$

multiplying out:

$$(\cos(x) \cos(y) - \sin(x) \sin(y)) + i (\sin(x) \cos(y) + \cos(x) \sin(y))$$

The terms in parentheses are all real numbers; equating them with our original expression yields the result

$$\cos(x+y) = \cos(x) \cos(y) - \sin(x) \sin(y)$$
<br>$$\sin(x+y) = \sin(x) \cos(y) + \cos(x) \sin(y)$$

Both addition formulas for the price of one. \(In fact, this exploits that the addition formulas for trigonometric functions and the addition formula for exponents are really the same thing\). The main point being that if you know complex multiplication, you never have to remember what the grouping of factors and the signs are, something I used to have trouble remembering.

Plugging in x=y into the above also immediately gives the double\-angle formulas:

$$\cos(2x) = \cos(x)^2 - \sin(x)^2$$
<br>$$\sin(2x) = 2 \sin(x) \cos(x)$$

so if you know the addition formulas there's really no reason to learn these separately.

Then there's the well\-known

$$\cos(x)^2 + \sin(x)^2 = 1$$

but it's really just the Pythagorean theorem in disguise \(since cos\(x\) and sin\(x\) are the side lengths of a right\-angled triangle\). So not really a new formula either!

Moving either the cosine or sine terms to the right\-hand side gives the two *immensely* useful equations:

$$\cos(x)^2 = 1 - \sin(x)^2$$
<br>$$\sin(x)^2 = 1 - \cos(x)^2$$

In particular, that second one is perfect if you need the sine squared of an angle that you only have the cosine of \(usually because you've determined it using a dot product\). Judicious application of these two tends to be a great way to simplify superfluous math in shaders \(and elsewhere\), one of my [pet peeves](*finish-your-derivations-please).

For practice, let's apply these two identities to the cosine double\-angle formula:

$$\cos(2x) = \cos(x)^2 - \sin(x)^2 = 2 \cos(x)^2 - 1 \Leftrightarrow cos(x)^2 = (cos(2x) + 1) / 2$$
<br>$$\cos(2x) = \cos(x)^2 - \sin(x)^2 = 1 - 2 \sin(x)^2 \Leftrightarrow sin(x)^2 = (1 - cos(2x)) / 2$$

why, it's the half\-angle formulas! Fancy meeting you here!

Can we do something with the sine double\-angle formula too? Well, it's not too fancy, but we can get this:

$$\sin(2x) = 2 \sin(x) \cos(x) \Leftrightarrow \sin(x) \cos(x) = \sin(2x) / 2$$

Now, let's go back to the original addition formulas and let's see what happens when we plug in negative values for y. Using $$\sin(-x) = -\sin(x)$$ and $$\cos(-x) = \cos(x)$$, we get:

$$\cos(x-y) = \cos(x) \cos(y) + \sin(x) \sin(y)$$
<br>$$\sin(x-y) = \sin(x) \cos(y) - \cos(x) \sin(y)$$

Hey look, flipped signs! This means that we can now add these to \(or subtract them from\) the original formulas to get *even more* identities!

$$\cos(x+y) + \cos(x-y) = 2 \cos(x) \cos(y)$$
<br>$$\cos(x-y) - \cos(x+y) = 2 \sin(x) \sin(y)$$
<br>$$\sin(x+y) + \sin(x-y) = 2 \sin(x) \cos(y)$$
<br>$$\sin(x+y) - \sin(x-y) = 2 \cos(x) \sin(y)$$

It's the product\-to\-sum identities this time. I got one more! We've deliberately flipped signs and then added/subtracted the addition formulas to get the above set. What if we do the same trick in reverse to get rid of those x\+y and x\-y terms? Let's set $$x = (a + b)/2$$ and $$y = (b - a)/2$$ and plug that into the identities above and we get:

$$\cos(b) + \cos(a) = 2 \cos((a+b)/2) \cos((b-a)/2)$$
<br>$$\cos(a) - \cos(b) = 2 \sin((a + b)/2) \sin((b - a)/2)$$
<br>$$\sin(b) + \sin(a) = 2 \sin((a + b)/2) \cos((b - a)/2)$$

Ta\-dah, it's the sum\-to\-product identities. Now, admittedly, we've taken quite a few steps to get here, and looking these up when you need them is going to be faster than walking through the derivation \(if you ever need them in the first place \- I don't think I've ever used the product/sum identities in practice\). But still, working these out is a good exercise, and a lot less likely to go wrong \(at least for me\) than memorizing lots of similar formulas. \(I never can get the signs right that way\)

Bonus exercise: work out general expressions for $$\cos(x)^n$$ and $$\sin(x)^n$$. Hint:

$$\cos(x) = (\exp(ix) + \exp(-ix))/2$$
<br>$$\sin(x) = (\exp(ix) - \exp(-ix))/2i$$.

And I think that's enough for now. \(At some later point, I might do an extra post about one of the sneakier trig techniques: the [Weierstrass substitution](http://en.wikipedia.org/wiki/Weierstrass_substitution)\).