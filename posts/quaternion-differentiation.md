-title=Quaternion differentiation
-time=2012-08-25 03:58:36
I wanted to point someone to a short explanation of this today and noticed, with some surprise, that I couldn't find something concise within 5 minutes of googling. So it seems worth writing up. I'm assuming you know what quaternions are and what they're used for.

First, though, it seems important to point one thing out: Actually, there's nothing special at all about either integration or differentiation of quaternion\-valued functions. If you have a quaternion\-valued function of one variable q\(t\), then

$$\displaystyle \dot{q}(t) = q'(t) = \frac{\mathrm{d}q}{\mathrm{d}t} = \lim_{h \rightarrow 0} \frac{q(t+h) - q(t)}{h}$$

same as for any real\- or complex\-valued function.

So what, then, is this post about? Simple: unit quaternions are commonly used to represent rotations \(or orientation of rigid bodies\), and rigid\-body dynamics require integration of orientation over time. Almost all sources I could find just magically pull a solution out of thin air, and those that give a derivation tend to make it way more complicated than necessary. So let's just do this from first principles. I'm assuming you know that multiplying two unit quaternions quaternions q<sub>1</sub>q<sub>0</sub> gives a unit quaternion representing the composition of the two rotations. Now say we want to describe the orientation q\(t\) of a rigid body rotating at constant angular velocity. Then we can write

$$q(0) = q_0$$
<br>$$q(1) = q_\omega q_0$$

where $$q_\omega$$ describes the rotation the body undergoes in one time step. Since we have constant angular velocity, we will have $$q(2) = q_\omega q_\omega q_0 = q_\omega^2 q_0$$, and more generally $$q(k) = q_\omega^k q_0$$ for all nonnegative integer k by induction. So for even more general t we'd expect something like

$$q(t) = q_\omega^t q_0$$.

Now, q<sub>ω</sub> is a unit quaternion, which means it can be written in *polar form*

$$q_\omega = \cos(\theta/2) + \sin(\theta/2) (\mathbf{n}_x i + \mathbf{n}_y j + \mathbf{n}_z k)$$

where θ is some angle and n is a unit vector denoting the axis of rotation. That part is usually mentioned in every quaternion tutorial. Embedding real 3\-vectors as the corresponding pure imaginary quaternion, i.e. writing just $$\mathbf{n}$$ for the quaternion $$\mathbf{n}_x i + \mathbf{n}_y j + \mathbf{n}_z k$$, is usually also mentioned somewhere. What usually isn't mentioned is the crucial piece of information that the polar form of a quaternion, in fact, just the quaternion version of Euler's formula: Any unit complex number $$z$$ can be written as the complex exponential of a pure imaginary number $$z=\exp(it)=\cos(t) + i \sin(t)$$, and similarly any unit\-length quaternion \(and q<sub>ω</sub> in particular\) can be written as the exponential of a pure imaginary quaternion

$$q_\omega = \exp(\frac{\theta}{2}\mathbf{n})$$

which gives us a natural definition for

$$q_\omega^t = \exp(t \frac{\theta}{2} \mathbf{n})$$.

Now, what if we want to write a differential equation for the behavior of q\(t\) over time? Just compute the derivative of q\(t\) as you would for any other function of t. Using the chain and product rules we get:

$$\dot{q}(t) = \frac{\mathrm{d}}{\mathrm{d}t} (q_\omega^t q_0) = \frac{\theta}{2} \mathbf{n} \exp(t \frac{\theta}{2} \mathbf{n}) q_0 = \frac{\theta}{2} \mathbf{n} q(t)$$

The vector θ**n** is in fact just the angular velocity ω, which yields the oft\-cited but seldom\-derived equation:

$$\dot{q} = \frac{\mathrm{d}q}{\mathrm{d}t} = \frac{1}{2} \omega q$$

This is usually quoted completely without context. In particular, it's not usually mentioned that q\(t\) describes the orientation of a body with constant angular velocity, and similar for the crucial link to the exponential function.