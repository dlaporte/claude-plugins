---
name: passes
description: A fixture for scripts/test-check-contract-sections.sh, not a skill. Every line below the heading must pass, alone and beside the fails fixture.
---

# Lines that must PASS

- Every id valid: `sections: ["1", "1.1", "1.2", "1.3", "2", "3", "4", "4.1", "5"]`.
- One valid id, and the last section: `sections: ["2.3"]`, `sections: ["7"]`.
- No space after the colon or the commas: `sections:["2","5","6"]`.
- An id after the literal is not in it: `sections: ["2", "4.1"]` (add `"9"` later).
- A list with no sections key is not checked: `["9"]`.
- A section sign in prose is not checked: §8 and §9.
- An empty literal names no section: `sections: []`.
