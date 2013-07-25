-title=A trip through the Graphics Pipeline 2011: Index
-time=2011-07-09 09:31:35
Welcome.

This is the index page for a series of blog posts I'm currently writing about the D3D/OpenGL graphics pipelines *as actually implemented by GPUs*. A lot of this is well known among graphics programmers, and there's tons of papers on various bits and pieces of it, but one bit I've been annoyed with is that while there's both broad overviews and very detailed information on individual components, there's not much in between, and what little there is is mostly out of date.

This series is intended for graphics programmers that know a modern 3D API \(at least OpenGL 2.0\+ or D3D9\+\) well and want to know how it all looks under the hood. It's *not* a description of the graphics pipeline for novices; if you haven't used a 3D API, most if not all of this will be completely useless to you. I'm also assuming a working understanding of contemporary hardware design \- you should at the very least know what registers, FIFOs, caches and pipelines are, and understand how they work. Finally, you need a working understanding of at least basic parallel programming mechanisms. A GPU is a massively parallel computer, there's no way around it.

Some readers have commented that this is a really low\-level description of the graphics pipeline and GPUs; well, it all depends on where you're standing. GPU architects would call this a *high\-level* description of a GPU. Not quite as high\-level as the multicolored flowcharts you tend to see on hardware review sites whenever a new GPU generation arrives; but, to be honest, that kind of reporting tends to have a very low information density, even when it's done well. Ultimately, it's not meant to explain how anything actually *works* \- it's just technology porn that's trying to show off shiny new gizmos. Well, I try to be a bit more substantial here, which unfortunately means less colors and less benchmark results, but instead lots and lots of text, a few mono\-colored diagrams and even some \(*shudder*\) equations. If that's okay with you, then here's the index:

* [Part 1](*a-trip-through-the-graphics-pipeline-2011-part-1): Introduction; the Software stack.
* [Part 2](*a-trip-through-the-graphics-pipeline-2011-part-2): GPU memory architecture and the Command Processor.
* [Part 3](*a-trip-through-the-graphics-pipeline-2011-part-3): 3D pipeline overview, vertex processing.
* [Part 4](*a-trip-through-the-graphics-pipeline-2011-part-4): Texture samplers.
* [Part 5](*a-trip-through-the-graphics-pipeline-2011-part-5): Primitive Assembly, Clip/Cull, Projection, and Viewport transform.
* [Part 6](*a-trip-through-the-graphics-pipeline-2011-part-6): \(Triangle\) rasterization and setup.
* [Part 7](*a-trip-through-the-graphics-pipeline-2011-part-7): Z/Stencil processing, 3 different ways.
* [Part 8](*a-trip-through-the-graphics-pipeline-2011-part-8): Pixel processing \- "fork phase".
* [Part 9](*a-trip-through-the-graphics-pipeline-2011-part-9): Pixel processing \- "join phase".
* [Part 10](*a-trip-through-the-graphics-pipeline-2011-part-10): Geometry Shaders.
* [Part 11](*a-trip-through-the-graphics-pipeline-2011-part-11): Stream\-Out.
* [Part 12](*a-trip-through-the-graphics-pipeline-2011-part-12): Tessellation.
* [Part 13](*a-trip-through-the-graphics-pipeline-2011-part-13): Compute Shaders.

  <a rel="license" href="http://creativecommons.org/publicdomain/zero/1.0/">
    <img src="http://i.creativecommons.org/p/zero/1.0/88x31.png" style="border-style:none;" alt="CC0"/>
  </a>
<br>  <br>
<br/>
<br>  To the extent possible under law,
<br>  <a rel="dct:publisher" href="http://fgiesen.wordpress.com">
    <span>Fabian Giesen</span></a>
<br>  has waived all copyright and related or neighboring rights to
<br>  <span>A trip through the Graphics Pipeline 2011</span>.
