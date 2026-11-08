# A variable call's other answers

Read this when a `set_app_variables`, `list_app_variables` or
`remove_app_variables` answer is anything but a plain success, or when an app
still reports a variable missing. The skill's **Variables** section says what
variables are and what to tell the user before setting one.

Things to relay to the user in plain terms:

- **Stored, but the push was refused.** On a container app one of whose data
  links no longer holds, the answer's `Delivery:` line says the values were
  stored and the push refused, naming `link_invalid` or
  `link_source_missing`. Nothing reaches the running app: unlink that link
  (`unlink_app_data`), or have the source's owner fix it, and the app's next
  deploy delivers the values.
- `variables_invalid`: the message names the rule its name or value broke,
  or a name given twice, and, when the call names two or more variables,
  the item. Fix that item and send the whole call again: nothing was
  stored or removed.
- `variables_limit_reached`: the call would take the app past the most
  variables it may hold. Remove some with `remove_app_variables`, or set
  fewer, then call again.
- `encryption_key_missing`, `encryption_key_invalid`, or on a container app
  `platform_key_missing`: an admin-side precondition, not an argument
  problem. Relay it and stop: only a platform admin can fix any of them
  (the skill's **Asking a platform admin**), and retrying will not help.
- `link_invalid` or `link_source_missing` from `remove_app_variables`: one of
  the app's data links is no longer valid, and nothing was removed. Unlink it
  (`unlink_app_data`), or have the source's owner fix it, then remove again.
- **A removal whose host upload failed** (on a container app, and the answer
  says so): the removal stands, but the running instance keeps the old
  values until it next restarts. Relay that and offer `restart_app`;
  `get_platform_docs` section 16 (What the tools do in detail), its
  Variables and Connections item, has the detail.
- **A removal that stopped part-way** (the answer names what was removed
  and what was not): the names it removed are gone; call
  `remove_app_variables` again for the rest. On a container app the answer
  adds that its host was not uploaded again, so the running instance keeps
  the old values until it next restarts: relay that too and offer
  `restart_app`.
- **"I set it and the app still reports it missing."** Check
  `list_app_variables`: a set name that looks like a typo of a declared name
  nobody has set carries a suggestion naming the declared one, and a hidden
  variable reported `pending delivery` has not reached the deployed app yet
  (the next deploy delivers it with the app, so it is there from that
  deploy's first request).
- **A hidden variable that reads `needs a value`** is a secret no deploy can
  deliver, for one of two causes: it was delivered to an app's script before
  the platform's one earlier move of every app onto a new script, and stayed
  behind on the old one; or the platform still holds it, pending delivery,
  sealed under an encryption key the platform no longer has (a never-deployed
  app's secrets can meet this too). It holds no value and counts as missing.
  The owner sets it again with `set_app_variables`, or, for the second cause,
  the platform's operator puts the earlier key back; `app_status` names every
  such variable until then (contract §2.3).
- `app_status` names a REQUIRED declared variable that has no value, on its
  own line.
