-title=sinc and Polynomial interpolation
-time=2010-10-26 04:17:28
Another short one. This one bugged me for quite a while until I realized what the answer was a few years ago. The Sampling Theorem states that \(under the right conditions\)

$$\displaystyle x(t) = \sum_{n=-\infty}^{\infty} x(nT) \;\textrm{sinc}\left(\frac{t - nT}{T}\right)$$

where

$$\displaystyle \textrm{sinc}(x) = \frac{\sin(\pi x)}{\pi x}$$

\(the normalized sinc function\). The problem is this: Where does the sinc function come from? \(In a philosophical sense. It plops out of the proof sure enough, but that's not what I mean\). Fourier theory is full of \(trigonometric\) polynomials \(i.e. sine/cosine waves when you're dealing with real\-valued signals\), so where does the factor of x in the denominator suddenly come from?

The answer is a nice identity discovered by Euler:

$$\displaystyle \textrm{sinc}(x) = \prod_{n=1}^{\infty} \left(1 - \frac{x^2}{n^2}\right)$$

With some straightforward algebraic manipulations \(ignoring convergence issues for now\) you get:
<br>$$\displaystyle \textrm{sinc}(x) = \prod_{n=1}^{\infty} \left(1 - \frac{x}{n}\right) \left(1 + \frac{x}{n}\right)$$

$$\displaystyle = \prod_{\substack{n \in \mathbb{Z} \\ n \ne 0}} \left(1 - \frac{x}{n}\right) = \prod_{\substack{n \in \mathbb{Z} \\ n \ne 0 }} \frac{n - x}{n}$$

Compare this with the formula for Lagrange basis polynomials:

$$\displaystyle L_{i;n}(x) = \prod_{\substack{0 \le j \le n \\ j \ne i}} \frac{x_j - x}{x_j - x_i}$$

in other words, the sinc function is the limiting case of Lagrange polynomials for an infinite number of equidistant control points. Which is pretty neat :\)