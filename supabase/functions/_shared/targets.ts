// The allowlist of daily targets: things Apple's on-device image classifier recognises
// (docs/decisions/004). Each key must have accepted labels in TargetLabels.accepted in
// ios/App/Services/CheckIn/PhotoChecks.swift, which is what the phone checks the photo against.

export interface Target {
  key: string;
  label: string;
  hint: string;
}

export const TARGETS: readonly Target[] = [
  { key: "tree", label: "a tree", hint: "Any tree counts: street trees, parks, gardens." },
  { key: "bench", label: "a bench", hint: "Parks, bus stops and squares usually have one." },
  { key: "street_sign", label: "a street sign", hint: "A street name sign on a corner works." },
  { key: "post_box", label: "a post box", hint: "Look near shops and street corners." },
  { key: "bicycle", label: "a bicycle", hint: "Bike racks, parked bikes or a bike share dock." },
  { key: "lamp_post", label: "a lamp post", hint: "Any street light will do." },
  { key: "statue_or_monument", label: "a statue or monument", hint: "Squares and parks are good places to look." },
  { key: "building_entrance", label: "a front door", hint: "The door of a house, shop or office." },
  { key: "shop_front", label: "a shop front", hint: "Any shop window or sign." },
  { key: "traffic_light", label: "a traffic light", hint: "Crossings and junctions have them." },
  { key: "fence", label: "a fence", hint: "Garden fences, park railings and building-site fences all count." },
  { key: "plant", label: "a plant", hint: "A potted plant, a hedge or a flower bed." },
];

/** A random target, avoiding the ones used recently when possible. */
export function pickRandomTarget(recentKeys: ReadonlySet<string>, random: () => number = Math.random): Target {
  const fresh = TARGETS.filter((t) => !recentKeys.has(t.key));
  const pool = fresh.length > 0 ? fresh : TARGETS;
  return pool[Math.floor(random() * pool.length) % pool.length];
}
