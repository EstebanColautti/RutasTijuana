const { test } = require('node:test');
const assert = require('node:assert/strict');
const model = require('../preview/catalog.js');
const sample = () => ({ schemaVersion: 1, groups: [{ id: 'g', name: 'Ejemplo' }], features: [
  { id: 'r', name: 'Recorrido', groupID: 'g', kind: 'route', color: '#2476e8', geometry: { type: 'LineString', coordinates: [[0, 0], [2, 0]] } }
] });
test('search normalizes accents and keeps group filters', () => {
  const data = model.parse(JSON.stringify(sample()));
  assert.equal(model.search(data, 'recórrido EJEMPLO').length, 1);
  assert.equal(model.search(data, '', 'missing').length, 0);
});
test('nearest distance uses segments, not only vertices', () => {
  const feature = sample().features[0];
  assert.ok(Math.abs(model.nearby(feature, [1, 1]) - 111195) < 2);
  assert.ok(model.nearby(feature, [1, 0]) < .01);
});
test('duplicate IDs and inverted axes are rejected', () => {
  let data = sample(); data.features.push(data.features[0]);
  assert.throws(() => model.parse(JSON.stringify(data)));
  data = sample(); data.features[0].geometry.coordinates = [[32, -117], [33, -117]];
  assert.throws(() => model.parse(JSON.stringify(data)));
});
test('areas never become nearby boarding candidates', () => {
  const feature = { ...sample().features[0], kind: 'area' };
  assert.equal(model.nearby(feature, [1, 0]), null);
});
