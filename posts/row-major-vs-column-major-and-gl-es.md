-title=Row-major vs. column-major and GL ES
-time=2011-05-04 08:11:06
There's two major \(no pun intended\) ways to store 2D arrays: Row\-major and Column\-major. Row\-major is the default layout in C, Pascal and most other programming languages; column\-major is the default in FORTRAN and some numeric math\-centric languages \(mainly Matlab and R\) \- presumably because they started out as a kind of frontend for FORTRAN code.

Confusingly, the same terminology is also used by some people to denote whether you're treating vectors as column vectors or row vectors by default. If you treat them as column vectors, you typically multiply a vector with a matrix from the left, i.e. the result of transforming a vector v by a matrix M is written $$Mv$$. Transforming a vector by M then N is written as $$NMv$$, which I thought was backwards and confusing when I first saw it, but it has the big advantage of being consistent with the way we usually write function evaluation and composition: $$NMv = N(M(v)) = (N \circ M)(v)$$ \(treating a matrix and its associated linear map given the standard basis as the same thing here\). This is why most Maths and Physics texts generally treat vectors as column vectors \(unless specified otherwise\). The "row\-major" convention defaults to row vectors, which means you end up with reverse order: $$vMN$$. This matches "reading order" \(take v, transform by M, transform by N\) but now you need to reverse the order when you look at the associated linear maps; this is generally more trouble than it's worth.

Historically, IRIS GL used the row\-vector convention, then OpenGL \(which was based on IRIS GL\) switched to column vectors in its specification \(to make it match up better with standard mathematical practice\) but at the same time switched storage layout from row\-major to column\-major to make sure that existing IRIS GL code didn't break. That's a somewhat unfortunate legacy, since C defaults to row\-major storage, so you would normally expect a C library to use that too. ES got rid of a lot of other historical ballast, so this would've been a good place to change it.

Anyway, a priori, there's no huge reason to strongly prefer one storage layout over the other. However in some cases, external constraints tilt the balance. I recently bitched a bit about OpenGL ES favoring column\-major order, because it happens to be such a case, and column\-major is the wrong choice. Don't get me wrong, it's by no means a big deal anyway, but it makes things less orthogonal than they need to be, which annoys me.

GLSL and HLSL have vec4/float4 as their basic native vector data type, and shader constants are usually passed in groups of 4 floats \(as of D3D10\+ HW this is a bit more freeform, but the alignment/packing rules are still float4\-centric\). In a row\-major layout, a 4x4 matrix gets stored as

```
struct mat4_row_major {
  vec4 row0;
  vec4 row1;
  vec4 row2;
  vec4 row3;
};
```

and multiplying a matrix with a 4\-vector gets computed as

```
  // This implements o = M*v
  o.x = dot(M.row0, v);
  o.y = dot(M.row1, v);
  o.z = dot(M.row2, v);
  o.w = dot(M.row3, v);
```

whereas for column\-major storage layout you get

```
struct mat4_col_major {
  vec4 col0;
  vec4 col1;
  vec4 col2;
  vec4 col3;
};

  // M*v expands to...
  o = M.col0 * v.x;
  o += M.col1 * v.y;
  o += M.col2 * v.z;
  o += M.col3 * v.w;
```

so column\-major uses muls/multiply\-adds whereas row\-major storage ends up using dot products. Same difference, so far \- generally, shaders take the exact same time for both variants. But there's an important special case: affine transforms, i.e. ones for which the last row of the matrix is "0 0 0 1". Generally almost all of the transforms you'll use in a game/rendering engine, except for the final projection transform, are of this form. More concretely, all of the transforms you'll normally use for character skinning are affine, and if you do skinning in a shader you'll use a lot of them, so their size matters. With the row\-major layout you can just drop the last row and do this:

```
  // M*v, where M is affine with last row not stored
  o.x = dot(M.row0, v);
  o.y = dot(M.row1, v);
  o.z = dot(M.row2, v);
  o.w = v.w; // often v.w==1 so this simplifies further
```

while with the column\-major layout, you get to drop the last entry of every column vector, but that saves neither memory nor shader instructions. \(As an aside, GL ES doesn't support non\-square matrix types directly; if you want to use a non\-square matrix, you have to use an array/struct of vecs instead \- another annoyance\)

Furthermore, I generally prefer \(for rendering code anyway\) to store matrices in the format that I'm gonna send to the hardware or graphics API. On GL ES, that means I have to do one of three things:

1. Use 4x4 matrices everywhere and live with 25% unnecessary extra arithmetic and memory transfers,
    <br>
2. Have my 3x4 matrix manipulation use row\-major layout while 4x4 uses column\-major,
    <br>
3. Avoid the GL ES builtin mat4 type and use a vec4\[4\] \(or a corresponding struct\) instead.

Now, options 2 and 3 are perfectly workable, but they're ugly, and it annoys me that an API that breaks compatibility with the original OpenGL in about 50 different ways anyway didn't clean up this historical artifact.