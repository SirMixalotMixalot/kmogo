# Password recovery and Password AutoFill

The sign-in form includes **Forgot password?**. It sends a Supabase recovery email
with the exact redirect `roam://auth/recovery`. Open the newest email on the same
iPhone that requested it: Supabase's PKCE verifier is stored on that device.

The app exchanges the callback code through the Supabase SDK before showing the
new-password form. Expired, used, invalid, and wrong-device links show an error.
Successful changes use the authenticated `auth.update(user:)` endpoint. No admin
key is used or shipped in the app. Cancel signs the recovery session out locally.

## Supabase configuration

Keep the Site URL and existing signup redirect at `https://kmogo.me/confirm/`.
Add `roam://auth/recovery` to Authentication > URL Configuration > Redirect URLs.
This exact URL was added to roam-dev when implementing the feature. The reset
password email must retain Supabase's `{{ .ConfirmationURL }}` link. Do not use the
public confirmation landing page as a password-reset form.

## Apple setup

The app uses `.username`, `.password`, and `.newPassword` content types. Successful
signup removes the credential form without first emptying the generated password;
failed requests retain it for retry. iOS and the user's password manager control
whether to offer saving; the app does not write a password to its own storage.

The Roam target declares `webcredentials:kmogo.me`. The website publishes:

`https://kmogo.me/.well-known/apple-app-site-association`

Its `webcredentials.apps` entry is `X767SL92S7.com.roamstudy.Roam`, matching this
project's team and bundle identifier. If Patrick builds under a different App ID
prefix, update this entry to match the signed app's `application-identifier`.

Patrick needs to enable **Associated Domains** for the **Roam** app identifier in
the Apple developer account, then refresh its provisioning profile or let Xcode
automatic signing regenerate it. The monitor extension has its own unchanged
Family Controls entitlement file; it does not need Associated Domains.

## Verification

The unit tests use an isolated mock HTTP transport and in-memory auth storage.
They test PKCE reset requests, generic responses, rejected/expired callbacks,
password validation, successful updates, cancellation, and callback routing.
They do not send emails or change a real user's password.

On a physical iPhone with Password AutoFill enabled:

1. Create a fresh account using iOS's suggested password. Confirm the password is
   saved in Passwords for `kmogo.me`, including when email verification is needed.
2. Complete email confirmation and use Password AutoFill to sign in.
3. Sign out, tap Forgot password, and request a reset. Open it on that iPhone.
4. Set a suggested replacement password, check it is saved, sign out, and sign in
   with the replacement. The previous password should fail.
5. Reopen the used link and test a link on a different device; neither should
   authorize a new reset. Existing group-invite links should still open normally.

Apple caches domain associations, so a correctly provisioned fresh install may be
needed while testing a newly published association. Simulator builds and unit tests
cannot verify the real iCloud Passwords save prompt.
