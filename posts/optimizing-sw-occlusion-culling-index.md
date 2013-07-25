-title=Optimizing Software Occlusion Culling - index
-time=2013-02-17 23:33:57
In January of 2013, some nice folks at Intel released a [Software Occlusion Culling demo](http://software.intel.com/en-us/vcsource/samples/software-occlusion-culling) with full source code. I spent about two weekends playing around with the code, and after realizing that it made a great example for various things I'd been meaning to write about for a long time, started churning out blog posts about it for the next few weeks. This is the resulting series.

Here's the list of posts \(the series is now finished\):

1. ["Write combining is not your friend"](*write-combining-is-not-your-friend), on typical write combining issues when writing graphics code.
2. ["A string processing rant"](*a-string-processing-rant), a slightly over\-the\-top post that starts with some bad string processing habits and ends in a rant about what a complete minefield the standard C/C\+\+ string processing functions and classes are whenever non\-ASCII character sets are involved.
3. ["Cores don't like to share"](*cores-dont-like-to-share), on some very common pitfalls when running multiple threads that share memory.
4. ["Fixing cache issues, the lazy way"](*fixing-cache-issues-the-lazy-way). You could redesign your system to be more cache\-friendly \- but when you don't have the time or the energy, you could also just do this.
5. ["Frustum culling: turning the crank"](*frustum-culling-turning-the-crank) \- on the other hand, if you do have the time and energy, might as well do it properly.
6. ["The barycentric conspiracy"](*the-barycentric-conspirac) is a lead\-in to some in\-depth posts on the triangle rasterizer that's at the heart of Intel's demo. It's also a gripping tale of triangles, Möbius, and a plot centuries in the making.
7. ["Triangle rasterization in practice"](*triangle-rasterization-in-practice) \- how to build your own precise triangle rasterizer and *not* die trying.
8. ["Optimizing the basic rasterizer"](*optimizing-the-basic-rasterizer), because this is real time, not amateur hour.
9. ["Depth buffers done quick, part 1"](*depth-buffers-done-quick-part) \- at last, looking at \(and optimizing\) the depth buffer rasterizer in Intel's example.
10. ["Depth buffers done quick, part 2"](*depth-buffers-done-quick-part-2) \- optimizing some more!
11. ["The care and feeding of worker threads, part 1"](*care-and-feeding-of-worker-threads-part-1) \- this project uses multi\-threading; time to look into what these threads are actually doing.
12. ["The care and feeding of worker threads, part 2"](*the-care-and-feeding-of-worker-threads-part-2) \- more on scheduling.
13. ["Reshaping dataflows"](*reshaping-dataflows) \- using global knowledge to perform local code improvements.
14. ["Speculatively speaking"](*speculatively-speaking) \- on store forwarding and speculative execution, using the triangle binner as an example.
15. ["Mopping up"](*mopping-up) \- a bunch of things that didn't fit anywhere else.
16. ["The Reckoning"](*optimizing-software-occlusion-culling-the-reckoning) \- in which a lesson is learned, but [the damage is irreversible](http://www.alessonislearned.com/).

All the code is available on [Github](https://github.com/rygorous/intel_occlusion_cull/); there's various branches corresponding to various \(simultaneous\) tracks of development, including a lot of experiments that didn't pan out. The articles all reference the [blog branch](https://github.com/rygorous/intel_occlusion_cull/tree/blog) which contains only the changes I talk about in the posts \- i.e. the stuff I judged to be actually useful.

Special thanks to Doug McNabb and Charu Chandrasekaran at Intel for publishing the example with full source code and a permissive license, and for saying "yes" when I asked them whether they were okay with me writing about my findings in this way!

  <a rel="license" href="http://creativecommons.org/publicdomain/zero/1.0/">
    <img src="http://i.creativecommons.org/p/zero/1.0/88x31.png" style="border-style:none;" alt="CC0"/>
  </a>
<br>  <br>
<br/>
<br>  To the extent possible under law,
<br>  <a rel="dct:publisher" href="http://fgiesen.wordpress.com">
    <span>Fabian Giesen</span></a>
<br>  has waived all copyright and related or neighboring rights to
<br>  <span>Optimizing Software Occlusion Culling</span>.
