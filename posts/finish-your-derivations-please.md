-title=Finish your derivations, please
-time=2010-10-21 07:37:16
Every time you ship a product with half\-assed math in it, God kills a fluffy kitten by feeding it to an ill\-tempered panda bear \(don't ask me why \- I think it's bizarre and oddly specific, but I have no say in the matter\). There's tons of ways to make your math way more complicated \(and expensive\) than it needs to be, but most of the time it's the same few common mistakes repeated ad nauseam. Here's a small checklist of things to look out for that will make your life easier and your code better:

* **Symmetries**. If your problem has some obvious symmetry, you can usually exploit it in the solution. If it has radial symmetry around some point, move that point to the origin. If there's some coordinate system where the constraints \(or the problem statement\) get a lot simpler, try solving the problem in that coordinate system. This isn't guaranteed to win you anything, but if you haven't checked, you should \- if symmetry leads to a solution, the solutions are usually very nice, clean and efficient.
* **Geometry**. If your problem is geometrical, draw a picture first, even if you know how to solve it algebraically. Approaches that use the geometry of the problem can often make use of symmetries that aren't obvious when you write it in equations. More importantly, in geometric derivations, most of the quantities you compute actually have geometrical meaning \(points, distances, ratios of lengths, etc\). Very useful when debugging to get a quick sanity check. In contrast, intermediate values in the middle of algebraic manipulations rarely have any meaning within the context of the problem \- you have to treat the solver essentially as a black box.
* **Angles**. Avoid them. They're rarely what you actually want, they tend to introduce a lot of trigonometric functions into the code, you suddenly need to worry about parametrization artifacts \(e.g. dealing with wraparound\), and code using angles is generally harder to read/understand/debug than equivalent code using vectors \(and slower, too\).
* **Absolute Angles**. Particularly, never never *ever* use angles relative to some arbitrary absolute coordinate system. They *will* wrap around to negative at some point, and suddenly something breaks somewhere and nobody knows why. And if you're about to introduce some arbitrary coordinate system just to determine some angles, stop and think very hard if that's really a good idea. \(If, upon reflection, you're still undecided, [this website](http://www.nooooooooooooooo.com/) has your answer\).
* **Did I mention angles?** There's one particular case of angle\-mania that really pisses me off: Using inverse trigonometric functions immediately followed by sin / cos. atan2 / sin / cos: World's most expensive 2D vector normalize. Using acos on the result of a dot product just to get the corresponding sin/tan? Time to brush up your [trigonometric identities](http://en.wikipedia.org/wiki/List_of_trigonometric_identities#Inverse_trigonometric_functions). A particularly bad offender can be found [here](http://wiki.gamedev.net/index.php/D3DBook:\(Lighting\)_Oren-Nayar) \- the relevant section from the simplified shader is this:
    
    ```
    float alpha = max( acos( dot( v, n ) ), acos( dot( l, n ) ) );
float beta  = min( acos( dot( v, n ) ), acos( dot( l, n ) ) );
C = sin(alpha) * tan(beta);
    ```
    
    Ouch! If you use some trig identities and the fact that acos is monotonically decreasing over its domain, this reduces to:
    
    ```
    float vdotn = dot(v, n);
float ldotn = dot(l, n);
C = sqrt((1.0 - vdotn*vdotn) * (1.0 - ldotn*ldotn))
  / max(vdotn, ldotn);
    ```
    
    ..and suddenly there's no need to use a lookup texture anymore \(and by the way, this has way higher accuracy too\). Come on, people! You don't need to derive it by hand \(although that's not hard either\), you don't need to buy some formula collection, it's all on Wikipedia \- spend the two minutes and look it up!
* **Elementary linear algebra**. If you build some matrix by concatenating several transforms and it's a performance bottleneck, don't get all SIMD on it, do the obvious thing first: do the matrix multiply symbolically and generate the result directly instead of doing the matrix multiplies every time. \(But state clearly in comments which transforms you multiplied together in what order to get your result or suffer the righteous wrath of the next person to touch that code\). Don't invert matrices that you know are orthogonal, just use the transpose! Don't use 4x4 matrices everywhere when all your transforms \(except for the projection matrix\) are affine. It's not rocket science.
* **Unnecessary numerical differentiation**. Numerical differentiation is numerically unstable, and notoriously difficult to get robust. It's also often completely unnecessary. If you're dealing with analytically defined functions, compute the derivative directly \- no robustness issues, and it's usually faster too \(...but remember the chain rule if you warp your parameter on the way in\).

Short version: Don't just stick with the first implementation that works \(usually barely\). Once you have a solution, at least spend 5 minutes looking over it and check if you missed any obvious simplifications. If you won't do it by yourself, think of the kittens!