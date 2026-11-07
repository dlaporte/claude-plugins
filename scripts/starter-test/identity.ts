// A copy of the platform's function scaffold's app/identity.ts, which
// registration commits beside the starter (SKILL.md step 5) and the starter
// imports. Copied because this repository's CI has no platform checkout:
// inno-platform's ci/fixtures/template/scaffold/function/app/identity.ts at
// the release scripts/platform-compat.json pins, unchanged below this header:
// scripts/check-scaffold-copy.sh holds it to that record's shipped hash.

// The caller, or null when the request carries no identity (the platform's
// health probe, or a local run without the headers). The same contract as the
// template's lib/storage.js currentUser, which function apps do not carry.
// Never default the absence into a value: code that needs a person handles
// null first. `subject` is the caller's identity provider ID, null when the
// header is empty or missing; a subject alone never makes a user.
export interface CurrentUserResult {
  email: string;
  groups: string[];
  member: boolean;
  subject: string | null;
}

export function currentUser(headers: Headers): CurrentUserResult | null {
  const email = (headers.get("x-forwarded-user") ?? "").trim();
  if (!email) return null;
  const groups = (headers.get("x-forwarded-groups") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  const subject = (headers.get("x-forwarded-subject") ?? "").trim() || null;
  return { email, groups, member: groups.some((g) => g.endsWith("-users")), subject };
}
