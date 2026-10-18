// Geometry and surface regressions for the rounded wheels.
// Run in the page console like demo-tests.js. Results: window.__wheelUiTestResults.
(() => {
  "use strict";
  const ui = window.ZD_WHEEL, results = [];
  const expect = (value, message) => { if (!value) throw new Error(message); };
  const test = (name, fn) => {
    try { fn(); results.push("PASS " + name); }
    catch (e) { results.push("FAIL " + name + " :: " + e.message); }
  };
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 380 380");
  svg.setAttribute("aria-hidden", "true");
  svg.style.cssText = "position:absolute;left:-1000px;width:380px;height:380px";
  document.body.appendChild(svg);
  function draw(n) {
    const layers = ui.base(svg);
    for (let i = 0; i < n; i++) ui.petal(layers, i, n);
    ui.hub(svg);
  }
  try {
    test("radii match the updated desktop wheel", () => {
      expect(ui.CENTER === 190 && ui.OUTER === 172 && ui.INNER === 65, "geometry constants changed");
    });
    test("every menu size has rounded faces and raised, non-interactive sidewalls", () => {
      for (const n of [0, 1, 4, 6, 7, 8, 9, 10]) {
        draw(n);
        const faces = [...svg.querySelectorAll('.petal')], sides = [...svg.querySelectorAll('.petal-side')];
        expect(faces.length === n && sides.length === n, "wrong count for " + n);
        faces.forEach((face, i) => {
          const d = face.getAttribute('d');
          expect((d.match(/Q/g) || []).length === 4, "not four rounded junctions");
          expect(sides[i].getAttribute('d') === d, "sidewall does not match face");
          expect(sides[i].getAttribute('transform') === 'translate(0 4)' && sides[i].getAttribute('pointer-events') === 'none', "sidewall can intercept input");
        });
        expect(svg.querySelector('.hub').getAttribute('r') === '56', "hub radius");
      }
    });
    test("petal centres select the right option for every menu size", () => {
      for (const n of [1, 4, 6, 7, 8, 9, 10]) {
        draw(n);
        for (let i = 0; i < n; i++) {
          const p = ui.polar(126, -Math.PI / 2 + i * 2 * Math.PI / n);
          expect(ui.hit(svg, ...p) === i, `missed petal ${i} of ${n}`);
        }
      }
    });
    test("centre, larger dead zone and outside edge are never selected", () => {
      for (const n of [0, 1, 4, 8, 9]) {
        draw(n);
        for (const r of [0, 55, 60, 64, 65, 175, 182, 200]) {
          expect(ui.hit(svg, ...ui.polar(r, -Math.PI / 2)) === -1, `selected radius ${r} for ${n}`);
        }
      }
    });
    test("gaps and rounded-off outer corners are not selectable", () => {
      for (const n of [1, 4, 6, 7, 8, 9]) {
        draw(n);
        for (let i = 0; i < n; i++) {
          const start = -Math.PI / 2 + (i - .5) * 2 * Math.PI / n;
          expect(ui.hit(svg, ...ui.polar(119, start)) === -1, `gap ${i} of ${n}`);
          expect(ui.hit(svg, ...ui.polar(171, start + .026)) === -1, `rounded corner ${i} of ${n}`);
        }
      }
    });
    test("highlight updates the face and sidewall together and clears cleanly", () => {
      draw(8);
      ui.select(svg, 3);
      expect(svg.querySelectorAll('.petal.on').length === 1 && svg.querySelectorAll('.petal-side.on').length === 1, "selection counts");
      expect([...svg.querySelectorAll('.petal')][3].classList.contains('on'), "wrong face");
      expect([...svg.querySelectorAll('.petal-side')][3].classList.contains('on'), "wrong sidewall");
      ui.select(svg, -1);
      expect(!svg.querySelector('.on'), "highlight remained");
    });
  } finally {
    svg.remove();
  }
  const failures = results.filter(r => r.startsWith('FAIL'));
  console.log(results.join('\n'));
  window.__wheelUiTestResults = { passed: results.length - failures.length, total: results.length, failures };
  return window.__wheelUiTestResults;
})();
