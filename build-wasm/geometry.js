/* geometry.js -- an invariant as a region of the plane.
 *
 * Projects a conjunction of linear constraints onto two chosen variables and
 * turns the result into a convex polygon. Loaded by index.html, which draws the
 * polygon; nothing here touches the DOM or the page's state, so it can be
 * exercised on its own (see the note on testing at the bottom).
 *
 * ## What comes in
 *
 * Constraints as `--print-invariants-to-json` writes them:
 *
 *     {"op": "<=", "terms": [["1", "y"]], "const": "9"}        <=>  y <= 9
 *
 * reading `<terms> <op> <const>`, with `op` one of "<=", "<", "=", "!=" or the
 * nullary "true" / "false", which carry no other keys. Nothing here needs the
 * analyzer's help beyond that document, which is why the Shapes feature needed
 * no change to the wasm build.
 *
 * ## How a constraint is carried
 *
 *     { c: Map<var, BigInt>, k: BigInt, op }      meaning   Σ c·v + k  op  0
 *
 * The constant sits on the same side as the terms, so every rewrite below is one
 * rule rather than one per side. The JSON puts it on the right, so it crosses
 * over negated on the way in.
 *
 * **Coefficients are BigInt.** Fourier-Motzkin multiplies them together, and the
 * products outgrow a double long before these programs outgrow the playground;
 * a silently rounded coefficient would draw a region that is not the invariant.
 * Floats appear only at the last step, where a polygon is measured in pixels.
 *
 * ## The two steps
 *
 * **Projection** eliminates every variable but the two being plotted. An
 * equality mentioning the victim is used to substitute it away, which is exact
 * and yields one constraint per survivor. Failing that, Fourier-Motzkin pairs
 * each upper bound with each lower bound, which is |upper| x |lower|
 * constraints -- the combinatorial step, and the reason an equality is preferred
 * whenever one is to hand.
 *
 * **Clipping** intersects the half-planes. Clipping a convex polygon by a
 * half-plane leaves it convex, so one Sutherland-Hodgman pass per constraint is
 * enough and the result stays a simple ring.
 *
 * ## Where this is deliberately approximate
 *
 * A disequation is dropped, by `project` when it mentions an eliminated
 * variable and by `polygon` when it survives to the end. It excludes a line,
 * which no convex polygon can express, and dropping is the only safe direction:
 * clipping on it instead -- treating `!=` as `<=` -- would cut away half the
 * region and show fewer states than the invariant allows, which is the one
 * error a picture must not make. What dropping loses is a set of zero area, and
 * `dropped.ne` counts it so the caller can say so.
 *
 * Elimination is also abandoned if it runs away (`dropped.gaveUp`), leaving the
 * constraints gathered so far -- again a superset, never a subset.
 *
 * Both are over-approximations: the region drawn always contains the real one.
 *
 * ## Testing
 *
 * This file assigns one global and has no imports, so Node can load it as-is
 * and call `CrabGeom.*` -- which is how the projection was checked against cases
 * with a known answer: `x<=z and z<=y` must give the `x<=y` triangle,
 * `s=2t and t=i` the segment `s=2i`, `x<=z and z<=x-1` the empty region.
 */

(function (root) {
  'use strict';

  const OPS = { LE: '<=', LT: '<', EQ: '=', NE: '!=' };

  function gcdBig(a, b) {
    a = a < 0n ? -a : a; b = b < 0n ? -b : b;
    while (b) { const t = a % b; a = b; b = t; }
    return a;
  }

  /* Divide through by the GCD of everything in the constraint, which keeps the
     BigInts small across repeated elimination. Safe for every op: the divisor is
     positive, so no inequality turns over. */
  function reduce(con) {
    let g = 0n;
    for (const v of con.c.values()) g = gcdBig(g, v);
    g = gcdBig(g, con.k);
    if (g <= 1n) return con;
    const c = new Map();
    for (const [v, a] of con.c) if (a / g !== 0n) c.set(v, a / g);
    return { c, k: con.k / g, op: con.op };
  }

  /* A JSON constraint. Null for a tautology, which constrains nothing. */
  function fromJson(j) {
    if (j.op === 'true') return null;
    if (j.op === 'false') return { c: new Map(), k: 1n, op: OPS.LE };   // 1 <= 0
    const c = new Map();
    for (const [coef, v] of (j.terms || [])) {
      const a = BigInt(coef);
      if (a !== 0n) c.set(v, (c.get(v) || 0n) + a);
    }
    return reduce({ c, k: -BigInt(j.const ?? '0'), op: j.op });
  }

  /* f1·con1 + f2·con2, with f1 and f2 positive so no inequality turns over. */
  function combine(f1, con1, f2, con2) {
    const c = new Map();
    for (const [v, a] of con1.c) c.set(v, (c.get(v) || 0n) + f1 * a);
    if (con2) for (const [v, a] of con2.c) c.set(v, (c.get(v) || 0n) + f2 * a);
    for (const [v, a] of [...c]) if (a === 0n) c.delete(v);
    const k = f1 * con1.k + (con2 ? f2 * con2.k : 0n);
    const strict = con1.op === OPS.LT || (con2 && con2.op === OPS.LT);
    return reduce({ c, k, op: strict ? OPS.LT : OPS.LE });
  }

  /* Eliminate one variable from a conjunction.

     Substitution, when an equality mentions z: orient it so z's coefficient `a`
     is positive (an equality may be negated freely), leaving z = -P/a; then each
     other constraint `c·z + R op 0`, multiplied by a > 0, becomes
     `a·R - c·P op 0`.

     Otherwise Fourier-Motzkin: from `a·z + P <= 0` (a > 0) and `-b·z + Q <= 0`
     (b > 0) come z <= -P/a and z >= Q/b, hence Q/b <= -P/a, hence
     `a·Q + b·P <= 0`. */
  function eliminate(cons, z, dropped) {
    const eq = cons.find(c => c.op === OPS.EQ && (c.c.get(z) || 0n) !== 0n);
    if (eq) {
      const a0 = eq.c.get(z);
      const e = a0 > 0n ? eq : combine(-1n, eq, 0n, null);
      const a = e.c.get(z);
      const P = combine(1n, e, 0n, null); P.c.delete(z);
      const out = [];
      for (const con of cons) {
        if (con === eq) continue;
        const cz = con.c.get(z) || 0n;
        if (cz === 0n) { out.push(con); continue; }
        if (con.op === OPS.NE) { dropped.ne++; continue; }
        const R = combine(1n, con, 0n, null); R.c.delete(z);
        const comb = combine(a, R, -cz, P);
        comb.op = con.op === OPS.EQ ? OPS.EQ
                : (con.op === OPS.LT ? OPS.LT : OPS.LE);
        out.push(reduce(comb));
      }
      return out;
    }
    const upper = [], lower = [], rest = [];
    for (const con of cons) {
      const a = con.c.get(z) || 0n;
      if (a === 0n) { rest.push(con); continue; }
      if (con.op === OPS.NE) { dropped.ne++; continue; }
      (a > 0n ? upper : lower).push(con);
    }
    const out = rest;
    for (const u of upper) {
      const a = u.c.get(z);
      for (const l of lower) {
        const b = -l.c.get(z);
        const P = combine(1n, u, 0n, null); P.c.delete(z);
        const Q = combine(1n, l, 0n, null); Q.c.delete(z);
        out.push(combine(a, Q, b, P));
      }
    }
    // Bounded on one side only: z's constraints say nothing about the others.
    return out;
  }

  /* Project a conjunction onto {x, y}. */
  function project(cons, x, y) {
    const dropped = { ne: 0, gaveUp: false };
    const vars = new Set();
    for (const con of cons) for (const v of con.c.keys()) vars.add(v);
    vars.delete(x); vars.delete(y);
    let cur = cons;
    // Fewest appearances first: the elimination that pairs least blows up least.
    const order = [...vars].sort((a, b) =>
      cur.filter(c => c.c.has(a)).length - cur.filter(c => c.c.has(b)).length);
    for (const z of order) {
      cur = eliminate(cur, z, dropped);
      if (cur.length > 4000) { dropped.gaveUp = true; break; }
    }
    return { cons: cur, dropped };
  }

  const EPS = 1e-9;

  /* Clip a convex polygon by the half-plane A·x + B·y + k <= 0. */
  function clipHalf(poly, A, B, k) {
    const f = p => A * p[0] + B * p[1] + k;
    const out = [];
    for (let i = 0; i < poly.length; i++) {
      const p = poly[i], q = poly[(i + 1) % poly.length];
      const fp = f(p), fq = f(q);
      if (fp <= EPS) out.push(p);
      if ((fp > EPS && fq < -EPS) || (fp < -EPS && fq > EPS)) {
        const t = fp / (fp - fq);
        out.push([p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])]);
      }
    }
    return out;
  }

  /* Drop repeated vertices. A region pinned to a line or a point leaves the
     clipper with its vertices doubled: harmless to draw, but it makes the vertex
     list a poor description of the shape. */
  function dedupe(poly) {
    const out = [];
    for (const p of poly) {
      const q = out[out.length - 1];
      if (q && Math.abs(p[0] - q[0]) < 1e-7 && Math.abs(p[1] - q[1]) < 1e-7) continue;
      out.push(p);
    }
    while (out.length > 1) {
      const a = out[0], b = out[out.length - 1];
      if (Math.abs(a[0] - b[0]) < 1e-7 && Math.abs(a[1] - b[1]) < 1e-7) out.pop();
      else break;
    }
    return out;
  }

  /* The region as a polygon, clipped to `box`.

     The box is not cosmetic: an unbounded region has no polygon, so one is
     imposed. A vertex landing on the box is the region running off rather than a
     corner of it, which is what lets the caller say the region continues instead
     of drawing an edge that is not there. */
  function polygon(cons2, x, y, box, dropped) {
    let poly = [[box.lo, box.lo], [box.hi, box.lo], [box.hi, box.hi], [box.lo, box.hi]];
    for (const con of cons2) {
      if (con.op === OPS.NE) { dropped.ne++; continue; }   // see the header
      const A = Number(con.c.get(x) || 0n), B = Number(con.c.get(y) || 0n);
      const k = Number(con.k);
      if (A === 0 && B === 0) {
        const bad = con.op === OPS.EQ ? k !== 0 : k > 0;
        if (bad) return [];                   // a false constant: nothing holds
        continue;
      }
      poly = clipHalf(poly, A, B, k);
      if (con.op === OPS.EQ) poly = clipHalf(poly, -A, -B, -k);
      if (!poly.length) return [];
    }
    return dedupe(poly);
  }

  /* A box big enough that the only thing it cuts is genuine unboundedness. */
  function box(cons2, x, y) {
    let mag = 10;
    for (const con of cons2) {
      const A = Number(con.c.get(x) || 0n), B = Number(con.c.get(y) || 0n);
      const k = Math.abs(Number(con.k));
      if (A) mag = Math.max(mag, k / Math.abs(A));
      if (B) mag = Math.max(mag, k / Math.abs(B));
    }
    const hi = Math.max(10, mag * 2 + 5);
    return { lo: -hi, hi };
  }

  root.CrabGeom = { OPS, fromJson, project, polygon, box };
})(typeof globalThis !== 'undefined' ? globalThis : this);
