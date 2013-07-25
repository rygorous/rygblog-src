-parent=debris-opening-the-box
-title=Metaprogramming for madmen
-time=2012-04-08 09:04:41

Okay, previous posts from this series aimed to actually convey useful technical information: assuming you actually want to write say a mesh generator, there's definitely useful bits there.

This is *not* one of these posts. In fact, this is about what is pretty much the complete opposite: an insane ploy that, against all odds, actually kinda worked, then spectacularly backfired. We knew ahead of time this was gonna happen, but we were desperate.  I don't think there's anything of any use we actually learned from the whole thing \- but it makes for a cool story \(in a very nerdy way\), so why not? Consider it a \(seasonally appropriate!\) easter egg.

### The setting

This is recounting a true story that took place in late March and early April 2004 \- a bit less than 2 weeks before Breakpoint 2004, where we planned to release our 96k first\-person shooter [".kkrieger"](http://www.theprodukkt.com/kkrieger). While being a nice technical challenge, it was a complete failure as far as the game side was concerned \(mostly because no\-one involved really deeply cared about that aspect\). That's not what this post is about though \- the point is that we very nearly missed the 96k limit too.

The way any self\-respecting 4k intro, 64k intro or other size\-limited program starts out is, well, too large. I haven't done enough 4ks to give you an order of magnitude estimate, but most of our serious 64ks were somewhere around 70\-80k a few weeks before they were supposed to be released. The last 2 weeks usually ended up turning into a frenetic rush to simultaneously get the thing actually finished \(put all the content in etc.\) and make it fit within the size limit. Doing either of those is a real challenge by itself. Doing both at once is both extremely stressful and mentally exhausting, and by the end of it, you're basically in need of a vacation.

Anyway, there's \(broadly speaking\) 3 different steps to making sure you get small code:

1. Architecture. Basically, design the code in a way that enables it to be small. Know exactly what goes into it, keep it modular, and make sure the algorithms are appropriate. Store data in the right way, and work with your back\-end packer, not against it. All of this is pretty much over 2 weeks before release though \- if you didn't get that part right early enough, you're not gonna be able to fix it in time.
2. Evicting ballast. There's gonna be whole paths of code that are just not getting used. If your data doesn't have a single torus in it, there's no point including the code that generates it \- and if there's just one torus, you can maybe replace it with something else in the art. You get the idea. This step is fairly easy provided you have at least rudimentary stats on your content, and it yields big wins in short time \(in a 64k context, usually several kilobytes for less than an hour of work\).
3. Detail work. This is where it gets messy. It basically boils down to dumping stats about all of the functions in the code, figuring out which are larger than they should be and what you can do to make them smaller. Lots of staring at disassembly listings trying to find out where the compiler is generating big code and why. Also lots of time staring at the content and figuring out if there's some shortcuts you can take to make *this particular intro* smaller. This is where you start switching to a different branch \(or at the very least wrap all of your changes in `#ifdef`\) because you're going to introduce bugs and by the end of it, parts of the code are gonna be ruined. It's also slow work \- by the point the initial easy targets are down, and assuming there's nothing else to do, I can get 32\-bit x86 code \(in a 64k intro context\) smaller at a rate of about 300\-400 bytes per day, tops.

Basically, by the end of step 2, you have a pretty good idea of how much more work is left, even though you have very little clue of what that work is :\). Note this is very different from things like speed optimization. For speed optimization, you're usually willing to make significant changes to data flow to do less work, at least where it matters, and you concentrate on hot spots. For size optimization, hot spots are mostly irrelevant; sure there may be a place where a big array ends up being initialized by code rather than being stored as data, and fixing that kind of thing is usually easy and fun, but mostly the hot spots in a "size profile" are the places where the actual work gets done. Unless you actually do work that is completely unnecessary, optimizing for speed will not make your code smaller in an absolute sense, it will just move the complexity \(and thus size\) somewhere else in the executable image.

Speed micro\-optimization is about staring at loops and figuring out how to make them tighter. Size micro\-optimization is about staring at large bodies of code and figuring out how to either get rid of it completely, share code with something else that's similar enough, or doing small architecture\-specific tricks with an "area effect". For example, on x86, you can reorder struct fields so the ones you access most often \- in terms of distinct instances, not number of times they end up being executed \- end up within 127 bytes of the base pointer so 8\-bit displacements get used. Things like that.

With that established, let's get back to kkrieger.

### 98304

The first time we got the "player" versions of kkrieger running, the compressed executable was something like 120 kilobytes. By the time we had thrown out all the ballast and were finished tweaking the data formats, we were down to about 102k, but that was still with some content \(and good chunks of the game \- not that there was that much to begin with!\) missing. A bit more than two weeks before the release, we started meeting \(more or less full\-time\) at [Chaos's](http://www.xyzw.de/) place to put it all together \- note things were complicated by the fact that Chaos, me, and [giZMo](http://www.pixelz.de/) \(one of our two artists\) were also organizers of Breakpoint, the party where kkrieger was to be released, so we also had to arrive early at the party place, build everything up and so forth. So we knew there was maybe a week and a half left, and the aforementioned frenzy set in \- worsened by the fact that a lot of the art was still incomplete \(and parts of it were broken in the small "player" executable\) and there were gaping holes in the game code \(most importantly, some serious collision issues that we never fixed\). Lots of work and little sleep. At some point, Chaos put up a \(hand\-drawn\) sign saying just "98304", the target size \(in bytes\) we were aiming for \- 96 \(binary\) kilobytes.

A week before release, we were at 100k. The realization started to sink in: *At the rate we were going, this was not going to work out* \- unless we were willing to throw out large amounts of content, which we *really* didn't want to. We needed to change gears and come up with another plan, fast.

### A plan so insane, it might just work.

The key idea was that, in the "detail work" step, there's lots of things you could do if you were willing to *really* specialize the code to the content. As in, literally throw out all code paths that will never be taken for the given content. In the final shipping executable, everything is procedurally generated from the same source data, always; the code in the player needs to work for that one data file and nothing else. There's a big catch, though: it's a time sink to manually determine exactly which code paths are actually necessary, and once start going down this road, you really cannot touch the data anymore.

In short, doing this manually is not only crap work, it's also extremely brittle \- which is why we never did this for any our previous 64ks. However, in this case, we were desperate, and we really just didn't have any other idea of what else we could do to shave off 4 kilobytes in a week. So we did what any self\-respecting programmer would do in this situation: we decided to write a program to do it for us.

The idea was this: We decided to write a new tool, "lekktor" \(always with the double\-ks, I know\). It's a play on the German word "Lektor" which means editor, as in person who edits books, not text editor. Lekktor was to take the program and instrument it with detailed code coverage tracking. Then, in a second pass, it would take the code coverage information gathered in the first pass and eliminate all the paths that were never taken. Since all the content generation is deterministic and happens at the start of the program, you'd just need to launch the game once in instrumented mode, take the dumped coverage information, then run lekktor again to write the "dead\-stripped" source files and recompile.

Sounds relatively simple, right? The only problem being that it involves parsing and processing C\+\+ source code.

### My kingdom for a pretty\-printer

Chaos' original idea was to start from a source code pretty\-printer \(think GNU indent and programs like that\). Note that the kind of source processing described above doesn't really care about declarations and types, the two trickiest bits of C\+\+. Really, all you need to know to be able to do this kind of processing is to detect and parse certain kinds of statements and expressions: `if`, `else`, `for`, `while`, `do`, and the `&&`, `||` and `?:` operators. We figured that a source code pretty\-printer should understand at least that much about C\+\+ code, and then we could add some extra tokens in strategic places and we'd be set.

Alas, we spent an afternoon looking at different such packages, and none of them actually understood even that much about C/C\+\+ code; they were mostly trying to make do with regular expressions. That wasn't gonna fly for what we needed. At the end of the day \(the Sunday before Easter Sunday, 2004\), we hadn't found anything useful \- we had a plan, but no way to make it work.

That's when Chaos decided that, "well, guess I'll need to write my own C\+\+ parser then". 

What, you think I was kidding with the title of this post? Note we had about 3 days total to make this work, and we were going all in by doing this; if this hadn't worked out, we'd have been screwed. Luckily, it did work out. Sort of.

### Parsing C\+\+ \- how hard can it be?

Turns out, not *that* hard, provided you a\) only need to do it approximately, b\) can just change the program you're trying to parse to work around problems,  and c\) are willing to take some shortcuts to simplify matters considerably. We didn't need to be able to parse template declarations, for example; in fact, we just parsed unpreprocessed C\+\+ source files, and skipped on headers entirely \(we didn't have any significant amount of code in headers, so there was no reason to\). That meant we needed to modify parts of the code so that `#ifdef` and the like didn't mess with the control structure. For example, stuff like

```
    if (condition)
    {
        // ...
    }
#ifndef IS_INTRO
    else (condition_2)
#else
    else (condition_3)
#endif
    {
        // ...
    }
```

wasn't allowed \- not a big loss, but you get the idea: we were totally willing to reformat code in fairly simple and mechanical ways if it meant we'd get our code coverage analysis.

The next morning, Chaos had to take a break from his "vacation" time and go to a work meeting in Berlin. That meant a roughly 2\-hour train ride in each direction; he took his laptop, a pair of headphones and a copy of ["A Retargetable C Compiler: Design and Implementation"](http://www.amazon.com/Retargetable-Compiler-Design-Implementation/dp/0805316701) with him. By the time he came back in the late afternoon, he had a very rough parser that could "understand" simple functions \- and, of course, indent them properly :\). By the time we went to sleep that night, we had it working on parts of our target codebase.

By noon the next day, we could process significant chunks of the code we were interested in, and in the early afternoon, we added code coverage tracking and "dead code elimination". The first worked by assigning unique IDs to each location and just incrementing a corresponding counter whenever execution got through there; the second, by adding `if (0)` in strategic locations \(way easier than actually removing the code yourself \- just let the compiler's dead code elimination deal with it!\).

To give an example of what it did: Here's a short original fragment from GenMesh that deals with selection processing:

```
void GenMeshElem::SelElem(sU32 mask,sBool state,sInt mode)
{
  switch(mode)
  {
  case MSM_ADD:    if(state) Mask |= mask;                     break;
  case MSM_SUB:    if(state) Mask &= ~mask;                    break;
  case MSM_SET:    if(state) Mask |= mask; else Mask &= ~mask; break;
  case MSM_SETNOT: if(state) Mask &= ~mask; else Mask |= mask; break;
  }
}
```

and here's the same code after Lekktor was done with it \(run using the kkrieger data\):

```
void GenMeshElem::SelElem(sU32 mask,sBool state,sInt mode)
{
  switch(mode)
  {
    {
    }
    case MSM_ADD:
    {
      if(state)
      {
        Mask|=mask;
      }
    }
    break;
    {
    }
    case MSM_SUB:
    {
      if(state)
      {
      }
      if(1)
      {
        Mask&=~ mask;
      }
    }
    break;
    {
    }
    case MSM_SET:
    {
      if(state)
      {
        Mask|=mask;
      }
      else
      {
        Mask&=~ mask;
      }
    }
    break;
    {
    }
    case MSM_SETNOT:
    {
      if(state)
      {
      }
      if(1)
      {
        Mask&=~ mask;
      }
      else
      {
      }
      if(0)
      {
        if(0)
        {
          Mask|=mask;
        }
      }
    }
    break;
    {
    }
  }
}
```

Aha \- looks like that for this function, the `MSM_SUB` path only ever gets called with `state` true, and same for the `MSM_SETNOT` path, so we can get rid of the ifs. Yeah, that's the kind of thing you would *never ever* consider doing manually; it's obviously extremely brittle and it only saves a handful of bytes \(a single compare and a conditional branch\). But that's exactly the point \- saving hundreds of bytes in one place can be done well by human optimizers. Saving 3\-5 bytes in a thousand places, not so much.

Note that for every `if`, we keep track of whether it's either never or always taken; we still need to evaluate the if expression \(which might have side effects!\), so the original `if` stays, but we yank everything out of the body and instead put it into a `if (0)` \(or `if (1)`\) block. Again, let the compiler's data\-flow analysis deal with the rest to clean this mess up!

So, after about two days of work, we had something that could, conceivably, make a significant dent in our size profile. So we started ran it on GenMesh and GenBitmap \(you can guess what those two things do\). And it worked! And saved about 2.5k \- more than halfway to our target! That's when we realized our insane plan might actually *work out*. Only problem being, we still had 1.5k to go, and we had to leave for Bingen to start with Breakpoint 2004 location set\-up the next day.

### Fast forward

I'll spare you the details of the next few days; they add little to this particular story. We did get to save about 4.5k using lekktor in the end, meeting our goal. Of course our ambitions increased a bit too; there was this small intro sequence we had lying around but were willing to get rid of \(since it really had nothing to do with the game\). Once we were getting close, we kept pushing trying to get to keep the intro too. But it was a tall order \- this was essentially the only sequence in the game using cut scene\-like functionality, so it was pulling in a lot of code that wasn't necessary for anything else, and cost a lot more than just the data. And of course there were tons of last\-minute content tweaks and \(ultimately futile\) attempts to clean up the broken gameplay.

By 2 hours before the competition started, we had a version without intro that fit inside the 96k limit, and a version with intro sequence that was 0.5k over the limit. Because we had other stuff to work on over the week, we'd mainly gotten there by \(carefully\) moving more and more source files over to lekktor. We had a magic `#pragma` you could use to turn processing on and off for regions of code; slowly we kept pushing deeper and deeper into the whole project. We started "lekktoring" not just the fully deterministic content generation code, but also things like the low\-level init code, parts of the 3D engine, and parts of the game code. We tried to be careful to mark up "taboo" sections correctly, but we were operating under severe stress, with tons of other stuff to do at the same time, and with not enough sleep, so we got sloppy in some places.

Suddenly, one and a half hours before the competition \(and several hours after the deadline \- benefits of being an Organizer...\), Chaos came up to me smiling, saying that he'd done some refactorings on the code and re\-did a Lekktor run, and now we did in fact have enough space to keep the intro sequence in! Needless to say, we were elated, packed the whole thing up with the README, zipped it and shipped it \(so to say\).

Of course, at this point you can imagine what had *actually* happened. So for our shared entertainment value, here's the full list of things \(so far as I know\) he didn't trigger during his trial run, which subsequently got compiled out of the released version:

* We used shadow volumes; there was a shadowing path for one\-sided stencil cards \(two passes\) or two\-sided stencil cards \(one pass\). The card we were recording on \(a GeForce4 Ti\) had two\-sided stencil, so the one\-sided stencil code didn't make it into the released version. Oops. \(This one had nothing to do with "user error" during the trial run\).
* In the menu at the start, cursor\-down works, but cursor\-up doesn't \(he never hit cursor\-up in menus during the test run\).
* The small enemies at the start can hit you, but he didn't get hit by any enemy shots, so in the released version of .kkrieger enemy shots deal no damage.
* Part of the collision resolution code disappeared, since it was never used in the trial run.

For what it's worth, this was maybe 230 bytes of code or so. Hey, considering we pretty much removed random ifs, that's a quite short list actually! :\)

### So what did we learn?

Honestly? I'm not quite sure. The story has a nice poetic justice to itself though, and I promise that I really didn't make any of this up \- all of this actually happened like I described!

In reality, we knew this was a bad idea when we started, but on the other hand, this was one of the best bad ideas we ever had :\), and some mistakes are worth making \(once\). And both Chaos and me were well aware that we were practically begging for something like the magically lost collision code to happen by doing this kind of stuff. But we were desperate and we really wanted to release kkrieger at Breakpoint, and we did, so it all worked out in the end. kkrieger was a crappy game with or without the bugs mentioned above; at least this way I got a nice story to tell.

Well, that and a running gag. In numerous occasions after .kkrieger, when we were working on intros, and hitting the size\-optimization phase, one of us would suggest "well, you know, we *could* dig up Lekktor again...". And then we'd both shudder and just shake our heads.
