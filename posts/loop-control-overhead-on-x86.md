-title=Loop control overhead on x86
-time=2011-02-17 15:51:10
This is gonna be a short one. Let's start with this simple loop to compute the dot product of two vectors vec\_a, vec\_b of signed 16\-bit values:

```
        ; (rsi=vec_a, rdi=vec_b, rcx=N_elements/16)
        pxor            xmm0, xmm0
        pxor            xmm1, xmm1

dot_loop:
        movdqa          xmm2, [rsi]
        movdqa          xmm3, [rsi+16]
        pmaddwd         xmm2, [rdi]
        pmaddwd         xmm3, [rdi+16]
        paddd           xmm0, xmm2
        paddd           xmm1, xmm3
        add             rsi, 32
        add             rdi, 32
        dec             rcx
        jnz             dot_loop
```

There's nothing really wrong with this code, but it executes more ops per loop iteration than strictly necessary. Whether this actually costs you cycles \(and how many\) heavily depends on the processor you're running on, so I'll dodge that subject for a bit and pretend there's no out\-of\-order execution to help us and every instruction costs at least one cycle.

Anyway, the key insight here is that we're basically using three registers \(`rsi`, `rdi`, `rcx`\) as counters, and we end up updating all of them. The key is to update less counters and shift some of the work to the magic x86 addressing modes. One way to do this is to realize that while `rsi` and `rdi` change every iteration, `rdi - rsi` is loop invariant. So we can compute it once and do this:

```
        sub             rdi, rsi
        pxor            xmm0, xmm0
        pxor            xmm1, xmm1

some_loop:
        movdqa          xmm2, [rsi]
        movdqa          xmm3, [rsi+16]
        pmaddwd         xmm2, [rsi+rdi]
        pmaddwd         xmm3, [rsi+rdi+16]
        paddd           xmm0, xmm2
        paddd           xmm1, xmm3
        add             rsi, 32
        dec             rcx
        jnz             some_loop
```

One `sub` extra before the loop, but one less `add` inside the loop \(of course we do that work in the addressing modes now, but luckily for us, they're basically free\).

There's a variant of this that computes `vec_a_end = rsi + rcx*32` at the start and replaces the `dec rcx` with a `cmp rsi, vec_a_end`. Two more instructions at the loop head, no instructions saved inside the loop, but we get a `cmp`/`jne` pair which Core2 onwards can fuse into one micro\-op, so that's a plus. VC\+\+ will often generate this style of code for simple loops.

We can still go one lower, though \- there's still two adds \(or one add\+one compare\), after all! The trick is to use a loop count in bytes instead of elements and have it count up from `-sizeof(vec_a)` to zero, so we can still use one `jnz` at the end to do our conditional jump. The code looks like this:

```
        shl             rcx, 5                  ; sizeof(vec_a)
        pxor            xmm0, xmm0
        pxor            xmm1, xmm1
        add             rsi, rcx                ; end of vec_a
        add             rdi, rcx                ; end of vec_b
        neg             rcx

some_loop:
        movdqa          xmm2, [rsi+rcx]
        movdqa          xmm3, [rsi+rcx+16]
        pmaddwd         xmm2, [rdi+rcx]
        pmaddwd         xmm3, [rdi+rcx+16]
        paddd           xmm0, xmm2
        paddd           xmm1, xmm3
        add             rcx, 32
        jnz             some_loop
```

The trend should be clear at this point \- a few more instrs in the loop head, but less work inside the loop. How much less depends on the processor. But the newest batch of Core i7s \(Sandy Bridge\) can fuse the `add`/`jnz` pair into one micro\-op, so it's very cheap indeed.