#!/usr/bin/env node

/**
 * Fetches all Plane and Phenomenon cards from Scryfall and writes a trimmed
 * PlaneCards.json used by the iOS app, React Native app, and Cloud Functions.
 *
 * Usage:  node scripts/fetch-plane-cards.js
 */

const fs = require("fs");
const path = require("path");

const SEARCH_URL =
  "https://api.scryfall.com/cards/search?q=t%3Aplane+or+t%3Aphenomenon&unique=prints&order=name";

async function fetchAllPages(url) {
  const cards = [];
  let nextUrl = url;

  while (nextUrl) {
    console.log(`Fetching ${nextUrl} ...`);
    const res = await fetch(nextUrl);
    if (!res.ok) throw new Error(`Scryfall error: ${res.status}`);
    const json = await res.json();
    cards.push(...json.data);
    nextUrl = json.has_more ? json.next_page : null;

    // Scryfall asks for 50-100ms between requests
    if (nextUrl) await new Promise((r) => setTimeout(r, 100));
  }

  return cards;
}

function pickBestImage(card) {
  // Prefer card_faces[0] image for planar cards (some are double-faced)
  if (card.card_faces && card.card_faces[0]?.image_uris) {
    return card.card_faces[0].image_uris.normal;
  }
  if (card.image_uris) {
    return card.image_uris.normal;
  }
  return null;
}

async function main() {
  const raw = await fetchAllPages(SEARCH_URL);

  // De-duplicate by oracle_id (keep first printing)
  const seen = new Set();
  const unique = [];
  for (const card of raw) {
    if (seen.has(card.oracle_id)) continue;
    seen.add(card.oracle_id);
    unique.push(card);
  }

  const planes = unique.map((c) => ({
    id: c.oracle_id,
    name: c.name,
    type_line: c.type_line,
    oracle_text: c.oracle_text || "",
    image_uri: pickBestImage(c),
    is_phenomenon: c.type_line === "Phenomenon",
  }));

  planes.sort((a, b) => a.name.localeCompare(b.name));

  const json = JSON.stringify(planes, null, 2);

  const destinations = [
    "Treachery-iOS/Treachery-iOS/Treachery-iOS/Resources/PlaneCards.json",
    "Treachery/src/assets/PlaneCards.json",
    "functions/planeCards.json",
  ];

  const root = path.resolve(__dirname, "..");
  for (const dest of destinations) {
    const full = path.join(root, dest);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, json, "utf-8");
    console.log(`Wrote ${planes.length} cards to ${dest}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
