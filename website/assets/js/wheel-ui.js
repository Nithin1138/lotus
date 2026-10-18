// Shared wheel surfaces for the hero demo and the file-type showcase.
// Geometry mirrors DropWheel.Keycap in DropDial/work/DropDial/FloatingWheel.cs.
(() => {
  "use strict";
  const SVG = "http://www.w3.org/2000/svg";
  const CENTER = 190, OUTER = 172, INNER = 65;
  const polar = (radius, angle) => [CENTER + radius * Math.cos(angle), CENTER + radius * Math.sin(angle)];

  function node(name, attrs, parent) {
    const el = document.createElementNS(SVG, name);
    for (const [key, value] of Object.entries(attrs)) el.setAttribute(key, value);
    parent.appendChild(el);
    return el;
  }

  function keycap(index, count) {
    const angle = -Math.PI / 2 + index * 2 * Math.PI / count;
    const half = Math.PI / count, start = angle - half + .016, end = angle + half - .016;
    const outerCorner = 16, innerCorner = 10;
    const outerInset = outerCorner / OUTER, innerInset = innerCorner / INNER;
    const p = (r, a) => polar(r, a).join(" ");
    return `M${p(INNER + innerCorner, start)}L${p(OUTER - outerCorner, start)}`
      + `Q${p(OUTER, start)} ${p(OUTER, start + outerInset)}`
      + `A${OUTER} ${OUTER} 0 ${end - start - 2 * outerInset > Math.PI ? 1 : 0} 1 ${p(OUTER, end - outerInset)}`
      + `Q${p(OUTER, end)} ${p(OUTER - outerCorner, end)}`
      + `L${p(INNER + innerCorner, end)}Q${p(INNER, end)} ${p(INNER, end - innerInset)}`
      + `A${INNER} ${INNER} 0 ${end - start - 2 * innerInset > Math.PI ? 1 : 0} 0 ${p(INNER, start + innerInset)}`
      + `Q${p(INNER, start)} ${p(INNER + innerCorner, start)}Z`;
  }

  function base(svg) {
    svg.replaceChildren();
    node("circle", { class: "disk", cx: CENTER, cy: CENTER, r: 180 }, svg);
    // Draw all sidewalls underneath every face so neighbouring keys never cover one another.
    const sides = node("g", { class: "wheel-sides", "aria-hidden": "true" }, svg);
    const faces = node("g", { class: "wheel-faces" }, svg);
    return { sides, faces };
  }

  function petal(layers, index, count, attrs = {}) {
    const d = keycap(index, count);
    const side = node("path", { class: "petal-side", d, transform: "translate(0 4)", "pointer-events": "none" }, layers.sides);
    const face = node("path", { ...attrs, class: "petal", d }, layers.faces);
    return { side, face };
  }

  function hub(svg) {
    node("circle", { class: "hub-side", cx: CENTER, cy: CENTER + 4, r: 56, "aria-hidden": "true", "pointer-events": "none" }, svg);
    node("circle", { class: "hub", cx: CENTER, cy: CENTER, r: 56 }, svg);
  }

  function select(svg, index) {
    // `on` changes both the flat face and its raised edge, without moving the hit target.
    [".petal", ".petal-side", ".label"].forEach(selector => {
      [...svg.querySelectorAll(selector)].forEach((el, i) => el.classList.toggle("on", i === index));
    });
  }

  function hit(svg, x, y) {
    // x/y are viewBox coordinates based on the layout size, not the opening animation.
    // Use the actual path fill: rounded corners, gaps and the central dead zone are not selectable.
    if (Math.hypot(x - CENTER, y - CENTER) <= INNER) return -1;
    const point = new DOMPoint(x, y);
    return [...svg.querySelectorAll(".petal")].findIndex(path => path.isPointInFill(point));
  }

  window.ZD_WHEEL = { CENTER, OUTER, INNER, polar, keycap, base, petal, hub, select, hit };
})();
