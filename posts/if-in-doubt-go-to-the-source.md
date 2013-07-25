-parent=debris-opening-the-box
-title=If in doubt, go to the source
-time=2012-04-15 19:18:55

As mentioned in the introduction to this series, our various demo tools contain a lot of cool ideas, but also a lot of bad ones that didn't work out, and the code has suffered as a result. Nevertheless, the code makes for an interesting historical document if nothing else, and we \(Farbrausch\), after some deliberation, decided to just open it up \- something we've been planning to do for ages, but were never able to pull of for various legal reasons. Well, all of those problems have gone away over the past year, so there was no good reason left to *not* publish the source.

So here it is: [https://github.com/farbrausch/fr_public](https://github.com/farbrausch/fr_public).

We decided to go with very permissive licenses: a lot of the code was released into the public domain, the rest is BSD\-licensed, and all of the \(currently uploaded\) content is released under Creative Commons CC\-BY or CC\-BY\-SA licenses. So if you want to play around with it, go ahead! Also, we will be adding both more demos and code as soon as we're able \- re\-licensing these things means we need to acquire permission from all the original authors, which takes a few days to sort out. Similarly, some of the code we're planning to release contains optional components encumbered with third\-party rights that we need to get rid of before we can make it public. 

Finally, there's some ongoing "reconstruction" work, too: the original code was written for various compiler versions etc., and some depended on old library versions that are no longer available. A separate branch of the repository \("vs2010"\) contains modified versions of the original code that should compile with VS2010.

And what about this series? Don't worry, the point I made in the first post of this series remains valid: Source code is a good way of communicating cookbook recipes, but a bad way of describing the underlying ideas. So this series will continue, only from now on, you'll be able to cross\-check against the actual source code and notice all the little white lies I'm telling to make things easier to follow or understand :\)

**UPDATE**: Turns out Memon just decided to [release source code for Demopaja](http://digestingduck.blogspot.com/2012/04/demopaja-sources.html), his demo\-tool, too! The more the merrier.
