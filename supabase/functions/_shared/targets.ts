// The allowlist of daily targets (docs/PLAN.md Phase 4). Phase 3 picks one at random;
// Phase 4 lets Claude pick one that fits where the user is.

export interface Target {
  key: string;
  label: string;
  hint: string;
}

export const TARGETS: readonly Target[] = [
  { key: "tree", label: "a tree", hint: "Any tree counts: street trees, parks, gardens." },
  { key: "bench", label: "a bench", hint: "Parks, bus stops and squares usually have one." },
  { key: "bus_stop", label: "a bus stop", hint: "The sign or the shelter is enough." },
  { key: "street_sign", label: "a street sign", hint: "A street name sign on a corner works." },
  { key: "post_box", label: "a post box", hint: "Look near shops and street corners." },
  { key: "bicycle", label: "a bicycle", hint: "Bike racks, parked bikes or a bike share dock." },
  { key: "lamp_post", label: "a lamp post", hint: "Any street light will do." },
  { key: "statue_or_monument", label: "a statue or monument", hint: "Squares and parks are good places to look." },
  { key: "building_entrance", label: "a building entrance", hint: "A front door or the entrance to a shop or office." },
  { key: "shop_front", label: "a shop front", hint: "Any shop window or sign." },
  { key: "traffic_light", label: "a traffic light", hint: "Crossings and junctions have them." },
  { key: "park_gate", label: "a park gate", hint: "The entrance to a park or garden." },
  { key: "plant_pot", label: "a plant pot", hint: "Doorsteps, balconies and cafés often have one." },
];

/** A random target, avoiding the ones used recently when possible. */
export function pickRandomTarget(recentKeys: ReadonlySet<string>, random: () => number = Math.random): Target {
  const fresh = TARGETS.filter((t) => !recentKeys.has(t.key));
  const pool = fresh.length > 0 ? fresh : TARGETS;
  return pool[Math.floor(random() * pool.length) % pool.length];
}
