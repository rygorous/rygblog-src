-title=Frustum planes from the projection matrix
-time=2012-09-01 03:54:17
Another quick one. Now this is another old trick, but it's easy to derive and still not as well\-known as it deserves to be, so here goes.

All modern graphics APIs ultimately expect vertex coordinates to end up in one common coordinate system where clipping is done \- clip space. That's the space that vertices passed to the rasterizer are expected in \- and hence, the space that Vertex Shaders \(or Geometry Shaders, or Domain/Tessellation Evaluation Shaders\) transform to. These shaders can do what they want, but the usual setup matches the original fixed\-function pipeline and splits vertex transformations into at least two steps: The projection transform and the model\-view transform, both of which can be represented as homogeneous 4x4 matrices.

The projection transform is the part that transforms vertices from camera view space to clip space. A view\-space input vertex position v is transformed with the projection matrix P and gives us the position of the vertex in clip space:

$$\displaystyle \begin{pmatrix} x \\ y \\ z \\ w \end{pmatrix} = P v = \begin{pmatrix} p_1^T \\ p_2^T \\ p_3^T \\ p_4^T \end{pmatrix} v$$

Here, I've split P up into its four row vectors p<sub>1</sub><sup>T</sup>, …, p<sub>4</sub><sup>T</sup>. Now, in clip space, the view frustum has a really simple form, but there's two slightly different formulations in use. GL uses the symmetric form:

$$-w \le x \le w$$
<br>$$-w \le y \le w$$
<br>$$-w \le z \le w$$

whereas D3D replaces the last row with $$0 \le z \le w$$. Either way, we get 6 distinct inequalities, each of which corresponds to exactly one clip plane: $$-w \le x$$ is the left clip plane, $$x \le w$$ is the right clip plane, and so forth. Now from the equation above we know that $$x=p_1^T v$$ and $$w=p_4^T v$$ and hence

$$-w \le x$$
<br>$$\Leftrightarrow 0 \le w + x$$
<br>$$\Leftrightarrow 0 \le p_4^T v + p_1^T v = (p_4^T + p_1^T) v$$

Or in words, v lies in the non\-negative half\-space defined by the plane p<sub>4</sub><sup>T</sup>\+p<sub>1</sub><sup>T</sup> \- we have a view\-space plane equation for the left frustum plane! For the right plane, we similarly get

$$x \le w \Leftrightarrow 0 \le w - x \Leftrightarrow 0 \le (p_4^T - p_1^T) v$$

and in general, for the GL\-style frustum we find that the six frustum planes in view space are exactly the six planes p<sub>4</sub><sup>T</sup>±p<sub>i</sub><sup>T</sup> for i=1, 2, 3 \- all you have to do to get the plane equations is to add \(or subtract\) the right rows of the projection matrix! For a D3D\-style frustum, the near plane $$0 \le z$$ is different, but it takes the even simpler form $$0 \le p_3^T v$$, so it's simply defined by the third row of the projection matrix.

Deriving frustum planes from your projection matrix in this way has the advantage that it's nice and general \- it works with any projection matrix, and is guaranteed to agree with the clipping / culling done by the GPU, as long as the planes are in fact derived from the projection matrix used for rendering.

And if you need the frustum planes in some other space, say in model space: not too worry! We didn't use any special properties of P \- the derivation works for *any* 4x4 matrix. The planes obtained this way are in whatever space the input matrix transforms to clip space \- in the case of P, view space, but it can be anything. To give an example, if you have a model\-view matrix M, then PM is the combined matrix that takes us from model\-space to clip\-space, and extracting the planes from PM instead of P will result in model\-space clip planes.