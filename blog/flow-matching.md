@def title = "Flow Matching: From Straight Paths to One-Step Sampling"
@def maxtoclevel = 2
@def mintoclevel = 2
@def flow_matching_demos = true

{{insert navbar.html}}

@@toc-container
@@toc
\tableofcontents
@@
@@

@@div

# Flow Matching: From Straight Paths to One-Step Sampling

@@date
November 16, 2026
@@

## Flow matching

Given samples from an unknown distribution, how can we generate new ones? For high-dimensional data such as images, we often have observations but no direct procedure for sampling from the distribution that produced them. One approach starts with a simpler distribution that is easy to sample, typically a standard Gaussian, and learns a map whose outputs approximately follow the target distribution.

Let's use two noisy moons as our target distribution. In this case, we can sample from the target directly and use fresh draws to evaluate the learned sampler.

~~~
<figure class="fm-demo fm-intro">
  <div class="fm-panels">
    <div class="fm-panel">
      <p>Gaussian source</p>
      <span class="fm-intro-time">\(t=0\)</span>
      <img src="/assets/blog/flow-matching/gaussian-source.svg" alt="Blue points sampled from a standard Gaussian." width="320" height="210">
    </div>
    <div class="fm-panel">
      <p>Two-moons target</p>
      <span class="fm-intro-time">\(t=1\)</span>
      <img src="/assets/blog/flow-matching/two-moons-target.svg" alt="Red points drawn from the target distribution form two noisy crescents, shown at the same scale as the Gaussian." width="320" height="210">
    </div>
  </div>
  <figcaption>A standard Gaussian and the target distribution for the flow.</figcaption>
</figure>
~~~

A continuous normalising flow defines a transport by an ordinary differential equation (ODE). To generate a sample, draw $X_0\sim\mathcal N(0,I_2)$ and solve

@@nonumber
$$
\dot x(t)=v_\theta(x(t),t),\qquad x(0)=X_0,\qquad 0\le t\le 1,
$$
@@

where $v_\theta(x,t)$ is the instantaneous velocity vector field at position $x$ and time $t$. The ODE transports the Gaussian draw $X_0$ to a sample $X_1^\theta=x(1)$ from the model distribution, which approximates the target.

How do we learn the velocity field? Flow matching constructs paths between noise and data samples. The velocities along these paths give us regression targets that we can compute directly [[1]](#fm-ref-1) [[2]](#fm-ref-2).

## Straight training paths and curved trajectories

Draw a pair $(X_0,X_1)$, with $X_0$ from the Gaussian and $X_1$ from the moons. For now, draw them independently. The training path and its velocity are

$$
X_t=(1-t)X_0+tX_1,
\qquad U=\frac{\mathrm d X_t}{\mathrm d t}=X_1-X_0.
$$

To get a training example, draw a random time $T$ uniformly from $[0,1]$, independently of the endpoint pair. At $T$, the segment is at $X_T$ and has velocity $U=X_1-X_0$. We train $v_\theta$ to predict $U$ from $(X_T,T)$ by minimising

@@nonumber
$$
\mathbb E\!\left[\|v_\theta(X_T,T)-U\|^2\right].
$$
@@

Both the position and the target velocity come from the straight segment, so we can compute the loss without solving the ODE.

In our experiments, $v_\theta$ is a multilayer perceptron (MLP) with three hidden layers of width $64$ and $\tanh$ activations.

To see what this regression learns, consider the loss over all fields $v$. Fix an input $(x,t)$ and write $m=\mathbb E[U\mid X_T=x,T=t]$. Set $a=v(x,t)-m$ and $b=U-m$. The squared error is

@@fm-equation
$$
\|a-b\|^2=\|a\|^2+\|b\|^2-2\langle a,b\rangle.
$$
@@

After conditioning on $(X_T,T)=(x,t)$, the cross term averages to zero because $a$ is fixed and $\mathbb E[b\mid X_T=x,T=t]=0$. The term $\|b\|^2$ is independent of $v$. The term $\|a\|^2$ is minimised by choosing $v(x,t)=m$. Since $T$ was sampled independently, this gives the fixed-time expression

$$
v^*(x,t)=\mathbb E[X_1-X_0\mid X_t=x].
$$

Each training segment carries a constant velocity. At a given position and time, the field $v^*$ averages the velocities of the segments that can pass through there. As an ODE trajectory moves, it encounters a succession of these local averages. Its direction can therefore change along the way.

The straight segments start with the Gaussian law at $t=0$ and end with the target law at $t=1$. Does the averaged field $v^*$ do the same? Let $\mu_t$ be the law of $X_t$. For a smooth, compactly supported function $f$, the chain rule and conditional expectation give

@@nonumber
$$
\frac{\mathrm d}{\mathrm dt}\mathbb E[f(X_t)]
=\mathbb E[\nabla f(X_t)\cdot U]
=\mathbb E[\nabla f(X_t)\cdot v^*(X_t,t)].
$$
@@

The last expression gives the rate of change of the average of $f$ when $\mu_t$ moves with velocity $v^*$. This is the weak form of the continuity equation. If the ODE driven by $v^*$ has a flow and the continuity equation has a unique solution, then starting the ODE from the same Gaussian gives law $\mu_t$ at each $t$. In particular, its endpoint has the target law. The two constructions agree in distribution at each time, even though they can send the same starting point to different endpoints [[1]](#fm-ref-1) [[2]](#fm-ref-2).

~~~
<div class="fm-demo" id="fm-explorer" role="region" aria-label="Trajectory explorer">
  <div class="fm-controls">
    <label class="fm-flow-time" for="fm-time">
      <span>Flow time \(t\)</span>
      <span class="fm-flow-time-track">
        <output for="fm-time" aria-hidden="true">0.50</output>
        <input id="fm-time" type="range" min="0" max="50" value="25" aria-valuetext="0.50">
      </span>
    </label>
    <label for="fm-pairing">Coupling
      <select id="fm-pairing">
        <option value="independent">Independent</option>
        <option value="ot">Entropic OT</option>
      </select>
    </label>
    <div class="fm-actions">
      <button type="button" id="fm-play" disabled>Play</button>
      <button type="button" id="fm-reset" disabled>Reset</button>
    </div>
  </div>
  <div class="fm-panels">
    <div class="fm-panel">
      <p>Training segments</p>
      <div class="fm-plot" role="img" aria-label="Straight training segments at the selected time"></div>
    </div>
    <div class="fm-panel">
      <p>Integrated trajectories</p>
      <div class="fm-plot" role="img" aria-label="Integrated ODE trajectories at the selected time"></div>
    </div>
  </div>
  <div class="fm-legend">Noise <span class="fm-time-gradient" aria-hidden="true"></span> Data</div>
  <p class="fm-status" role="status">Loading trajectory data…</p>
  <noscript>This figure requires JavaScript. You can rerun the experiment with the Pluto notebook linked at the end of the post.</noscript>
</div>
~~~

## Sampling by solving the ODE

To draw a sample, we follow the learned velocity field $v_\theta$ from $t=0$ to $t=1$. A numerical solver approximates this trajectory one step at a time. At position $x$ and time $t$, the vector $v_\theta(x,t)$ is tangent to the trajectory through $x$ at that time. Over a short interval, Euler approximates the trajectory by a straight segment with this velocity. A step of length $h$ gives

$$
x_{\mathrm E}=x+h\,v_\theta(x,t).
$$

Heun first takes that Euler step as a prediction. It evaluates the velocity again at $(x_{\mathrm E},t+h)$ and uses the mean of the two slopes to update $x$. We also test Tsit5, an adaptive Runge–Kutta solver that adjusts its step size using a local error estimate. We set the absolute and relative tolerances to $10^{-9}$.

We compare the model and target distributions using the sliced Wasserstein distance ($\mathrm{SW}_2$), a cheaper proxy for the Wasserstein distance.

~~~
<div class="fm-demo" id="fm-sampler" role="region" aria-label="ODE solver comparison">
  <div class="fm-controls">
    <label for="fm-field">Training coupling
      <select id="fm-field">
        <option value="independent">Independent</option>
        <option value="ot">Entropic OT</option>
      </select>
    </label>
    <label for="fm-method">ODE solver
      <select id="fm-method">
        <option value="euler">Euler</option>
        <option value="heun">Heun</option>
        <option value="reference">Tsit5</option>
      </select>
    </label>
    <label class="fm-budget" for="fm-budget">Euler and Heun steps
      <span class="fm-budget-slider">
        <input id="fm-budget" type="range" min="0" step="1">
        <span class="fm-budget-stops" aria-hidden="true"></span>
      </span>
    </label>
  </div>
  <div class="fm-panels fm-sampler-panels">
    <div class="fm-panel" id="fm-generated">
      <p>Generated samples</p>
      <div class="fm-plot" role="img" aria-label="Output of the selected sampler"></div>
    </div>
    <div class="fm-panel" id="fm-held-out">
      <p>Held-out moons</p>
      <div class="fm-plot" role="img" aria-label="Independent samples from the two moons distribution"></div>
    </div>
  </div>
  <div class="fm-legend">Noise <span class="fm-time-gradient" aria-hidden="true"></span> Data</div>
  <table class="fm-metrics" aria-label="Measured ODE solver errors">
    <thead><tr><th scope="col">ODE solver</th><th scope="col" aria-label="Velocity field evaluations">\(v_\theta\) evaluations</th><th scope="col" aria-label="Sliced Wasserstein distance">\(\mathrm{SW}_2\)</th></tr></thead>
  </table>
  <p class="fm-status" role="status">Loading sampler data…</p>
  <noscript>This figure requires JavaScript. You can rerun the experiment with the Pluto notebook linked at the end of the post.</noscript>
</div>
~~~

## Two ways to make sampling cheaper

### Change the coupling

When is one Euler step enough? If the velocity stays constant along a trajectory, the velocity at $t=0$ gives the displacement over the whole interval $[0,1]$. Can we encourage this behaviour by choosing the training pairs differently?

Changing the *coupling*, the joint law of $(X_0,X_1)$, changes which displacements $X_1-X_0$ enter the regression. For our Gaussian source, the exact population quadratic OT map gives straight trajectories with constant velocity, so a single Euler step suffices [[2]](#fm-ref-2).

This motivates using OT to choose the training pairs. We work with $2{,}048$ samples from each distribution and solve the resulting discrete OT problem with entropic regularisation at $\varepsilon=0.2$. Sinkhorn takes about $0.2$ seconds, and we draw pairs from the resulting plan throughout training [[3]](#fm-ref-3).

*Reflow* constructs a new coupling from a fitted field. We solve its ODE from $2{,}048$ fresh Gaussian points, then fit a second field on the straight segments from those points to their endpoints [[4]](#fm-ref-4). It is also possible to combine the two methods by first solving the entropic OT problem and then reflowing the resulting pairs.

~~~
<table class="fm-metrics" aria-label="Coupling comparison on two moons" aria-describedby="fm-coupling-cost">
  <thead class="fm-metrics-head"><tr><th scope="col">Coupling</th><th scope="col">One-step Euler \(\mathrm{SW}_2\) ↓</th><th scope="col">Training time (s)</th></tr></thead>
  <tbody>
    <tr><th scope="row">Independent coupling</th><td>0.6026</td><td>1.14</td></tr>
    <tr><th scope="row">Independent coupling + reflow</th><td>0.1243</td><td>3.27</td></tr>
    <tr><th scope="row">Entropic OT</th><td>0.0844</td><td>1.55</td></tr>
    <tr><th scope="row">Entropic OT + reflow</th><td>0.0738</td><td>3.31</td></tr>
  </tbody>
</table>
~~~

Entropic OT alone improved the one-step score more than reflow from the independent coupling and took less time. Combining the two gave the lowest score.

*Remark.* Generating the reflow pairs was nearly twice as fast with the OT field ($0.50$ versus $0.94$ seconds).

### Change the prediction target

Can a learnt field tell us where to land after a step of length $h$? Euler takes the initial velocity and keeps it fixed over the step. **Shortcut Models** give the network the step length as an input, so it can learn how far the trajectory actually moves. If $\Phi_{s,t}(x)$ is the flow map from time $s$ to time $t$, the velocity a step of length $h$ needs is the displacement divided by $h$ [[5]](#fm-ref-5) [[8]](#fm-ref-8).

$$
u_h(x,s)=\frac{\Phi_{s,s+h}(x)-x}{h}.
$$

Where do we get a target for a long step? Two consecutive steps of length $h$ reach the same endpoint as a single step of length $2h$. Adding their displacements and dividing by $2h$ gives

@@fm-equation
$$
u_{2h}(x,s)=\frac{u_h(x,s)+u_h(x+h\,u_h(x,s),s+h)}{2}.
$$
@@

During training, the model predicts both shorter steps and uses their average as the target for the longer step. The second prediction starts where the first one lands. Ordinary flow matching anchors this recursion at $h=0$, where $u_0(x,s)=v(x,s)$. At sampling time, setting $s=0$ and $h=1$ gives the full displacement in one prediction [[8]](#fm-ref-8).

**MeanFlow** applies the same consistency idea to an infinitesimal first step. Write $\bar v(x,s,t)=u_{t-s}(x,s)$ for the average velocity from $s$ to $t$. Hold $t$ fixed and move the start a little way along the trajectory. The remaining displacement changes by the negative of the displacement just travelled. Differentiating $(t-s)\bar v(x(s),s,t)=x(t)-x(s)$ with respect to $s$ gives

@@fm-equation
$$
v(x,s)=\bar v(x,s,t)
 -(t-s)\bigl(\partial_s\bar v(x,s,t)+D_x\bar v(x,s,t)\,v(x,s)\bigr).
$$
@@

The term in parentheses measures how the predicted average changes as the starting point and time move together. It is a Jacobian–vector product. During training, MeanFlow uses the conditional velocity from the training pair in this product, so it can learn from scratch [[6]](#fm-ref-6).

**$\alpha$-Flow** lets the first step cover any fraction $\alpha$ of the interval, with the split at $s+\alpha(t-s)$. Choosing $\alpha=\tfrac12$ and using model predictions for both parts recovers Shortcut Models. A vanishing first step recovers the MeanFlow update in the limit. The training schedule uses the conditional velocity along the straight training segment for the first part and the model's prediction for the second. It starts at $\alpha=1$ and gradually reduces $\alpha$ to zero [[9]](#fm-ref-9).

**Endpoint distillation** learns the displacement from noise to data using pairs generated by a fitted teacher [[10]](#fm-ref-10). Reflow uses the same kind of teacher pairs to supervise a velocity field at times throughout each straight segment. The endpoint student gives the full displacement from time zero. To recover intermediate states along the teacher's trajectory, we still need to integrate the teacher. These methods move work from sampling to training. Teacher solves and student fitting are paid once and shared across later draws. MeanFlow and $\alpha$-Flow train without a separate teacher, with extra work in the training objective.

### Results

We draw training pairs from the same entropic OT plan for the Euler field, Shortcut Models, MeanFlow and $\alpha$-Flow. The distilled student learns from $2{,}048$ endpoint pairs generated by the Euler field's ODE. All fits use the same hidden-layer architecture and $6{,}000$ Adam updates in Lux. At generation time, each method uses one network evaluation per sample [[7]](#fm-ref-7).

~~~
<table class="fm-metrics" aria-label="One-step results on two moons">
  <thead class="fm-metrics-head"><tr><th scope="col">One-step method</th><th scope="col" aria-label="Sliced Wasserstein distance, lower is better">\(\mathrm{SW}_2\) ↓</th><th scope="col">Training time (s)</th><th scope="col">Generation time (ms)</th></tr></thead>
  <tbody>
    <tr><th scope="row">Euler</th><td>0.0654</td><td>1.44</td><td>24.84</td></tr>
    <tr><th scope="row">Distillation</th><td>0.0436</td><td>3.10</td><td>25.75</td></tr>
    <tr><th scope="row">Shortcut</th><td>0.0509</td><td>1.67</td><td>26.19</td></tr>
    <tr><th scope="row">MeanFlow</th><td>0.0484</td><td>4.67</td><td>25.23</td></tr>
    <tr><th scope="row">\(\alpha\)-Flow</th><td>0.0434</td><td>3.09</td><td>26.82</td></tr>
  </tbody>
</table>
~~~

Scores and generation times use batches of $16{,}384$ samples.

On this toy example, we find that changing the coupling makes a large difference but the one-step methods are less convincing. The ~~~<a id="fm-notebook" href="/assets/blog/flow-matching/flow-matching-notebook.jl" download="flow-matching-notebook.jl">Pluto notebook</a>~~~ lets you experiment with these different methods.

## References

~~~
<ol class="fm-references">
  <li id="fm-ref-1">Lipman et al. <a href="https://arxiv.org/abs/2210.02747">Flow Matching for Generative Modeling</a>. ICLR 2023.</li>
  <li id="fm-ref-2">Lipman et al. <a href="https://arxiv.org/abs/2412.06264">Flow Matching Guide and Code</a>. 2024.</li>
  <li id="fm-ref-3">Cuturi. <a href="https://arxiv.org/abs/1306.0895">Sinkhorn Distances: Lightspeed Computation of Optimal Transport</a>. NeurIPS 2013.</li>
  <li id="fm-ref-4">Liu, Gong and Liu. <a href="https://arxiv.org/abs/2209.03003">Flow Straight and Fast</a>. ICLR 2023.</li>
  <li id="fm-ref-5">Boffi, Albergo and Vanden-Eijnden. <a href="https://arxiv.org/abs/2406.07507">Flow Map Matching</a>. 2024.</li>
  <li id="fm-ref-6">Geng et al. <a href="https://arxiv.org/abs/2505.13447">Mean Flows for One-step Generative Modeling</a>. NeurIPS 2025. See also the <a href="https://www.cs.cmu.edu/~csd-phd-blog/2026/mean-flows/">authors' blog</a>.</li>
  <li id="fm-ref-7">Pal. <a href="https://doi.org/10.5281/zenodo.7808904">Lux: Explicit Parameterization of Deep Neural Networks in Julia</a>. Zenodo, 2023.</li>
  <li id="fm-ref-8">Frans et al. <a href="https://arxiv.org/abs/2410.12557">One Step Diffusion via Shortcut Models</a>. ICLR 2025.</li>
  <li id="fm-ref-9">Zhang et al. <a href="https://arxiv.org/abs/2510.20771">AlphaFlow: Understanding and Improving MeanFlow Models</a>. 2025.</li>
  <li id="fm-ref-10">Luhman and Luhman. <a href="https://arxiv.org/abs/2101.02388">Knowledge Distillation in Iterative Generative Models for Improved Sampling Speed</a>. 2021.</li>
</ol>
~~~

@@
