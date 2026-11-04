# Deleting an account on request

The iPhone app deletes an account from Profile, through the `deleteAccount`
callable. The web and Android apps can't yet, so players on them ask by email.
`functions/scripts/delete-account.js` deletes the account they ask about with
the iPhone app's own steps (`deleteAccountFor` in
`functions/src/callables/account.js`):

- it takes the account out of the lobbies it is waiting in;
- it renames its seats in past games "Deleted player";
- it takes it off friends' lists and deletes its friend requests;
- it deletes its profile, including email, phone number and push token;
- it deletes its sign-in account.

It never deletes an account that is in, or hosts, a game in progress. It is a
dry run unless you pass `--apply`.

## Before you start

Run it from `functions/` with its dependencies installed (`npm ci`), as a
Google account that is an Owner of `treachery-71922` (or has its Firebase
Authentication Admin, Cloud Datastore User and Service Usage Consumer roles):

```sh
gcloud auth application-default login
gcloud auth application-default set-quota-project treachery-71922
```

Don't skip the second command. Firebase Auth needs a quota project for
requests made with your own Google account's credentials; without one, the
script's first lookup fails and it exits 3.

You'll type the requester's email address or phone number. So that your shell
doesn't keep them in its history, run `unset HISTFILE` first in the terminal
you use: zsh and bash then save nothing from it. Once the dry run has printed
the account's uid, use that instead.

## 1. Send the code, and wait until it's set

Reply to the request with a code for them to set as their display name: a
word and four digits, like `Lantern-4821`, new for every request. For example:

> To confirm the account is yours, open Treachery on the web or Android, go
> to Profile, tap Edit, change your display name to exactly Lantern-4821 and
> tap Save. Then reply to this email. If you play as a guest, don't sign out
> until we've confirmed it's yours.

The script compares the name exactly, so case and spaces inside it count
(the apps trim spaces from the ends). Wait until they reply that it is set.

Other replies you may need:

- **A guest who has already signed out:** "We can only delete a guest account
  while you're signed in to it, because setting the code is how you show it's
  yours. Nobody can sign back in to a guest account after signing out, so we
  can't confirm this one, and it stays as it is."
- **An email or phone account:** they can also delete it themselves, by
  signing in to the iPhone app with the same email address or phone number
  and tapping Delete Account in Profile. Mention it, but don't require it.

## 2. Find the account

- **Email sign-in:** `--email <address>`.
- **Phone sign-in:** `--phone <+number>`, in international format, like
  `+15551234567`.
- **Guest (no email or phone):** in the Firebase console, open Firestore
  Database, filter the `users` collection on `display_name` equal to the
  code, and pass the document's id as `--uid <uid>`. If more than one
  document matches, send a new code instead of guessing.

With `--email` or `--phone`, the script prints the uid it found.

## 3. Dry run, then apply

```sh
unset HISTFILE
cd functions
node scripts/delete-account.js --email <address> --expect-name <code> --project treachery-71922
```

Check what it prints:

- the target: `project:  treachery-71922 (from --project)`, `LIVE Firestore` and
  `LIVE Firebase Auth`;
- the account: the display name is the code, and the masked email or phone
  matches the request. A display name shown with `(masked: it contains "@")`
  isn't the code: old versions of the apps named email accounts after their
  address;
- what deleting it would do.

When the dry run refuses, it exits 1 and changes nothing:

| It says | Do this |
|---|---|
| `no such account` | Check the address or number, or ask which one they sign in with. |
| `the display name is "…", not "…"` | They haven't set the code yet, or set it differently. Ask them to set it exactly. |
| `users/<uid> doesn't exist` | The account has a sign-in account but no profile. On a first run, ask them to sign in to Treachery on the web or Android, which makes one, then set the code and reply. After an `--apply` that exited 3, see below. |
| `is in, or hosts, a game in progress` | Reply that the account can be deleted once that game ends. A game with no activity for 24 hours is removed automatically. Then run it again. |

Then delete it, by the uid the dry run printed:

```sh
node scripts/delete-account.js --uid <uid> --expect-name <code> --apply --project treachery-71922
```

It prints the same report as the dry run, then
`deleting <uid> from treachery-71922 …` and what it deleted, ending with
`deleted the sign-in account:    yes` and a reminder to check on it in an
hour. It exits 0.

If it exits 3, its last line says how far it got:

- `failed: nothing was written.` It stopped before deleting anything. Read the
  error above that line: usually the credentials (log in again, or set the
  quota project), a missing permission, or the network. Fix that, then run the
  same command again.
- `failed: the deletion stopped part-way.` Run the same command again to
  finish: every step is safe to repeat. If that is refused because
  `users/<uid>` doesn't exist, the first run got as far as deleting the
  profile. It can still have left documents under it, such as `private/data`
  with their email address, phone number and push token, and the refusal
  names them. Delete the sign-in account in the Firebase console
  (Authentication, Users), then run the `--apply` command again: with no
  sign-in account or profile left, it deletes anything still under
  `users/<uid>` without checking the name. Time step 4 from when you deleted
  the sign-in account in the console, not from the first `--apply`.

## 4. Check it stayed deleted

The requester's web or Android app may still be signed in to the account.
Until that sign-in runs out, up to an hour after the sign-in account is
deleted, the app can write a new profile for the account, and the Android
app writes the email address or phone number back with it. So at least an
hour after the sign-in account was deleted, whether by `--apply` or by you in
the Firebase console, run the dry run again by uid:

```sh
node scripts/delete-account.js --uid <uid> --expect-name <code> --project treachery-71922
```

- `refused: no such account` (exit 1): it's done. Nothing is left under
  `users/<uid>` either.
- If it shows `sign-in providers:              none: no sign-in account`
  and lists documents after `documents left under it:`, an earlier run
  stopped before deleting them. Run the same command with `--apply` to
  delete them. It doesn't check the name: no account is left to check it
  against.
- If it shows the account again, with
  `sign-in providers:              none: no sign-in account` and a new
  display name such as "Player" or "Guest", an app wrote the profile again.
  Delete it by that name (if it's masked, read it from `users/<uid>` in the
  Firebase console):
  `--uid <uid> --expect-name '<that name>' --apply --project treachery-71922`.
  It ends with `deleted the sign-in account:    no, it was already deleted`
  and the reminder to check by uid. The hour since the sign-in account was
  deleted has passed, so no app can write the profile again: the check finds
  no such account straight away.

Check by uid, not by email or phone. Those look the account up in Firebase
Auth, where it is gone, so they report `no such account` even when the
profile is back.

## 5. Reply

> Your Treachery account is deleted. We deleted your sign-in account,
> profile, stats, friends list, friend requests and push token, and took you
> out of any lobby you were waiting in. In past games your name now shows as
> "Deleted player" and your commander name is removed; the role, life total
> and result stay so the other players' history still adds up. Google can
> take up to 180 days to clear deleted information from its backups. If
> Treachery still shows you as signed in on the web or Android, sign out.

## Accounts that break the rules, and children's accounts

To delete an account that broke the rules, or one we're told belongs to a
child under 13 (the privacy policy's Children section), rather than one its
owner asked about, pass its current display name as `--expect-name` and
follow steps 3 and 4. The check then still guards against a mistyped uid. If
the script shows the name masked, read it from the account's `users/<uid>`
document in the Firebase console.

## Rehearsing it

`npm run test:integration` runs the script against the emulators every time
(`functions/test/integration/callables/delete-account-script.test.js`). Add
`-- --test-name-pattern "delete-account script"` to run only its tests.

To try it by hand, start the Firestore and Auth emulators on the integration
suite's ports, from `functions/`:

```sh
firebase emulators:start --project demo-test --only auth,firestore \
  --config test/integration/callables/firebase.emulators.json
```

That config turns the Emulator UI off, so make an account from a second
terminal, also in `functions/`. The `node -e` command prints its uid:

```sh
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8288 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9299
node -e '
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
initializeApp({ projectId: "demo-test" });
getAuth()
  .createUser({ email: "lantern@example.com", password: "rehearsal-only" })
  .then((user) =>
    getFirestore().doc(`users/${user.uid}`).set({ display_name: "Lantern-4821" }).then(() => console.log(user.uid))
  );
'
```

Then run the dry run, the deletion and the check against it:

```sh
node scripts/delete-account.js --email lantern@example.com --expect-name Lantern-4821 --project demo-test
node scripts/delete-account.js --uid <uid> --expect-name Lantern-4821 --apply --project demo-test
node scripts/delete-account.js --uid <uid> --expect-name Lantern-4821 --project demo-test
```

Set both emulator variables or neither. With only one, the script refuses to
run, because it would delete from an emulator and from the live project at
once.
