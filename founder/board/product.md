# Product lens
Score: 8/10 | Vote: FUND

## What is strong
- **Extreme Focus on Seamless Interaction**: Instead of another cluttered utility window with 40 tabs and dropdown menus, the interface is invisible until invoked via drag-and-drop or hotkey. It appears at the cursor, accepts the file, processes it, provides clean haptic/visual card feedback, and vanishes.
- **Craft and Local Autonomy**: Using native platform technologies (pure Swift + VisionKit on macOS; C# .NET 8 on Windows) instead of an Electron wrapper makes the app lightweight, instantaneous to launch, and respectful of system memory and battery.
- **End-to-End Control of the Experience**: From the non-intrusive floating progress cards to the zero-restart permission polling for Accessibility, the user flow demonstrates obsessive attention to friction points.

## What would kill it
1. **Feature Creep & Loss of Simplicity**: Expanding into a bloated photo editor, full video suite, or heavy document manager will destroy the lightweight "instant dial" essence.
2. **First-Run Friction / Permission Barriers**: On macOS, requiring Accessibility permissions for modifier key sniffing can scare away casual users if not onboarded with absolute elegance and transparency.
3. **Inconsistent Edge Case Failures**: In media conversion, corrupted files, unsupported codecs, or long video encodes can freeze background workers or spawn cryptic error popups.

## The questions I would ask the founder
1. What is the one core sentence that describes DropDial? (Answer: "Drag any file, drop it on the dial, converted instantly without leaving your app.")
2. What features have you deliberately refused to build to keep the app lightning-fast?
3. What is the fallback experience when a user converts a huge 4GB 4K video—does the system stay completely responsive?

## If FUND IF: the conditions
- **Condition 1**: Maintain aggressive zero-bloat discipline: never bundle unnecessary heavy UI frameworks or turn the app into an Electron shell.
- **Condition 2**: Ensure first-time onboarding explains the exact system permission rationale with immediate feedback and provides a 100% functional fallback (hotkeys and tray drag) if permissions are declined.
- **Condition 3**: Provide instant feedback on every drag: clear visual snap animations, unambiguous format icons, and quick desktop notifications with an "Open Folder" action.
