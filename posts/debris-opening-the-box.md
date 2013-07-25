-title=Debris: Opening the box
-time=2012-02-14 04:58:05
It's now been almost 5 years since we \(farbrausch\) released [fr-041: debris](http://www.farbrausch.com/prod.py?which=2), and almost 8 years since the somewhat ill\-fated [.kkrieger](http://www.farbrausch.com/prod.py?which=114). We tried to package that technology up and sell it for a while, which I wasn't particularly happy with when we decided to start doing it and extremely unhappy with by the time we stopped :\). We decided to dissolve the company that owned the IP \(.theprodukkt GmbH\) about two years ago, a process that was finished last summer. Some months ago we got the tax returns for our last fiscal year; I missed the party on account of currently being on another continent from my other co\-founders.

So now both the tech and the code are somewhat orphaned. We could just release the source code into the public, but frankly it's an unholy mess, and you're likely to miss all the cool bits among the numerous warts. I've done source releases before, and we might still do it with Werkkzeug3 \(the tool/framework behind the two aforementioned productions and nineteen others\). But I'd really rather present it in a somewhat more curated form, where I highlight the interesting bits and get to sweep all the mess behind it under the rug. So here's the idea: this post contains a list of things in Debris that I think might make for an interesting post. Unlike my "Trip Through The Graphics Pipeline 2011" series, this list is far too long to just decide on a whim to do all of it. So instead, you get to vote: if there's anything on this list that you'd like me to write about, post a comment. If there's sufficient interest and I'm in the mood, I'll write a post about it. :\)

The one thing I'm *not* going to talk about is about our [tool](http://www.farbrausch.com/prod.py?which=115)\-centric way of producing demos. Chaos and me have talked about that several times and I'm getting bored of the topic \(I think there's videos on the net, but didn't find anything on my first Google\-sweep; will re\-check later\). Also, some of the topics have dependencies among each other, so I might decide to post something on the basics first before I get into specifics. Just so you're warned. Anyway, here's the list:

### Source code

* [If in doubt, go to the source](*if-in-doubt-go-to-the-source)
* The [fr_public repository](https://github.com/farbrausch/fr_public) on Github
* [GenThree overview](*genthree-overview)

### Basics / execution environment

* Operators \(the building block of our procedural system\)
* Writing small code on Win32/x86 \(in C\+\+\)
* Executable compression
* Memory Management on the editor side
* The Operator Execution Engine \(demo/player side\)

### Texture generation

* How to generate cellular textures [part 1](*how-to-generate-cellular-textures) and [part 2](*how-to-generate-cellular-textures-2).
* Fast blurs [part 1](*fast-blurs-1) and [part 2](*fast-blurs-2).
* Fast Perlin noise\-based texture generation
* Shitting bricks

### Compression

* [x86 code compression in kkrunchy](*x86-code-compression-in-kkrunchy)
* Squeezing operator data

### Animation

* Operator "initialization" versus "execution" \(animatable parameters\)
* Animation scripts
* The timeline

### Mesh Generation

* [Half-edge based mesh representations: theory](*half-edge-based-mesh-representations-theory)
* [Half-edge based mesh representations: practice](*half-edge-based-mesh-representations-practice)
* [Half-edges redux](*half-edges-redux)
* Extrusions
* Catmull\-Clark subdivision surfaces
* Bones and Bends
* 3D Text

### Sound

* Debris and kkrieger use Tammo "kb" Hinrichs's V2 synth, described on his blog: [part I](http://blog.kebby.org/?p=34), [part II](http://blog.kebby.org/?p=36), [part III](http://blog.kebby.org/?p=38), and [part IV](http://blog.kebby.org/?p=40).

### Effects

* Swarms of cubes
* Exploding geometry
* Image postprocessing

### Shaders and 3D engine

* Shadergen \(directly generates D3D9 bytecode for ubershaders, code [here](http://www.farbrausch.com/~fg/code/shadergen/)\)
* The old material/lighting system: .kkrieger, PS1.3, cubes
* The new material/lighting system: PS2.0, the city, multipass madness
* Basic engine architecture \- lights, layers and passes
* Converting generated meshes to rendering\-ready meshes
* Skinning and Shadow Volumes

### Other

* [Metaprogramming for madmen](*metaprogramming-for-madmen) \(a small story about .kkrieger\)

That's not all of it, but it's all I can think of right now that is a\) somewhat interesting \(to me that is\) and b\) something I can write about \- for example, I wouldn't be comfortable writing about the music/sound or overall flow/direction of the demo, since frankly I had little to do with that. And of course I didn't write the code for all of the above either :\), but I do know most of the code well enough to do a decent job describing it. That said, if you think there's something I missed, just ping me and I'll put it on the list.

So there you go. Your turn!