# Usernames and friend profiles

Sign-in and signup failures display a native alert with an actionable message.
Incorrect credentials, unconfirmed email, weak passwords, and rate limits have
separate messages. A failed attempt retains the password for retry.

Signed-in users choose a unique username in Friends > Choose a username. Handles
are normalized to lowercase and use 3–20 letters, numbers, or underscores, starting
with a letter or number. Display names remain separate. Existing users do not
receive generated handles and are discoverable after choosing one.

Friends > Find friends searches username prefixes with at least two characters.
Results open a profile with the appropriate Add, Accept, Cancel, or Remove action.
The profile only shows progress after the friendship is accepted and the other
person enables sharing. Search and profile APIs never return emails or invite codes.
The previous friend-code APIs remain available to older app builds.

The run setup map shows accepted friends' shared virtual positions as blue markers
before a run starts, in both journey and explore modes. Hide friends / Show friends
controls visibility. The camera initially fits your position and planned route;
friends elsewhere remain available by panning or zooming. Markers reuse the cached
friend list and its existing foreground refresh, without adding server requests.

## Profile links

Share profile creates `https://kmogo.me/u/<username>`. Universal Links route this
path to the app; the HTTPS association includes only `/u/*` for this feature. The
fallback page offers `roam://profile/<username>` and manual username instructions.
It does not load account data from Supabase or sign the browser in. Invalid names
return 404. Changing a username changes the link; old links may stop resolving.

A profile link opened while signed out remains on the profile screen while the
user signs in. A link opened during a run waits until the run flow is dismissed.
Recovery and group-invite links keep their own routing.

The Roam target declares `applinks:kmogo.me` alongside `webcredentials:kmogo.me`.
The site's Apple association uses `X767SL92S7.com.roamstudy.Roam`. Verify this
against the signed app identifier if Patrick changes the signing team or prefix.
Install a build containing this branch to test profile routing. Apple caches
associations, so device verification may require reinstalling the updated build.

## Backend rollout and checks

Apply `supabase/migrations/202611270001_friend_usernames.sql` before shipping the
new app. It adds a nullable unique username and authenticated RPCs while retaining
existing friendships, sharing choices, Row Level Security, and old RPC signatures.
It does not alter auth passwords or email settings.

Run `supabase/tests/friend_usernames.sql` in a privileged SQL session after the
migration. Its fixtures use reserved test UUIDs and `.invalid` email addresses,
and the transaction rolls back every fixture and relationship. It checks handle
normalization/uniqueness, search bounds, private profile fields, friend request
states, opt-in progress, renaming, and removal. No emails are sent.

Device checks: verify the incorrect-password alert; choose a username; search a
second account; send and accept a request; toggle sharing; share a profile URL;
open it both signed in and signed out; and verify browser fallback, invalid names,
and existing recovery/group links.

On the run setup map, check friend markers and the visibility button in journey
and explore modes. Confirm pending requests and friends with sharing disabled
have no marker, distant friends do not widen the initial route camera, and normal
map taps still choose an explore destination. These map interactions need a signed
device or simulator UI check; the CI build only verifies compilation.
