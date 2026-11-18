# Run Roam with real app blocking on an iPhone

App Store Connect Admin access to an Individual membership does not supply development signing access. Use the account holder’s development signing setup to test Family Controls on a physical device.

## Fastest path: Patrick signs a development build

1. Open this working copy’s `Roam.xcodeproj` on Patrick’s development Mac. Check out `MP3-Roam`, which contains the app-blocking implementation.
2. Select Patrick’s paid team for BOTH the Roam and RoamMonitor targets. Keep automatic signing enabled.
3. Enable Family Controls (development) for both identifiers:
   - `com.roamstudy.Roam`
   - `com.roamstudy.Roam.Monitor`
4. Register the test iPhone’s UDID in the developer account.
5. Connect and unlock the iPhone, trust the development Mac, and enable Developer Mode on the iPhone if prompted.
6. Select the physical iPhone as the run destination, then build and run. This does not require a TestFlight upload or distribution entitlement approval.

For installation from another development Mac, Patrick can instead supply a development-signed IPA exported for this registered device, including the embedded monitor extension and valid Family Controls development profiles. No Apple account password needs to be shared. A signed IPA lets us install and test that build; it does not give this Mac permission to sign later code changes.

## Verify actual blocking

On the physical iPhone, turn on Block distracting apps, allow Apple’s Screen Time permission, choose an installed app, and start a run. Open the selected app and confirm the system shield appears. End the run and confirm the selected app opens normally. Also test timed completion while Roam is backgrounded.

Simulator builds intentionally show a labeled demo flow and sample apps. They do not enforce Screen Time restrictions.
